# Admin Role-Based Access Control Blueprint

## A reusable task series for building staff/admin permissions, audit logging, and staff MFA from scratch

This is a distilled record of a real admin-RBAC hardening series (T8a/T8b — permissions, invites,
audit log; T9a/T9b — staff TOTP MFA) run end-to-end on the same production-track SaaS app the
[`Auth_Flow_Blueprint.md`](./Auth_Flow_Blueprint.md) series covers: Node/Express + MongoDB backend,
two Next.js apps (customer-facing + admin), deployed on Cloud Run/Vercel. `Auth_Flow_Blueprint.md`
scoped this work as its own T8 but explicitly left it unbuilt ("treat its objective/closes/
depends-on as a starting design"). This document is what actually got built when that task ran for
real, plus one worked example (an admin-initiated Stripe refund/plan-change feature) showing how to
safely add a **new** admin action on top of the finished RBAC rail later, without re-deriving the
pattern from scratch each time.

**Stack assumption:** Node/Express + MongoDB/Mongoose backend, a separate staff-facing Next.js (or
similar SPA) app, JWT access tokens with an existing session/audience architecture (see
`Auth_Flow_Blueprint.md` §1 "Sessions and tokens" — this series assumes that already exists; admin
sessions specifically need a `mfa`-audience concept). If your stack differs, the *architecture
decisions* and *task order* still apply — only the specific APIs/libraries named below (`otplib`,
Mongoose `pre` hooks, Express router introspection, etc.) need substituting.

**Depends on:** `Auth_Flow_Blueprint.md` T4 (session/audience separation) at minimum. T6 (OAuth) and
T7 (credential-change notification patterns) are reused by the staff invite flow below, so running
this series after those is the well-trodden order — not a hard requirement if your project already
has equivalent primitives.

**How to use this:**
1. Give this file to Claude alongside `Auth_Flow_Blueprint.md` with:
   *"Review this against our actual admin/staff code and draft task specs from
   `templates/TASK_TEMPLATE.md`, following `CLAUDE.md`'s plan → approve → implement → review
   workflow."*
2. Treat this as a **starting design**, not gospel — Claude must read the real codebase, confirm
   what already exists (a coarse single "admin" role is the typical starting point), and adjust
   scope accordingly.
3. Tasks can run in the order given, or a later section can be read standalone (e.g. just the audit
   log pattern, or just the "adding a new admin action" worked example in §6, on a project that
   already has permissions but no audit trail).

---

## 0. What this covers

1. **Explicit permission strings** (`users.manage`, `billing.read`, ...) instead of one coarse
   `admin` role — resolved server-side per request, never trusted from a JWT claim.
2. **A super-admin tier** reserved for the most dangerous actions (staff management, permission
   grants, deactivate/reactivate staff, MFA reset for other staff) — never delegable.
3. **A drift-detection mechanism** that fails a build/test run the moment a new admin route is added
   without an explicit permission mapping — the actual hard part of RBAC, since "we'll remember to
   gate the next endpoint" is not a control.
4. **An append-only audit log** for every admin action, with a field-level allow-list so nothing
   sensitive (passwords, tokens, raw request bodies) can leak into it even by future mistake.
5. **A staff invite flow** — no admin-chosen plaintext password, same single-use-token machinery as
   the rest of the auth system.
6. **Mandatory TOTP MFA for every staff account**, including the super admin, with recovery codes
   and an operator-only "break-glass" CLI reset for when a staff member is fully locked out.
7. A repeatable **pattern for adding a new admin action** later (§6) — the account-action wrapper +
   audit event shape every future "admin does X to a customer/staff account" feature should follow.

---

## 1. Target architecture (build this once, all tasks build on it)

### Permission model
- A small, fixed catalog of dotted permission strings (`users.read`, `users.manage`, `billing.read`,
  `billing.manage`, ...) — group by resource, and make `.manage` imply `.read` at normalization time
  so you never have to grant both explicitly. Keep the catalog under ~15 entries; if it's growing
  past that, you probably need resource-scoped permissions (e.g. per-team), which is a bigger
  redesign than this document covers.
- **One function is the sole authority** for what a user can actually do —
  `effectivePermissions(user)`: `super_admin` → the full catalog, computed, **never read from
  storage** (a super admin's own `permissions` field, if it even exists, is irrelevant); `admin` →
  `stored ∩ catalog` (defends against a stale/legacy value containing a permission that's since been
  removed from the catalog); anything else, including a missing or malformed field → `[]`,
  **fail-closed**. Every authorization check in the codebase must call this function, never read the
  raw stored field directly.
- Validate permission lists at every write boundary: reject unknown strings outright (don't
  silently drop them — a typo'd permission string should be a loud 400, not a silent no-op grant).
- Keep named **presets** (e.g. "support", "billing", "full") as a UI convenience only — the server
  always stores and checks the resolved list of strings, never a preset name, so a preset's
  definition can change later without needing a data migration.
- Never let any endpoint write `role` or `permissions` from request input for arbitrary self-service
  use — every place a role is set should be a hardcoded literal at a specific, audited call site
  (account creation, staff invite, explicit super-admin-only permission-grant endpoint). Grep for
  every `role:`/`permissions:` write in the codebase during review and confirm each one is one of
  those call sites, not something reachable generically.

### The drift-detection mechanism (the part that actually makes RBAC hold up over time)
A permission catalog is worthless if a developer can add `router.post("/new-thing", handler)` next
month and forget to gate it. Build a script that:
1. **Walks the live router at runtime**, not a hand-maintained list — introspect your framework's
   actual mounted routes (Express: `app._router.stack`) so the check can never drift from what's
   really being served.
2. Maintains an **explicit, enumerable table** mapping route prefixes/patterns to required
   permissions (not a function with hidden fallthrough logic — a literal array of
   `{prefix, permission}`-shaped entries you can iterate and assert against independently).
3. Checks **both directions**: every live route must resolve to a table entry (`policyFor(route)`
   returns non-null), **and** every table entry must match at least one live route (catches a stale
   policy entry left behind after a route was deleted — otherwise the table silently grows
   meaningless entries forever).
4. Diffs the full sorted route-signature list against a **committed snapshot file** — this catches a
   new route the moment it's added, even before anyone thinks to check whether it needs a policy
   entry at all.
5. Then **actually exercises every route over real HTTP** with a small fixture matrix (anonymous,
   wrong-permission staff, exact-permission staff, super admin) and asserts the real status codes —
   a static table check alone proves the table is self-consistent, not that the real middleware
   chain enforces it.
6. **Prove the negative-control direction actually works**, don't just write it and trust it. The
   most common mistake here: building the "policy entry has no matching route" check from data
   derived from the *same* source it's supposed to be independently checking, making it
   structurally incapable of ever failing. Verify by deliberately injecting a fake orphaned entry
   during development and confirming the check fails — then remove the injection. A test that has
   never been observed to fail is not proven to work.
7. Every admin route mount ends in an explicit catch-all that returns 401 (unauthenticated) or 404
   (authenticated, no matching route) — never a "not implemented yet" stub that silently differs
   from a real 404 and could mislead a route-existence probe.

### Append-only audit log
- **Schema**: `at`, `actorId`/`actorRole` (nullable, for system/anonymous events), `action` (a
  strict enum — see below), `outcome` (`success`/`denied`/`failed`), `targetType`/`targetId`,
  `before`/`after` (structured, allow-listed — see below), `request` summary (`method`, `route`,
  `status` — never the raw body), `meta` (allow-listed), a hashed IP (never raw), and a TTL/expiry
  field for retention.
- **`action` is a strict enum**, not a free string — an audit action that isn't in the enum fails
  schema validation. This is deliberate: it forces every new admin action to explicitly register its
  audit action name (a one-line addition) rather than silently going unaudited because a call site
  used a slightly different string than expected.
- **Enforce append-only in application code**: register `pre` hooks on every mutating query
  operation your ORM exposes (update-one, update-many, find-and-update, replace, delete-one,
  delete-many, find-and-delete, find-and-replace — get the full list for your ORM, it's usually
  longer than people expect) that throw synchronously, plus a `pre("save")` hook that throws for any
  non-new document. Grep the whole codebase for any use of this model outside `create`/read
  operations as part of review — this needs to stay true forever, not just at ship time.
  Application-level enforcement is a good default; true database-level enforcement (a restricted
  DB role with no update/delete grant on this collection) is a stronger follow-up but usually needs
  infrastructure/IAM changes outside a single task's scope — track it as a deliberate, explicit
  follow-up rather than silently skipping it.
- **Centralize the field allow-list in the write path, not at each call site.** Two lists —
  one for `before`/`after` state keys, one for `meta` keys — checked unconditionally inside the one
  shared `recordAuditEvent`-style function every caller goes through. This is stronger than asking
  every call site to remember to sanitize its own payload: a future call site that's careless about
  what it passes in still can't leak anything, because the writer itself drops anything not on the
  list before it ever reaches the database. Never allow-list anything that could be a
  credential, token, raw email, or full request body.
- **The audit write must be best-effort and must never throw back to the caller.** Wrap it in
  try/catch; on failure, log it and move on. The user's actual request should succeed or fail on its
  own merits — an audit-log outage must never become a user-facing outage. (This is a real
  availability/reliability decision worth stating explicitly in review, since the instinct to "fail
  the action if we can't audit it" is common and wrong for most products.)
- **Two tiers of audit coverage**, so you get completeness without hand-instrumenting every route:
  - **Tier 1, automatic**: a middleware on the whole admin mount that records a generic "admin made
    a mutating request" event for every non-GET admin request, using only the method/route/status —
    never reading the request body. This guarantees nothing is silently unaudited even before a
    developer adds tier-2 detail for a specific action.
  - **Tier 2, explicit**: the specific service functions for genuinely significant actions
    (deactivate account, reset password, change permissions, refund a payment, ...) call the audit
    writer directly with real `before`/`after` state and a specific, meaningful `action` name.
- Reads should be restricted to the super-admin tier, support filtering by actor/target/action, and
  resolve human-readable labels at read time (a staff member's real email; a customer's masked
  email) rather than duplicating denormalized display data into every audit row at write time.

### Staff invite flow (no admin-chosen password)
Reuse the single-use-token machinery from `Auth_Flow_Blueprint.md` §1 exactly — this is not a
special case:
1. Super admin submits an email + a starting permission set. The created account has **no password
   hash at all** — not a temporary one, not admin-set-then-forced-to-change. `passwordHash: null`.
2. A single-use, purpose-scoped token (same collection, same atomic-consume pattern as email
   verification/password reset) is minted and mailed as an accept link.
3. The invitee visits the link, sets their own password (through the same shared password policy
   module every other password-setting path uses), and the token is atomically consumed.
4. The accept mutation should be a **conditional write** guarding against races — e.g. only succeeds
   if the account still has no password hash and hasn't been revoked in the meantime, so a
   concurrent "revoke this invite" from the super admin and "accept" from the invitee can't both
   apply.
5. Resend/revoke both need their own cooldown/conditional-write guards for the same reason — see
   `Auth_Flow_Blueprint.md`'s single-use-token guidance generally.
6. If your project also builds staff MFA (below), the invite-accept step should hand off directly
   into mandatory MFA enrollment rather than issuing a session immediately — there should be no
   window where a freshly-accepted staff account has a live session without MFA.

### Mandatory staff MFA (TOTP)
- **No skip, no grace period, for every staff role including the super admin.** The cleanest way to
  enforce this: make session issuance itself refuse to create an admin-audience session without an
  `mfa` flag/claim present. Don't rely on a UI-level "please enroll" prompt that a client could
  route around — enforce it at the point the session is actually minted, server-side.
- **Two-step login for the admin audience**: a correct password returns a short-lived MFA
  *challenge* (not a session, not a cookie) — `nextStep: "mfa_verify"` for an already-enrolled
  account, `"mfa_enrollment"` for a first-time login. The challenge can reuse your existing
  single-use-token collection (a new `purpose` value) rather than inventing a parallel mechanism —
  short TTL (minutes), a burn-on-attempts counter, and — this is the detail worth calling out
  explicitly — **bind the challenge to the account's current `tokenVersion`** (or equivalent
  revocation counter) at issuance, so any unrelated security event (password reset, sign-out-
  everywhere, an MFA reset) automatically invalidates any outstanding MFA challenge for free,
  without needing a separate cleanup step.
- **Store the TOTP secret encrypted at rest** (not merely hashed — you need to read it back to
  verify codes), with the encryption key separate from your JWT signing secret, and bind the
  encryption's associated data to the user id so a secret can't be silently swapped between
  accounts at the storage layer.
- **Recovery codes**: a fixed batch (8–10 is typical) of high-entropy, single-use, hashed-at-rest
  codes issued once at enrollment and shown to the user exactly once. Exempt recovery-code attempts
  from your normal TOTP-guessing lockout (a recovery code is high-entropy enough that lockout isn't
  needed for its own sake), but still apply your generic per-challenge attempt counter and per-IP
  rate limit — the goal is "an attacker who also stole the password still can't get in," not
  "a legitimate user can hammer recovery attempts forever."
- **Self-service MFA management** (regenerate recovery codes, replace authenticator) should require
  a fresh step-up (password + current code), and replacing an authenticator should revoke the
  caller's *other* active session families — an authenticator swap is exactly the moment you want to
  make sure an attacker who compromised the old device loses access everywhere else too.
- **Super-admin-initiated reset for another staff member** is a real operational need (lost device)
  and should go through the same account-action guard pattern as any other admin-on-staff action
  (§ below) — explicitly refuse to let it target the super admin's own account, and route it through
  the shared self/target-authorization helper rather than duplicating the checks inline (see the
  "duplicated auth checks drift" lesson in §5).
- **Build one true break-glass path**: an operator-only CLI script, never HTTP-exposed, for the case
  where the super admin's own MFA is unrecoverable and there's no other super admin to reset it.
  Concretely:
  - Dry-run by default; require an explicit `--apply` flag and a confirmation value that echoes back
    something identifying the target (e.g. `--confirm=<their email>`), refusing to proceed on a
    mismatch — this is the same "hard to fat-finger" pattern as a production database migration
    script, and for the same reason.
  - Print exactly what's about to change (account, role, current enrollment state) before writing.
  - This path should be allowed to target the super admin specifically (that's the whole point of
    it existing), unlike the HTTP-level reset endpoint.
  - Still writes an audit event, with a distinguishing `meta.via` value and a null actor id (there's
    no authenticated admin actor — this was run by someone with direct infrastructure/database
    access, and the audit trail should say so honestly rather than fabricate an actor).
  - This grants **no new capability** beyond what direct database access already implies — it exists
    for auditability and to avoid a bespoke manual Mongo shell command becoming the actual runbook.

---

## 2. Task series

### T8a — Backend: permissions, drift-check, audit log, staff invites
**Objective:** Build everything in §1 except MFA: the permission model, `effectivePermissions`,
every admin route re-gated by permission instead of a coarse role check, the route-policy
drift-check script + snapshot, the append-only audit log with its allow-lists, and the staff invite
flow.
**Closes:** every admin capability being reachable by any account with the `admin` role; no
mechanism to catch a future ungated route; no audit trail; admin-chosen plaintext passwords for new
staff.
**Depends on:** `Auth_Flow_Blueprint.md` T4 (audience separation).
**Carry forward:** write a **migration** for existing admin accounts *before* deploying the
permission-gated code — a missing `permissions` field resolves to `[]` under the fail-closed rule,
so deploying code first locks out every existing admin until the migration runs. Sequence this
explicitly in the task, don't leave it implicit.

### T8b — Admin app: permission-gated UI, staff management screen, audit viewer
**Objective:** Mirror the permission catalog client-side for UI gating (nav items, buttons), build
the staff invite/list/permission-editing screens (super-admin only), and an audit log viewer.
**Closes:** UI showing actions a caller's permissions don't actually allow (confusing, and a
support/trust problem even though the backend still enforces it); no way to invite/manage staff
without going around the app.
**Depends on:** T8a (the real endpoints and permission catalog this mirrors).
**Carry forward:** client-side permission gating is a UX nicety, not a security boundary — say this
explicitly in the task and verify it in review by confirming the *backend* 403s independently of
whatever the UI shows, not by trusting that a hidden button means the action is actually blocked.

### T9a — Backend: mandatory staff TOTP MFA
**Objective:** Everything in §1's MFA section — two-step login, enrollment, recovery codes,
self-service management, super-admin-initiated reset, and the break-glass CLI.
**Closes:** a compromised staff password being sufficient for full admin access on its own, given
the blast radius of an admin account.
**Depends on:** T8a (the permission/audit rail an MFA reset action reuses), `Auth_Flow_Blueprint.md`
T4 (session/tokenVersion architecture the challenge-binding relies on).
**Carry forward:** if your user model has existed since before a revocation counter
(`tokenVersion` or equivalent) was introduced, **do not assume every row has it populated** just
because the schema declares a default. A schema default only applies to documents created *after*
the field was added; an old document can have the field genuinely absent at the database level, and
a conditional write requiring an exact match against it (a common MFA-enrollment pattern) will
silently fail only for that row. Write and run an idempotent backfill migration as part of this
task, and test against a real pre-existing account shape, not only freshly-created test fixtures
(which always get the schema default applied).

### T9b — Admin app: MFA enrollment, login, and self-service UI
**Objective:** The two-step login UI (password → QR code/manual key → code entry → recovery codes
shown once), self-service recovery-code regeneration and authenticator replacement, and the
super-admin-facing "reset this staff member's MFA" action.
**Closes:** no client for the T9a flows.
**Depends on:** T9a.
**Carry forward:** if you build destructive-action confirmation with the platform's native
`confirm()`/`alert()` dialogs anywhere in the admin app, replace them with an in-app confirmation
modal *before* this task if automated browser verification matters to your workflow — native browser
dialogs generally cannot be driven by headless/automated tooling, which silently blocks live
verification of exactly the actions (staff close/reopen, MFA reset) that most need it. Do not work
around this by scripting `window.confirm` to auto-accept from page code — that defeats the
confirmation's actual purpose and most agent sandboxes will (correctly) refuse to do it.

---

## 3. Task ordering and parallelism

```
Auth_Flow_Blueprint T4 ──► T8a ──┬──► T8b
                                 │
                                 └──► T9a ──► T9b
```

- T8a must land (including its pre-deploy migration) before T8b, since T8b is a thin client over
  T8a's real endpoints and permission catalog.
- T9a depends on T8a's audit/permission rail (the MFA-reset action is itself an admin action that
  should go through the same guard and audit pattern) but not on T8b — T9a/T9b can run while T8b is
  still in progress if you have the parallel capacity, since they touch mostly disjoint files (auth/
  MFA modules vs. staff-management screens), but confirm this on your actual codebase before
  assuming it — if both touch the same login-page component, don't parallelize.
- Both T8a and T9a are backend-first, app-second pairs — don't try to build the UI ahead of the real
  endpoints it calls; you'll just be guessing at the response shape.

---

## 4. What "done" looks like for the whole series

- No admin route exists that isn't provably gated by an explicit permission — provably meaning a
  test that walks the live route table and fails loudly the moment a new ungated route appears, not
  a manually-maintained checklist.
- A super admin's capabilities are computed, never stored — there is no data path by which a
  super-admin's own `permissions` field (if it exists at all) matters.
- No admin action changes account state, permissions, or a customer's paid resources without an
  audit event recording who did what to whom — and no audit-log outage can block the action itself
  from succeeding.
- Nothing sensitive (a password hash, a token, a raw request body, a TOTP secret) can appear in the
  audit log even by a future developer's mistake, because the writer itself drops anything not on an
  explicit allow-list.
- Every staff account requires TOTP MFA before it can hold a live admin session — there is no
  code path, including a freshly-accepted invite, that reaches a working admin session without it.
- Every admin action that targets another account (deactivate, reset password, reset MFA, refund a
  payment, change a plan, ...) refuses to target the actor's own account and refuses to target the
  super admin's account from a non-super-admin caller — enforced by one shared helper, not
  duplicated per action.
- A super admin who is fully locked out (lost device, no other super admin) has exactly one documented
  recovery path, requiring direct operational/infrastructure access, not an HTTP endpoint.

---

## 5. Notes from running this the first time (things that cost real back-and-forth)

- **A negative-control test built from the same data it's supposed to independently check can never
  fail — verify this by deliberately breaking it once.** The route-policy drift-check's "does every
  policy entry have a matching route" direction was originally derived from the same source set it
  was meant to validate, making it structurally incapable of catching a real problem. This wasn't
  caught by writing the test or by it "passing" — it was caught by asking "what would make this
  fail?", and confirmed fixed by injecting a fake orphaned entry and watching the fixed version
  correctly fail on it, then removing the injection. Apply this generally: for any test whose whole
  job is to catch an absence (a missing gate, a missing entry, a missing check), don't trust it until
  you've watched it fail on a deliberately broken case.
- **A test harness's stub can silently not apply if the real gate sits one layer above the stub
  point.** A mail-sending stub replaced the function that sends mail, but an earlier, ungated
  "is mail even configured" check ran before ever reaching the stub — so a test claiming to cover
  "mail unconfigured" behavior only actually worked because the local environment happened to have
  real mail credentials loaded, and would have failed reproducibly in a genuinely unconfigured CI
  environment. When building a stub/mock seam, put it at the *outermost* function every code path
  actually calls, not at a lower-level function that has its own preconditions above it.
- **The same shape of finding — a shared authorization helper re-implemented inline instead of
  called — showed up independently in two different tasks.** Once is a one-off; twice in a row
  during the same series is a pattern worth calling out explicitly in review going forward: whenever
  a new admin action needs "can this actor act on this target," it should call the one shared
  helper, never reproduce its three-or-so checks by hand, even when the reproduction is currently
  equivalent. Equivalent-today code drifts silently; a shared call site can't.
- **A schema field's default value is not the same guarantee as "every row has this field."** A
  revocation counter had existed in the schema for a while, with a declared default, before any code
  did an *exact-value conditional write* against it. That combination — old rows, a field added after
  they were created, and a later feature that needs an exact match rather than just reading-with-
  fallback — is exactly the shape that breaks in production and passes every test built only against
  freshly-created fixtures (which always get the schema default applied at creation time). When a new
  feature introduces the *first* exact-match conditional check against an existing field, specifically
  test it against a legacy-shaped row, not only fresh ones.
- **Copying a UI restriction "by analogy" from a similar-looking button onto a different action is an
  easy, easy-to-miss mistake.** One destructive-action button correctly hid itself for accounts in
  certain states because the underlying endpoint required that precondition; a second, genuinely
  different button was given the identical hiding rule by pattern-matching on "it looks like the same
  kind of button," even though its endpoint had no such precondition. The fix is cheap once spotted,
  but spotting it requires checking each UI restriction against its *own* endpoint's actual
  preconditions, not against a neighboring button's.
- **A platform's native confirmation dialog (`window.confirm`, `alert`) is often invisible to
  automated browser-driving tools**, which silently blocks live verification of exactly the actions
  most worth verifying live (irreversible staff/account actions). Don't paper over this by scripting
  the dialog to auto-accept — that removes the actual safety property, not just the testing
  friction. Replace native dialogs with an in-app confirmation modal if live-verification matters to
  your workflow; it also gives you a consistent "danger tone" pattern to reuse for every future
  destructive admin action (see §6).
- **Sequence a pre-deploy data migration explicitly in the task spec when the new code's authorization
  is fail-closed on a field that might not be populated yet** — "deploy code, then run migration" and
  "run migration, then deploy code" produce very different (and in the fail-closed case, very
  different-severity) outcomes for existing users, and it's easy to leave this implicit and get it
  backwards under deploy pressure.

---

## 6. Worked example: adding a new admin action after the series is done

Once T8a/T9a are in place, every *new* "admin does something consequential to a customer or staff
account" feature should follow the same shape — this section is a concrete worked example (an
admin-initiated payment refund and subscription plan change), written after the RBAC series above
was already live, to show the pattern holds up for something genuinely new rather than just
re-describing the original build.

**The pattern, concretely:**
1. **A pure domain function** that does the real work (call the payment provider, mutate the
   resource) and knows nothing about "who's allowed to call this" — it takes a target id and
   whatever the action needs, and throws a typed, status-coded error for each real failure mode (not
   found, already in the requested state, upstream rejected it). If an equivalent self-service
   version of the same action already exists for the resource's owner (e.g. a customer changing
   their own plan), **extract and share the core logic** between the two rather than writing a
   parallel implementation — the admin path should do exactly what the self-service path does, just
   on someone else's behalf.
