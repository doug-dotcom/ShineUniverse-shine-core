# Foundation Layer 89 — Layer-88 coverage incident lifecycle

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** turn persistent Layer-88 reconciliation-coverage failures into append-only operational incidents

Layer 88 answers:

> **Did every successful Layer-86 execution receive exactly one trustworthy Layer-87 reconciliation receipt?**

Layer 89 makes a persistent bad answer operationally visible.

## Source of truth

Layer 89 reads only:

`foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(...)`

Source states:

- `idle`
- `normal`
- `pending`
- `gap`
- `invalid`

Only **gap** and **invalid** are incident-capable.

`pending` remains deliberately non-incident because the Layer-87 receipt is still inside Layer 88's explicit grace window.

## Incident lifecycle

Ledger:

`foundation.case_audit_reconcile_exec_coverage_incident_events`

Lifecycle:

- **detected** — first GAP/INVALID sample starts a watch;
- **opened** — identical bad evidence persists beyond 300 seconds;
- **changed** — materially different Layer-88 evidence arrives while open;
- **recovered** — coverage returns to IDLE, NORMAL or PENDING.

History is append-only.

## Semantic fingerprint

`foundation.case_audit_reconcile_exec_coverage_incident_fingerprint_v1(...)`

The fingerprint binds meaningful Layer-88 truth:

- overall state and reason;
- successful Layer-86 execution count;
- required/present Layer-87 receipt counts;
- reconciled/pending/overdue/invalid counts;
- negative Layer-87 outcome counts;
- Layer-87 coverage and healthy-reconciliation percentages;
- execution-level coverage state;
- Layer-87 and Layer-82 receipt identities/states;
- independently recomputed Layer-87 proof integrity.

Evaluation timestamps, execution age and reconciliation timestamps are excluded. A stable problem therefore cannot append a new incident event simply because time moved.

## Sentinel

`foundation.run_case_audit_reconcile_exec_coverage_incident_sentinel_v1(...)`

Only service role may run it.

The sentinel reads fresh Layer-88 coverage, evaluates the incident transition and returns the result.

It does **not** create Layer-87 reconciliation, run Layer 86, run Layer 82, run Layer 81, rerun verification, repair evidence or mutate authoritative truth.

## Hosted monitoring

Production pg_cron job:

`shine-foundation-case-audit-reconcile-exec-coverage-incident-5m`

Cadence:

`3,8,13,18,23,28,33,38,43,48,53,58 * * * *`

This uses the currently lighter `:03/:08/.../:58` five-minute lane and keeps the Layer-88 grace window separate from Layer-89 incident persistence.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Gateway reads the summary only through existing `foundation_runtime` membership and receives no direct grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

The transition helper is owner-private and service role cannot insert incident rows directly.

## Summary

`foundation.get_case_audit_reconcile_exec_coverage_incident_summary_v1(...)`

Reports NORMAL / WATCHING / CRITICAL operational state, active/watch counts, current Layer-88 state/reason, Layer-86/87 counts, problem count, Layer-87 coverage and health percentages, current incident evidence and the bounded recommended action.

## Deliberate non-actions

Layer 89 grants no authority to:

- create missing Layer-87 reconciliation;
- rerun Layer 86;
- rerun Layer 82;
- rerun Layer 81 or verification;
- manufacture or repair evidence;
- rewrite Layer-82/86/87 receipts;
- suppress incident history;
- mutate release truth;
- grant approval or execution authority.

## Acceptance coverage

CI proves first GAP detection, persistence before opening, quiet unchanged evidence, CHANGED on material evidence change, recovery to PENDING/NORMAL, INVALID watches, clock-noise-resistant fingerprints, service-role-only sentinel execution, append-only history and the complete read/execute role boundary.

## Invariant

> Layer-87 coverage can become an incident. An incident never becomes permission to manufacture Layer-87 evidence.
