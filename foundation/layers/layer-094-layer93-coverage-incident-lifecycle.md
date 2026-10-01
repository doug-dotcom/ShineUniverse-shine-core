# Foundation Layer 94 — Layer-93 coverage incident lifecycle

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** turn persistent Layer-93 Layer-92 reconciliation-coverage failures into append-only operational incidents

Layer 93 asks whether every successful Layer-91 execution received one trustworthy Layer-92 reconciliation receipt.

Layer 94 makes a persistent bad answer operationally visible.

## Source of truth

`foundation.get_case_audit_layer92_reconciliation_coverage_v1(...)`

Source states:

- `idle`
- `normal`
- `pending`
- `gap`
- `invalid`

Only **gap** and **invalid** are incident-capable.

`pending` stays non-incident because the Layer-92 receipt is still inside the explicit Layer-93 grace window.

## Incident lifecycle

Ledger:

`foundation.case_audit_layer92_coverage_incident_events`

Lifecycle:

- **detected** — first GAP/INVALID sample starts a watch;
- **opened** — identical bad evidence persists beyond 300 seconds;
- **changed** — materially different Layer-93 evidence arrives while open;
- **recovered** — coverage returns to IDLE, NORMAL or PENDING.

History is append-only.

## Semantic fingerprint

`foundation.case_audit_layer92_coverage_incident_fingerprint_v1(...)`

The fingerprint binds meaningful Layer-93 truth:

- overall state and reason;
- successful Layer-91 execution count;
- required/present Layer-92 receipt counts;
- reconciled/pending/overdue/invalid counts;
- negative Layer-92 outcome counts;
- Layer-92 coverage and healthy-reconciliation percentages;
- execution-level coverage state;
- Layer-92 and Layer-87 receipt identities/states;
- independently recomputed Layer-92 proof integrity.

Evaluation timestamps, execution age and reconciliation timestamps are excluded, so a stable problem cannot append noise simply because time moved.

## Sentinel

`foundation.run_case_audit_layer92_coverage_incident_sentinel_v1(...)`

Only service role may run it.

The sentinel reads fresh Layer-93 coverage, evaluates one incident transition and returns the result.

It does **not** create Layer-92 reconciliation, run Layer 91, run Layer 87, run Layer 86, run Layer 82, run Layer 81, rerun verification, repair evidence, rewrite receipts or mutate authoritative truth.

## Hosted monitoring

Production pg_cron job:

`shine-foundation-case-audit-layer92-coverage-incident-5m`

Cadence:

`1,6,11,16,21,26,31,36,41,46,51,56 * * * *`

Layer 93 owns the 300-second reconciliation grace window. Layer 94 independently requires another 300 seconds of unchanged bad evidence before opening an incident.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Gateway reads the summary only through existing `foundation_runtime` membership and receives no direct grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

The transition helper is owner-private and service role cannot directly insert incident rows.

## Summary

`foundation.get_case_audit_layer92_coverage_incident_summary_v1(...)`

Reports NORMAL / WATCHING / CRITICAL operational state, active/watch counts, current Layer-93 state/reason, Layer-91/92 counts, problem count, Layer-92 coverage and health percentages, current incident evidence and the bounded recommended action.

## Deliberate non-actions

Layer 94 grants no authority to:

- create missing Layer-92 reconciliation;
- rerun Layer 91;
- rerun Layer 87/86/82/81 or verification;
- manufacture or repair evidence;
- rewrite Layer-92/91/87/86/82 receipts;
- suppress incident history;
- mutate release truth;
- grant approval or execution authority.

## Acceptance coverage

CI proves first GAP detection, persistence before opening, quiet unchanged evidence, CHANGED on material evidence change, recovery to PENDING/NORMAL, INVALID watches, clock-noise-resistant fingerprints, service-role-only sentinel execution, append-only history and the complete read/execute role boundary.

## Invariant

> Layer-92 reconciliation coverage can become an incident. An incident never becomes permission to manufacture Layer-92 evidence.
