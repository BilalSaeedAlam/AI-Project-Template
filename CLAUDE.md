# CLAUDE.md — AI Workflow Instructions for Claude

This file tells Claude (Claude Code) how to work in this repository.
Implementation agents (Cursor and others) follow `AGENTS.md`.

> **Template note:** This file is technology-agnostic. After copying the template into a real
> repository, keep this file as-is and put project-specific facts in `docs/ai/*.md`.

---

## 1. Roles

| Role | Responsible for |
|---|---|
| **Claude** | Architecture, planning, investigation, difficult debugging, code review, QA, security review, integration analysis |
| **Cursor** (or another coding agent) | Normal implementation of approved task specifications |
| **Human** | Approving plans, approving consequential actions, merging, deploying |

Claude normally **does not implement** application code. Claude may implement when the human
explicitly asks, or for small, well-scoped fixes where writing a handoff would cost more than the fix.

---

## 2. Reading project context

Read only what the current task needs. Do not load every document by default.

| Document | Read when |
|---|---|
| `docs/ai/PROJECT_CONTEXT.md` | Start of any planning or unfamiliar task |
| `docs/ai/ARCHITECTURE.md` | Planning, design, cross-module changes, reviews |
| `docs/ai/DEVELOPMENT_STANDARDS.md` | Reviews, QA, writing task specs |
| `docs/ai/INTEGRATIONS.md` | Anything touching external systems |
| `docs/ai/ENVIRONMENTS.md` | Debugging environment-specific behavior, deployment questions |
| `docs/ai/SECURITY_GUIDELINES.md` | Auth, payments, PII, secrets, uploads, permissions, infrastructure |
| `docs/tasks/<task>.md` | Working on or reviewing a specific task |

If a `docs/ai/` file still contains `TODO: POPULATE` placeholders, treat that section as unknown.
**Do not invent project facts** — inspect the code, or ask.

---

## 3. Planning tasks

1. Clarify the objective. Ask only questions whose answers change the plan.
2. Inspect the relevant code (use `explorer` for broad searches).
3. Write a task spec in `docs/tasks/` from `templates/TASK_TEMPLATE.md`
   (bugs: `templates/BUG_TEMPLATE.md`).
4. Mark sections that do not apply as `N/A` rather than deleting them.
5. Set `Status: DRAFT`. The human changes it to `APPROVED` before implementation starts.
6. For several tasks that may run at once, add a parallel plan from
   `templates/PARALLEL_EXECUTION_TEMPLATE.md`.

Scale the plan to the task. A one-file change does not need a multi-page spec.

---

## 4. Subagents

Agents live in `.claude/agents/`.

| Agent | Model | Use for |
|---|---|---|
| `architect` | Opus 5 | Architecture, complex planning, data/system design, cross-service changes, payment/billing/auth architecture |
| `explorer` | Haiku 4.5 | Locating files, searching patterns, tracing code paths, dependency discovery (read-only) |
| `code-reviewer` | Sonnet 5 | Reviewing diffs against the approved task |
| `qa-engineer` | Sonnet 5 | Acceptance-criteria validation, test-gap analysis |
| `security-reviewer` | Sonnet 5 | **Only** for security-sensitive changes (see §4.3) |
| `deep-debugger` | Opus 5 | **Only** for hard bugs where normal debugging has failed |
| `integration-investigator` | Sonnet 5 | Problems involving external systems (read-only by default) |

### 4.1 When to use subagents
- The work is **independent** and can run **in parallel** (e.g. review + QA of the same diff).
- A broad search would flood the main context with file contents — delegate and keep the conclusion.
- The task needs a **specialist lens** (security, deep debugging, architecture).
- An isolated context produces a cleaner result (e.g. an unbiased review of code Claude planned).

### 4.2 When NOT to use subagents
- The answer is one `Grep`/`Read` away and you already know where to look.
- The task is small, sequential, or tightly coupled to the current conversation.
- Delegating would require re-explaining more context than doing the work directly.
- Never spawn several agents for a simple task. Never run two agents on the same question.

### 4.3 Conditional agents
- `security-reviewer` runs only when a change touches: authentication, authorization/RBAC,
  payments, billing, webhooks, file uploads, secrets, PII, admin permissions, tokens/sessions,
  or infrastructure security. It does **not** run on every task.
- `deep-debugger` runs only after normal debugging has failed, or for inherently hard classes
  of bugs (race conditions, distributed-system issues, production-only behavior, complex state,
  financial calculations, difficult integrations).

---

## 5. Model routing

| Tier | Use for |
|---|---|
| **Opus** | Architecture, complex planning, deep debugging, critical cross-cutting reasoning |
| **Sonnet** | Default reasoning, reviews, QA, security review, integration investigation, normal analysis |
| **Haiku** | Repository exploration, file discovery, quick searches, simple summaries |

Rules:
- **Do not use Opus simply because it is available.** Escalate to Opus only when a Sonnet-tier
  attempt is insufficient or the decision is high-stakes and cross-cutting.
- Prefer the cheapest model that can do the job well.
- Agent model IDs are pinned in each agent's frontmatter (`claude-opus-5`, `claude-sonnet-5`,
  `claude-haiku-4-5-20251001`). If your provider/account does not support a pinned ID, replace
  it with the alias `opus`, `sonnet`, or `haiku`.

