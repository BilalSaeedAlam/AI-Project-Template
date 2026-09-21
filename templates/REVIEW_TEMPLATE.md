# Review: <task title>

<!--
Copy to docs/reviews/YYYY-MM-DD-<slug>-review.md (same slug as the task).
Never copy secrets or customer data into a review; redact if found.
-->

| Field | Value |
|---|---|
| Task | docs/tasks/YYYY-MM-DD-<slug>.md |
| Branch / diff | <!-- e.g. main...task/<slug> --> |
| Review round | 1 |
| Date | YYYY-MM-DD |

## Severity Definitions
- **BLOCKER** — must fix before merge (incorrect behavior, data loss, security hole, broken build, violates approved architecture).
- **MAJOR** — should fix before merge (likely bug, missing error handling, significant regression risk, missing core tests).
- **MINOR** — fix recommended (maintainability, clarity, small inefficiency).
- **OPTIONAL** — suggestion only.

---

## Code Review (code-reviewer)

**Spec conformance:** Conforms / Partial / Does not conform — notes:

| # | Severity | Location | Finding | Suggested fix | Resolved |
|---|---|---|---|---|---|
| 1 | BLOCKER / MAJOR / MINOR / OPTIONAL | path:line | | | [ ] |

**Counts:** BLOCKER 0 · MAJOR 0 · MINOR 0 · OPTIONAL 0

---

## QA (qa-engineer)

**Verdict:** PASS / PARTIAL / FAIL

| Acceptance criterion | Evidence | Result |
|---|---|---|
| | | Met / Not met / Unverified |

**Tests run (command → result):**

**Coverage notes:** happy path · failure paths · boundary cases · regression

**Missing tests:**
- 

---

## Security Review (security-reviewer — only if applicable)

**Required:** Yes / No — reason:

| # | Severity | Location | Vulnerability class | Impact | Remediation | Resolved |
|---|---|---|---|---|---|---|
| 1 | | path:line | | | | [ ] |

---

## Final Review Status

**Status:** APPROVED / APPROVED_WITH_COMMENTS / CHANGES_REQUESTED / BLOCKED

- **APPROVED** — no BLOCKER/MAJOR findings; QA PASS.
- **APPROVED_WITH_COMMENTS** — no BLOCKER/MAJOR findings; MINOR/OPTIONAL items noted, or QA PARTIAL accepted by a human.
- **CHANGES_REQUESTED** — one or more MAJOR findings, or QA PARTIAL/FAIL needing work.
- **BLOCKED** — one or more BLOCKER findings, or cannot be reviewed (missing spec, build broken).

**Summary:**

**Required before merge:**
- 