2. **A thin wrapper function**, one per action, that: loads the target account, calls the shared
   "can this actor act on this target" guard (§1's self/super-admin/staff-target helper — never a
   bespoke reimplementation), delegates to the pure domain function through a **swappable hook**
   (a module-level `{ actionName?: typeof realFunction }` object that automated tests can override to
   avoid hitting a real third-party API, while everything else — the authorization guard, the audit
   write, the revocation logic — still runs for real), records an audit event on success with real
   before/after or meta detail, and maps the domain function's typed errors to your HTTP error type
   with the same status code.
3. **A route**, gated by the specific permission the action needs (not necessarily the coarsest
   permission for that resource — a refund is a `billing.manage`-level action even if merely viewing
   billing only needs `billing.read`), that does nothing but call the wrapper and shape the response.
4. **Extend, don't bypass, the drift-check table and audit-action enum** — add the new route to the
   policy table and snapshot, and the new action name to the audit enum, as part of the same change.
   If either is missed, the drift-check script (route side) or the schema validator (audit side)
   should fail the build — confirm both actually do.
5. **Sanitize third-party errors before they reach the caller.** A raw upstream API error can echo
   request parameters or expose internal identifiers; catch the provider's specific error type,
   map known error codes to a short, safe, specific message (a stable error-code field the provider
   publishes, not its free-text message field, which can vary and isn't guaranteed safe to display),
   and fall back to a generic "the provider rejected this, no changes were made" for anything
   unrecognized. Never let a generic 500 be the *only* outcome for a real, expected failure mode
   (e.g. "this was already refunded") — the caller should get a clear, specific answer for the cases
   you know can happen, and a safe generic one only for cases you don't.
6. **Gate the UI control on the actual precondition, not just on permission.** A button that's
   visible to anyone with the right permission but 404s when clicked on ineligible targets is a
   correctness gap even though it's not a security one — extend whatever list endpoint powers the
   UI to include the eligibility flag the button needs, rather than leaving the UI to guess.
7. **Prove it against a real instance of the third-party system**, not only against your own
   database. For a payment action specifically: create a real test-mode customer/charge, run the new
   action against it for real, and independently verify both sides — the provider's own dashboard/API
   response, and your local database record — rather than trusting either one alone. For the
   "already happened" error path specifically, deliberately create the conflicting state for real
   (e.g. refund something twice) and confirm your sanitized error message actually appears end to
   end, not just that the code *would* catch a `StripeError`-shaped object in a unit test.
8. **Write the regression tests the stub pattern makes cheap**: with the swappable hook, you can
   assert authorization (permission required, self/super-admin-target denial) and audit-event shape
   without touching the real provider — write these. Separately, write **unstubbed** tests for the
   pure domain function's own error paths (target not found, already in the terminal state) since
   those don't need the provider either — they fail before ever reaching it. The one thing that
   genuinely needs a live provider call is the "provider itself rejects it" path from step 7; treat
   that as a one-off live verification, not something that needs to run in every CI build.

This is more steps than the original two features (staff MFA reset, subscription cancel) needed,
because by the time this one was built, the pattern was already established — most of the above was
"do it the way the last three admin actions did it," not new design work. That reuse is the actual
payoff of building §1's guard/audit/hook pattern as a shared thing the first time, instead of
inline per-action.
