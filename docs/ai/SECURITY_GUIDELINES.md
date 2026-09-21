# Security Guidelines

> **TEMPLATE — populate the project-specific sections after copying into a real repository.**
> The **Baseline Rules** apply to every project and should be kept.
> Never record secrets, credentials, or customer data in this file.

## Baseline Rules (apply to all projects)

1. Never commit or write secrets, credentials, API keys, tokens, passwords, or connection strings to
   the repository or to any AI handoff document (`docs/tasks`, `docs/reviews`, `docs/investigations`).
2. Never copy customer data or production-sensitive information into code, tests, fixtures, docs, or logs.
   Use synthetic data.
3. Redact sensitive values in evidence (e.g. `sk_live_****`, `user_****@example.com`).
4. Enforce authorization server-side on every entry point; never trust client-supplied roles,
   prices, amounts, or status values.
5. Validate all input at trust boundaries.
6. Verify webhook signatures and handle webhook events idempotently.
7. Apply least privilege to service accounts, API keys, and IAM roles.
8. Do not log secrets, tokens, full payment details, or unnecessary PII.
9. Read/inspect actions may proceed; consequential actions require explicit human approval
   (production deploys, production data mutations, payments/refunds, webhook/DNS/IAM changes,
   resource deletion, secret rotation, publishing storefront configuration, customer communications).
10. If a secret is found exposed, stop, do not copy it anywhere, and notify a human.

## When `security-reviewer` Must Run
Changes involving: authentication, authorization/RBAC, payments, billing, webhooks, uploads,
secrets, PII, admin permissions, tokens/sessions, infrastructure security.

## Project-Specific Sections

### Data Classification
TODO: POPULATE — Categories of data (public, internal, confidential, PII, payment) and where each lives.

### Authentication Model
TODO: POPULATE

### Authorization / Roles Model
TODO: POPULATE

### Payment / Billing Security
TODO: POPULATE — or `N/A`.

### PII Handling and Retention
TODO: POPULATE

### Compliance Requirements
TODO: POPULATE — e.g. regulatory or contractual obligations, or `N/A`.

### Secrets Inventory (names and locations only)
TODO: POPULATE

### Security Contacts / Incident Process
TODO: POPULATE — Roles and process only.
