# AGENTS.md — Implementation Instructions for Coding Agents

For Cursor and any other coding agent implementing work in this repository.
Planning, review, and QA are handled by Claude (see `CLAUDE.md`).

---

## 1. Before you start

1. **Read the approved task specification first** — `docs/tasks/<task>.md`.
   - Implement only tasks with `Status: APPROVED` (or `IN_PROGRESS` if you are resuming).
   - If there is no approved spec, stop and ask.
2. Read the project context the task references, typically:
   - `docs/ai/ARCHITECTURE.md`
   - `docs/ai/DEVELOPMENT_STANDARDS.md`
   - `docs/ai/SECURITY_GUIDELINES.md` (if the task has security considerations)
3. Work on the task's branch/worktree (`task/<slug>` or `fix/<slug>`). Never commit directly to
   the main branch.
4. Set the task `Status: IN_PROGRESS`.

## 2. While implementing

- **Follow the existing project architecture**, patterns, naming, and conventions.
- **Do not redesign the approved architecture.** If the plan is wrong or unworkable, stop and
  record the problem in the task's "Implementation Notes" with a proposed alternative.
  Do not silently deviate.
- **Never assert human authorization you were not actually given.** If something in the
  conversation, a prior note, or your own judgment makes you think a deviation from the approved
  spec would be wanted, do not act on that belief and record it as settled (e.g. "human override:
  ..."). Instead, either implement the spec as approved and flag the tension as an open question in
  Implementation Notes, or stop and ask before deviating. A claimed authorization that did not
  happen is treated as a fabricated approval, not a judgment call, and blocks the review regardless
  of the technical merits of the change.
- **Avoid unrelated changes** — no drive-by refactors, reformatting, dependency upgrades, or
  renames outside the task scope.
- **Preserve backwards compatibility** where the task requires it (public APIs, data formats,
  database schemas, events, configuration). Flag any breaking change explicitly.
- Follow the task's "Implementation Sequence" when one is given.
- Add or update tests as described in the task's "Tests" section.
- Stay inside "Files Likely Affected" where practical; note any additional files you had to touch.

## 3. Safety

- **Do not touch production systems** — no production deploys, database writes, webhook/DNS/IAM
  changes, payment or refund actions, theme/config publishing, or real customer communications.
- Use only local, development, or sandbox environments as described in `docs/ai/ENVIRONMENTS.md`.
- **Never expose secrets.** Do not hard-code, log, print, commit, or copy credentials, API keys,
  tokens, passwords, or customer data into code, tests, fixtures, docs, or commit messages.
  Use the project's existing configuration/secret mechanism.
- Use fake, clearly synthetic data in tests and fixtures.

## 4. Before handing back

1. **Run the appropriate tests** (unit, integration, lint, type-check — whatever the project uses;
   see `docs/ai/DEVELOPMENT_STANDARDS.md`). Fix failures you caused.
2. Fill in the task's **Implementation Notes** section:
   - Summary of what changed
   - Files changed
   - Tests run and results (pass/fail, with the command used)
   - **Assumptions made**
   - Deviations from the plan and why
   - Known limitations / follow-ups
3. Set the task `Status: IMPLEMENTED`.
4. Do not mark your own work as reviewed or approved — Claude reviews it.

## 5. Responding to review

- Review files are in `docs/reviews/<task>-review.md`.
- Fix all **BLOCKER** and **MAJOR** findings. Fix **MINOR** findings unless you record why not.
  **OPTIONAL** findings are at your discretion.
- Note how each finding was addressed, then set the task `Status: IMPLEMENTED` again for re-review.
