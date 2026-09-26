# Foundation Layer 4 — Durable grant store, audit ledger and revocation propagation

**Status:** Complete  
**Scope:** Core + ID + Vault persistence

Layer 4 gives Foundation durable state without exposing that state directly to Shine app clients.

## Persistence model

`postgres/persistence-v1.sql` creates a private `foundation` schema containing:

- app registry;
- Shine identities and provider bindings;
- Vault resource catalogue;
- immutable grant issuance records;
- immutable grant revocations;
- monotonic revocation outbox;
- immutable allow/deny audit events.

## Grant lifecycle

A grant issuance record is append-only. Its effective state is derived rather than rewritten:

- **active** — no revocation, inside the allowed time window;
- **not-yet-active** — before `not_before`;
- **expired** — at or after `expires_at`;
- **revoked** — a revocation event exists.

This makes revocation monotonic: there is no database operation that turns a revoked grant back into an active grant.

## Revocation propagation

Every inserted revocation synchronously writes one row to `revocation_outbox`.

The outbox has a monotonically increasing `sequence_no`, so Foundation consumers can invalidate grant caches and advance a cursor without relying on event arrival order.

A unique constraint on `grant_id` permits only one terminal revocation event per grant.

## Audit ledger

`access_audit_events` stores both allow and deny decisions. Grant, revocation, outbox and audit records are append-only.

## Security boundary

- `foundation` is a private schema.
- `anon` and `authenticated` receive no schema/table/sequence access.
- RLS is enabled on every Foundation table as defence-in-depth.
- trusted server-side `service_role` receives only the persistence privileges it needs.
- no `SECURITY DEFINER` function is used.
- the effective-grants view uses `security_invoker = true`.

## Verification

GitHub CI starts PostgreSQL 17 and executes:

1. a Supabase-role compatibility bootstrap;
2. the complete persistence schema;
3. behavioural acceptance tests covering private access, RLS, active grant state, allow/deny audit records, revocation, exactly-once outbox emission, duplicate revocation rejection and append-only history.
