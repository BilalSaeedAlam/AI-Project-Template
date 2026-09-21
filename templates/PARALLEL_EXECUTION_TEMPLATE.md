# Parallel Execution Plan: <initiative title>

<!--
Copy to docs/tasks/YYYY-MM-DD-<slug>-parallel-plan.md
Complete this before running more than one task at the same time.
-->

| Field | Value |
|---|---|
| Date | YYYY-MM-DD |
| Planner | |
| Base branch | |
| Status | DRAFT / APPROVED |

## Tasks

| ID | Task file | Branch | Worktree path | Implementer |
|---|---|---|---|---|
| T1 | docs/tasks/... | task/... | | |
| T2 | | | | |

## Task Dependencies
<!-- "T2 depends on T1 (uses new API from T1)". -->

| Task | Depends on | Nature of dependency |
|---|---|---|
| | | |

## Overlapping Files
<!-- Files or modules more than one task will change. Assign an owner for each. -->

| File / module | Tasks touching it | Owner | Conflict risk (High/Med/Low) |
|---|---|---|---|
| | | | |

## Shared APIs / Contracts
<!-- Endpoints, interfaces, events, schemas used or changed by more than one task. -->

| API / contract | Changed by | Consumed by | Coordination needed |
|---|---|---|---|
| | | | |

## Database Migrations
<!-- Only one task should own migrations at a time unless ordering is explicit. -->

| Task | Migration | Order | Reversible | Conflicts with |
|---|---|---|---|---|
| | | | | |

## Shared External Systems
<!-- Sandboxes, webhooks, third-party accounts, queues shared between worktrees. -->

| System | Tasks using it | Isolation approach / risk |
|---|---|---|
| | | |

## Worktree Requirements
<!-- Per-worktree needs: local database, ports, config, sandbox accounts, seed data (no secrets). -->
- 

## Safe Parallel Groups

| Group | Tasks | Why safe to run together |
|---|---|---|
| A | | |
| B (after A merges) | | |

**Must run sequentially:**
- 

## Recommended Merge Order
1. 
<!-- After each merge: rebase remaining branches, re-run tests, re-check overlaps. -->

## Risks and Mitigations
- 
