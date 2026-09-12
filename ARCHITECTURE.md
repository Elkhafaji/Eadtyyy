# Eyadaty implementation plan

## Current baseline

The existing application is a single HTML SPA. It renders the current patient, doctor, receptionist, manager and admin screens, and currently synchronizes one JSON state document through `/api/db`. The local runtime uses SQLite; Vercel uses the PostgreSQL function in `api/db.js`.

This is preserved during migration. New modules must not be represented by client-only arrays or decorative actions.

## Target architecture

```text
Browser SPA
  -> authenticated API functions
  -> PostgreSQL transaction + authorization service
  -> private object storage for medical files
  -> notification/outbound provider adapters
```

The product has one organization and many branches. It is not multi-tenant SaaS.

## Migration order

1. Core organization, branches, users, roles, permissions and branch access.
2. Server-side session/authentication and authorization middleware.
3. Admin Patients, staff administration and branch management.
4. Front desk, cashier, call center and reminder delivery records.
5. Laboratory and radiology workflows.
6. Pharmacy, inventory, warehouses, batches and atomic dispensing.
7. Procedures and ambulance operations.
8. Reports, audit expansion, private files, realtime and responsive QA.

## Permission rules

Every API operation must derive the current user from the server-side session. Role, user id and branch id from the browser are treated as untrusted input. A query must include the user's organization and authorized branch scope before returning records.

## Data migration

Existing records receive the generated Default Branch. Existing patient, appointment, queue, visit, payment, invoice, file, message and audit records are retained. New tables are additive and nullable branch links are backfilled before constraints are tightened.

## Current limitations that remain until the API migration phases are completed

- The legacy `/api/db` compatibility endpoint still transports the complete state document.
- The legacy browser session is not a production-grade server session.
- The legacy data URL file storage must be replaced by private object storage before real medical files are used.

These limitations are intentionally documented instead of hidden.
