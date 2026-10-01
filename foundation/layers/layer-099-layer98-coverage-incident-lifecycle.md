# Foundation Layer 99 — Layer-98 coverage incident lifecycle

**Status:** LIVE — CI green and production verification complete  
**Scope:** turn persistent Layer-98 Layer-97 reconciliation-coverage failures into append-only operational incidents

Layer 98 asks whether every successful Layer-96 execution received one trustworthy Layer-97 reconciliation receipt.

Layer 99 makes a persistent bad answer operationally visible.

## Source of truth

`foundation.get_case_audit_layer97_reconciliation_coverage_v1(...)`

Source states:

- `idle`
- `normal`
- `pending`
- `gap`
- `invalid`

Only **gap** and **invalid** are incident-capable.

`pending` stays non-incident because the Layer-97 receipt is still inside the explicit Layer-98 grace window.

## Incident lifecycle

Ledger:

`foundation.case_audit_layer97_coverage_incident_events`

Lifecycle:

- **detected** — first GAP/INVALID sample starts a watch;
- **opened** — identical bad evidence persists beyond 300 seconds;
- **changed** — materially different Layer-98 evidence arrives while open;
- **recovered** — coverage returns to IDLE, NORMAL or PENDING.

History is append-only.

## Semantic fingerprint

`foundation.case_audit_layer97_coverage_incident_fingerprint_v1(...)`

The fingerprint binds meaningful Layer-98 truth:

- overall state and reason;
- successful Layer-96 execution count;
- required/present Layer-97 receipt counts;
- reconciled/pending/overdue/invalid counts;
- negative Layer-97 outcome counts;
- Layer-97 coverage and healthy-reconciliation percentages;
- execution-level coverage state;
- Layer-97 and Layer-92 receipt identities/states;
- independently recomputed Layer-97 proof integrity.

Evaluation timestamps, execution age and reconciliation timestamps are excluded, so stable evidence cannot append noise simply because time moved.

## Sentinel

`foundation.run_case_audit_layer97_coverage_incident_sentinel_v1(...)`

Only service role may run it.

The sentinel reads fresh Layer-98 coverage, evaluates one incident transition and returns the result.

It does **not** create Layer-97 reconciliation, run Layer 96, run Layer 92, run Layer 91, rerun Layer 87/86/82/81/verification, repair evidence, rewrite receipts or mutate authoritative truth.

## Hosted monitoring without another cron job

Production reuses the existing five-minute Foundation coverage-sentinel job:

`shine-foundation-case-audit-layer92-coverage-incident-5m`

Cadence remains:

`1,6,11,16,21,26,31,36,41,46,51,56 * * * *`

The job now invokes the owner-private wrapper:

`foundation.run_case_audit_coverage_incident_sentinels_hosted_v1()`

The wrapper runs the existing Layer-94 sentinel and the new Layer-99 sentinel sequentially. Each call is isolated in its own exception block, so one sentinel failing does not prevent the other from running. No extra pg_cron job is added.

Layer 98 owns the 300-second reconciliation grace window. Layer 99 independently requires another 300 seconds of unchanged bad evidence before opening an incident.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Gateway reads the summary only through existing `foundation_runtime` membership and receives no direct grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

The transition helper and shared hosted wrapper are owner-private. Service role cannot directly insert incident rows.

## Summary

`foundation.get_case_audit_layer97_coverage_incident_summary_v1(...)`

Reports NORMAL / WATCHING / CRITICAL operational state, active/watch counts, current Layer-98 state/reason, Layer-96/97 counts, problem count, Layer-97 coverage and health percentages, current incident evidence and the bounded recommended action.

## Deliberate non-actions

Layer 99 grants no authority to:

- create missing Layer-97 reconciliation;
- rerun Layer 96;
- rerun Layer 92/91/87/86/82/81 or verification;
- manufacture or repair evidence;
- rewrite Layer-97/92/91/87 receipts;
- suppress incident history;
- mutate release truth;
- grant approval or execution authority.

## Acceptance coverage

CI proves first GAP detection, persistence before opening, quiet unchanged evidence, CHANGED on material evidence change, recovery to PENDING/NORMAL, INVALID watches, clock-noise-resistant fingerprints, service-role-only sentinel execution, append-only history and the complete read/execute role boundary.

## Production proof

Layer 99 is deployed in the Shine Foundation Supabase project as:

- `20261001014001 — foundation_layer_099_layer98_coverage_incident_lifecycle`
- `20261001014008 — foundation_layer_099_layer98_coverage_incident_hosted`

Pull request **#131** passed the complete Foundation + Concierge and Shine Defence workflows.

Live production verification confirms:

- operational state: **normal**;
- Layer-98 coverage state: **idle**;
- active incidents: **0**;
- watches: **0**;
- problem count: **0**;
- successful Layer-96 execution count: **0**;
- Layer-97 reconciliation receipt count: **0**;
- Layer-97 reconciliation coverage: **100%**;
- healthy Layer-97 reconciliation: **100%**;
- Layer-99 incident-event count: **0**;
- service role can run the Layer-99 sentinel but cannot call the transition helper or directly insert incident rows;
- Foundation runtime can read the summary;
- Gateway reads the summary only through existing `foundation_runtime` membership;
- Shine Core and Shine Defence cannot run the sentinel;
- the shared hosted wrapper is owner-private;
- the existing pg_cron job remains job **39**, remains active, and retains the same five-minute cadence;
- total production cron-job count remained **28** before and after Layer 99;
- job 39 now invokes `foundation.run_case_audit_coverage_incident_sentinels_hosted_v1()`, which runs Layer 94 and Layer 99 sequentially without adding another concurrent cron job;
- the shared-wrapper production probe returned no Layer-94 error, no Layer-99 error and `additionalCronJobCreated=false`;
- both Layer-94 and Layer-99 probe transitions returned `eventCreated=false` against clean IDLE coverage;
- a real service-role Layer-99 sentinel probe also returned `eventCreated=false`;
- all probes performed no Layer-97 reconciliation, no Layer-96/92/91/87/86/82/81 or verification rerun, and no authoritative-truth or incident-history mutation;
- Supabase security advisors report **0 findings** after deployment;
- Supabase performance advisors report no Layer-99-specific finding.

## Invariant

> Layer-97 reconciliation coverage can become an incident. An incident never becomes permission to manufacture Layer-97 evidence.
