# Environments

> **TEMPLATE — populate after copying into a real repository.**
> Replace every `TODO: POPULATE` block. Leave a section as `N/A` if it does not apply.
> **Never** record credentials, connection strings, tokens, or private hostnames/IPs of sensitive
> systems here. Refer to secrets by name and storage location only.

## Environment Inventory

| Environment | Purpose | How to access | Data type (synthetic / copy / real) | AI agents allowed to |
|---|---|---|---|---|
| Local | Development | TODO | Synthetic | Read, write, run tests |
| TODO: Dev / Test | TODO | TODO | TODO | TODO |
| TODO: Staging | TODO | TODO | TODO | Read/inspect only unless approved |
| Production | Live customers | TODO | Real | **Read/inspect only; every change needs explicit approval** |

## Configuration Management
TODO: POPULATE — How configuration differs per environment and where it is defined.

## Secrets Management
TODO: POPULATE — Where secrets are stored (system name only) and who can access them.

## Deployment Process
TODO: POPULATE — How code is deployed to each environment, who approves, rollback procedure.
Production deployment always requires explicit human approval (see `CLAUDE.md` §7–8).

## External Service Modes per Environment
TODO: POPULATE — Which third-party accounts/modes (sandbox vs live) each environment uses.

## Observability
TODO: POPULATE — Where logs, metrics, traces, and alerts are viewed for each environment.

## Environment-Specific Behavior / Known Differences
TODO: POPULATE — Feature flags, data volume, scaling, or config differences that affect behavior.
