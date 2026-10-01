# Foundation Layer 109 — Layer-108 coverage incident lifecycle

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** turn persistent Layer-108 Layer-107 reconciliation-coverage failures into append-only operational incidents

Layer 108 asks whether every successful Layer-106 execution received one trustworthy Layer-107 reconciliation receipt.

Layer 109 makes a persistent bad answer operationally visible.

## Source of truth

`foundation.get_case_audit_layer107_reconciliation_coverage_v1(...)`

Only **gap** and **invalid** are incident-capable. `pending` remains non-incident because the Layer-107 receipt is still inside the explicit Layer-108 grace window.

## Incident lifecycle

Ledger:

`foundation.case_audit_layer107_coverage_incident_events`

Lifecycle:

- **detected** — first GAP/INVALID sample starts a watch;
- **opened** — identical bad evidence persists beyond 300 seconds;
- **changed** — materially different Layer-108 evidence arrives while open;
- **recovered** — coverage returns to IDLE, NORMAL or PENDING.

History is append-only.

## Semantic fingerprint

`foundation.case_audit_layer107_coverage_incident_fingerprint_v1(...)`

The fingerprint binds meaningful Layer-108 truth:

- overall state and reason;
- successful Layer-106 execution count;
- required/present Layer-107 receipt counts;
- reconciled/pending/overdue/invalid counts;
- negative Layer-107 outcome counts;
- Layer-107 coverage and healthy-reconciliation percentages;
- execution-level coverage state;
- Layer-107 and linked Layer-102 receipt identities/states;
- independently recomputed Layer-107 proof integrity.

Evaluation timestamps, execution age and reconciliation timestamps are excluded, so clock movement alone cannot append CHANGED noise.

## Sentinel

`foundation.run_case_audit_layer107_coverage_incident_sentinel_v1(...)`

Only service role may run it.

The sentinel reads fresh Layer-108 coverage, evaluates one transition and returns the result. It does **not** create Layer-107 reconciliation, rerun Layer 106/102/101/97/96/92/91/87/86/82/81/verification, repair evidence, rewrite receipts or mutate authoritative truth.

## Hosted monitoring

Production reuses the existing five-minute Foundation coverage-sentinel job:

`shine-foundation-case-audit-layer92-coverage-incident-5m`

The owner-private wrapper

`foundation.run_case_audit_coverage_incident_sentinels_hosted_v1()`

now runs Layer 94, Layer 99, Layer 104 and Layer 109 sequentially. Each call is exception-isolated, so one sentinel failing does not prevent the others from running. No additional pg_cron job is created.

## Read boundary

Foundation runtime and service role may read Layer 109. Gateway reads through existing `foundation_runtime` membership only. Shine Core, Shine Defence and browser roles are denied.

The transition helper and shared hosted wrapper are owner-private. Service role cannot directly insert incident rows.

## Acceptance coverage

CI proves first GAP detection, persistence before opening, quiet unchanged evidence, CHANGED on material evidence change, recovery to PENDING/NORMAL, INVALID watches, clock-noise-resistant fingerprints, service-role-only sentinel execution, append-only history and the complete read/execute role boundary.

## Invariant

> Layer-107 reconciliation coverage can become an incident. An incident never becomes permission to manufacture Layer-107 evidence.
