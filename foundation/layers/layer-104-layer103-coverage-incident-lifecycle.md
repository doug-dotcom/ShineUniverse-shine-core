# Foundation Layer 104 — Layer-103 coverage incident lifecycle

**Status:** LIVE — CI green and production verification complete  
**Scope:** turn persistent Layer-103 Layer-102 reconciliation-coverage failures into append-only operational incidents

Layer 103 asks whether every successful Layer-101 execution received one trustworthy Layer-102 reconciliation receipt.

Layer 104 makes a persistent bad answer operationally visible.

## Source of truth

`foundation.get_case_audit_layer102_reconciliation_coverage_v1(...)`

Only **gap** and **invalid** are incident-capable. `pending` remains non-incident because the Layer-102 receipt is still inside the explicit Layer-103 grace window.

## Incident lifecycle

Ledger:

`foundation.case_audit_layer102_coverage_incident_events`

Lifecycle:

- **detected** — first GAP/INVALID sample starts a watch;
- **opened** — identical bad evidence persists beyond 300 seconds;
- **changed** — materially different Layer-103 evidence arrives while open;
- **recovered** — coverage returns to IDLE, NORMAL or PENDING.

History is append-only.

## Semantic fingerprint

`foundation.case_audit_layer102_coverage_incident_fingerprint_v1(...)`

The fingerprint binds meaningful Layer-103 truth:

- overall state and reason;
- successful Layer-101 execution count;
- required/present Layer-102 receipt counts;
- reconciled/pending/overdue/invalid counts;
- negative Layer-102 outcome counts;
- Layer-102 coverage and healthy-reconciliation percentages;
- execution-level coverage state;
- Layer-102 and linked Layer-97 receipt identities/states;
- independently recomputed Layer-102 proof integrity.

Evaluation timestamps, execution age and reconciliation timestamps are excluded, so clock movement alone cannot append CHANGED noise.

## Sentinel

`foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(...)`

Only service role may run it.

The sentinel reads fresh Layer-103 coverage, evaluates one transition and returns the result. It does **not** create Layer-102 reconciliation, rerun Layer 101/97/96/92/91/87/86/82/81/verification, repair evidence, rewrite receipts or mutate authoritative truth.

## Hosted monitoring

Production reuses the existing five-minute Foundation coverage-sentinel job:

`shine-foundation-case-audit-layer92-coverage-incident-5m`

The owner-private wrapper

`foundation.run_case_audit_coverage_incident_sentinels_hosted_v1()`

now runs Layer 94, Layer 99 and Layer 104 sequentially. Each call is exception-isolated, so one sentinel failing does not prevent the other two from running. No additional pg_cron job is created.

## Read boundary

Foundation runtime and service role may read Layer 104. Gateway reads through existing `foundation_runtime` membership only. Shine Core, Shine Defence and browser roles are denied.

The transition helper and shared hosted wrapper are owner-private. Service role cannot directly insert incident rows.

## Acceptance coverage

CI proves first GAP detection, persistence before opening, quiet unchanged evidence, CHANGED on material evidence change, recovery to PENDING/NORMAL, INVALID watches, clock-noise-resistant fingerprints, service-role-only sentinel execution, append-only history and the complete read/execute role boundary.

## Production proof

Layer 104 is deployed in the Shine Foundation Supabase project as:

- `20261001033957 — foundation_layer_104_layer103_coverage_incident_lifecycle`
- `20261001034003 — foundation_layer_104_layer103_coverage_incident_hosted`

Pull request **#144** passed the complete Foundation + Concierge and Shine Defence workflows.

Live production verification confirms:

- operational state: **normal**;
- Layer-103 coverage state: **idle**;
- active incidents: **0**;
- watches: **0**;
- problem count: **0**;
- successful Layer-101 execution count: **0**;
- Layer-102 reconciliation receipt count: **0**;
- Layer-102 reconciliation coverage: **100%**;
- healthy Layer-102 reconciliation: **100%**;
- Layer-104 incident-event count: **0**;
- service role can run the Layer-104 sentinel but cannot call the transition helper or directly insert incident rows;
- Foundation runtime can read the summary;
- Gateway reads the summary only through existing `foundation_runtime` membership;
- Shine Core and Shine Defence cannot run the sentinel;
- the shared hosted wrapper is owner-private;
- the existing pg_cron job remains job **39**, remains active, and retains the same five-minute cadence;
- total production cron-job count remained **28** before and after Layer 104;
- job 39 now invokes the shared wrapper that runs Layer 94, Layer 99 and Layer 104 sequentially;
- the shared-wrapper production probe returned no Layer-94, Layer-99 or Layer-104 error and `additionalCronJobCreated=false`;
- all three shared sentinel transitions returned `eventCreated=false` against clean IDLE coverage;
- a real service-role Layer-104 sentinel probe also returned `eventCreated=false`;
- all probes performed no Layer-102 reconciliation, no Layer-101/97/96/92/91/87/86/82/81 or verification rerun, and no authoritative-truth or incident-history mutation;
- Supabase security advisors report **0 findings** after deployment;
- Supabase performance advisors report no Layer-104-specific finding.

## Invariant

> Layer-102 reconciliation coverage can become an incident. An incident never becomes permission to manufacture Layer-102 evidence.