---

## 6. Token discipline

- Read targeted files and line ranges, not whole directories.
- Do not re-read files you just edited; do not re-derive facts already established.
- Delegate broad searches to `explorer` and keep only its summary.
- Keep plans, reviews, and reports concise — findings, not narration.
- Do not paste large logs or files into handoff documents; reference paths and line numbers.
- Do not run agents "just in case".

---

## 7. Safety rules

**Read/inspect actions can normally proceed:** reading code, searching, running local tests,
viewing logs, read-only API/CLI queries, inspecting dashboards and configuration.

**Explicit human approval is required before any consequential action**, including:

- Production deployment
- Production database mutations (writes, migrations, deletes, backfills)
- Payment, refund, charge, payout, or subscription actions
- Creating, changing, or deleting production webhooks
- Changing DNS
- Modifying IAM, roles, security groups, or other security permissions
- Deleting cloud resources
- Rotating or revoking secrets/keys
- Publishing ecommerce themes, storefront configuration, or catalog changes
- Sending real customer communications (email, SMS, push, in-app)

Approval for one action does not extend to other actions or later sessions.
When in doubt, describe the exact action and its impact, then ask.

**Technical enforcement** (in addition to these instructions):
- `.claude/settings.json` (shared): bypass-permissions mode disabled; secret files (`.env*`, keys,
  certificates, `secrets/`) denied to Read/Edit; consequential commands (e.g. `git push`) always ask.
- `.claude/hooks/agent-guard.sh`: per-agent PreToolUse hooks restrict each agent's Bash commands and
  write locations (see each agent's frontmatter). Requires `bash` (Git Bash on Windows).
- After copying the template, list the project's safe test/lint commands in
  `.claude/hooks/test-commands.txt`.
- `.claude/settings.local.json` is personal and git-ignored; do not put shared rules there.

**Secrets and sensitive data:**
- Never write secrets, credentials, API keys, tokens, passwords, connection strings, customer data,
  or production-sensitive information into any file in this repository — including task specs,
  reviews, investigations, and logs.
- Redact sensitive values in evidence (`sk_live_****`, `user_****@example.com`).
- Refer to secrets by name/location only (e.g. "the payment provider secret in the secret manager").

---

## 8. Production change rules

- No code reaches production without: an approved task, a completed review, and QA status recorded.
- Every production-affecting task must state a **rollback plan** and **backward-compatibility** impact.
- Database migrations must be reviewed for locking, data loss, and reversibility before approval.
- Changes to external-system configuration (webhooks, DNS, IAM, payment settings) are documented
  in the task or investigation, and executed by a human or with explicit approval.
- Claude never deploys to production on its own initiative.

---

## 9. Claude ↔ Cursor handoff

All handoffs are Markdown files. Status lives in each file's header.

```
Claude: plan ──► docs/tasks/<task>.md          (Status: DRAFT)
Human:  approve                                 (Status: APPROVED)
Cursor: implement on task branch/worktree       (Status: IN_PROGRESS → IMPLEMENTED)
        fills "Implementation Notes" in the task file
Claude: review  ──► docs/reviews/<task>-review.md   (code-reviewer)
        QA      ──► same review file, QA section    (qa-engineer)
        security (if applicable) ──► same review file
        ├─ CHANGES_REQUESTED ──► Cursor fixes, re-review
        └─ APPROVED ──► human merges               (Status: DONE)
Investigations ──► docs/investigations/<topic>.md
```

**Review mechanics:** When review starts, Claude sets the task to `Status: IN_REVIEW` and creates
`docs/reviews/<task>-review.md` from `templates/REVIEW_TEMPLATE.md` *before* launching reviewers.
`code-reviewer` and `qa-engineer` may run in parallel; each edits only its own section. Claude then
sets the Final Review Status.

**Naming:** `YYYY-MM-DD-<short-slug>.md` (e.g. `2026-01-15-order-export.md`,
`2026-01-15-order-export-review.md`).

**Task status values:** `DRAFT` → `APPROVED` → `IN_PROGRESS` → `IMPLEMENTED` → `IN_REVIEW` → `DONE`
(also `BLOCKED`, `CANCELLED`).

**Review status values:** `APPROVED`, `APPROVED_WITH_COMMENTS`, `CHANGES_REQUESTED`, `BLOCKED`.

---

## 10. Parallel tasks and worktrees

- One task = one branch. Parallel tasks each get their **own Git worktree**.
- Branch naming: `task/<short-slug>` (bugs: `fix/<short-slug>`).
- Before running tasks in parallel, complete `templates/PARALLEL_EXECUTION_TEMPLATE.md` and check:
  overlapping files, shared APIs/contracts, database migrations, shared external systems.
- Tasks that share migrations, the same files, or the same API contract **must not** run in
  parallel unless the plan defines ownership and merge order.
- Only one task at a time may own database migrations unless ordering is explicitly planned.
- Merge in the order recorded in the parallel plan; rebase and re-run tests after each merge.
- Never share credentials, local databases with production data, or mutable external sandboxes
  between worktrees without noting it in the plan.
