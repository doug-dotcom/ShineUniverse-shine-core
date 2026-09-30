# Foundation Layer 84 — Reconciliation coverage incident lifecycle

**Status:** LIVE — CI green and production verification complete  
**Scope:** turn persistent Layer-83 reconciliation-coverage failures into append-only operational incidents

Layer 83 answers:

> **Have all successful Layer-81 executions actually received a valid Layer-82 reconciliation receipt?**

Layer 84 makes a persistent bad answer operationally visible.

## Source of truth

Layer 84 reads only:

`foundation.get_case_audit_verify_reconcile_coverage_v1(...)`

The source states are:

- `idle`
- `normal`
- `pending`
- `gap`
- `invalid`

Only **gap** and **invalid** are incident-capable.

`pending` remains deliberately non-incident because Layer 83 has already established that reconciliation is still inside its explicit grace window.

## Incident lifecycle

Ledger:

`foundation.case_audit_verify_reconcile_incident_events`

Lifecycle:

- **detected** — first GAP/INVALID sample starts a watch;
- **opened** — identical bad evidence persists beyond 300 seconds;
- **changed** — an open incident receives materially different reconciliation evidence;
- **recovered** — coverage returns to IDLE, NORMAL or PENDING.

The ledger is append-only.

## Semantic fingerprint

`foundation.case_audit_verify_reconcile_incident_fingerprint_v1(...)`

The fingerprint binds only meaningful Layer-83 truth:

- overall state and reason;
- successful-executor and reconciliation counts;
- reconciliation coverage and healthy-reconciliation percentages;
- overdue/invalid/negative reconciliation counts;
- execution-level coverage state;
- reconciliation identity/state;
- verification identity/state;
- reconciliation-proof integrity.

Evaluation timestamps, execution age and other clock-only movement are excluded. A stable problem therefore cannot create a new event every time the sentinel runs.

## Sentinel

`foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(...)`

Only `service_role` may run it.

The sentinel:

1. reads fresh Layer-83 coverage;
2. evaluates the incident transition;
3. returns coverage plus the transition result.

It does **not** run Layer 82, Layer 81 or Layer 77, create evidence, rewrite a receipt, or repair any authoritative truth.

## Hosted monitoring

Production pg_cron job:

`shine-foundation-case-audit-verify-reconcile-incident-5m`

Cadence:

`4,9,14,19,24,29,34,39,44,49,54,59 * * * *`

That creates two distinct time boundaries:

- Layer-83 reconciliation grace: 300 seconds;
- Layer-84 incident persistence: another 300 seconds before opening.

A temporarily late reconciliation therefore becomes a watch first, not an immediate production incident.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Foundation Gateway may read the summary only through its existing `foundation_runtime` membership. Layer 84 grants Gateway no direct EXECUTE privilege.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

The transition helper is owner-private, and service role cannot insert incident rows directly.

## Summary

`foundation.get_case_audit_verify_reconcile_incident_summary_v1(...)`

Reports:

- NORMAL / WATCHING / CRITICAL operational state;
- active incident and watch counts;
- current Layer-83 coverage state/reason;
- successful-executor, reconciliation-receipt and problem counts;
- reconciliation coverage and healthy-reconciliation percentages;
- current incident evidence;
- bounded recommended action.

## Deliberate non-actions

Layer 84 grants no authority to:

- run missing Layer-82 reconciliation;
- rerun Layer 81;
- rerun Layer 77;
- manufacture or repair durable evidence;
- rewrite Layer-77 proofs;
- rewrite Layer-81 receipts;
- rewrite Layer-82 reconciliation receipts;
- suppress incident history;
- mutate release truth;
- grant approval or execution authority.

## Acceptance coverage

CI proves:

- first GAP creates a watch;
- persistence opens the incident;
- unchanged open evidence does not append noise;
- material reconciliation-evidence change appends `changed`;
- PENDING recovers an incident/watch;
- INVALID creates a watch;
- NORMAL recovers;
- fingerprint ignores evaluation-time/execution-age noise;
- sentinel remains service-role-only;
- service role cannot directly insert incident rows;
- transition helper remains owner-private;
- Gateway reads summary only through Foundation runtime inheritance;
- Core, Defence and browser roles remain denied;
- incident history is append-only.

## Production proof

Layer 84 is deployed in the Shine Foundation Supabase project as:

- `20260930135059 — foundation_layer_084_reconciliation_coverage_incident_lifecycle`
- `20260930135106 — foundation_layer_084_reconciliation_coverage_incident_hosted`

Live production verification confirms:

- operational state: **normal**;
- Layer-83 reconciliation coverage state: **idle**;
- active incidents: **0**;
- watches: **0**;
- reconciliation problems: **0**;
- reconciliation coverage: **100%**;
- healthy reconciliation: **100%**;
- a real `service_role` sentinel execution returned no event and performed no reconciliation, repair, Layer-81 rerun or authoritative-truth mutation;
- `service_role` can run the sentinel but cannot run the transition helper or directly INSERT incident events;
- Foundation runtime can read the summary;
- Gateway can read the summary only through existing `foundation_runtime` membership and has no direct summary grant;
- Shine Core, Shine Defence and browser roles cannot read the summary;
- hosted pg_cron job `shine-foundation-case-audit-verify-reconcile-incident-5m` is active as job **37** on the documented cadence;
- Supabase advisors report no Layer-84-specific security or performance finding.

## Invariant

> A reconciliation gap may become an incident. An incident never becomes permission to manufacture reconciliation.
