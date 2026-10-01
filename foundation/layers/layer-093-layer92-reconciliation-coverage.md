# Foundation Layer 93 — Layer-92 reconciliation coverage audit

**Status:** LIVE — CI green and production verification complete  
**Scope:** audit coverage and structural integrity of Layer-92 reconciliation receipts over successful Layer-91 executions

Layer 92 independently proves whether a Layer-91 execution claim matches durable Layer-87 truth.

Layer 93 asks:

> **Did every successful Layer-91 execution receive exactly one trustworthy Layer-92 receipt?**

## Coverage reader

`foundation.get_case_audit_layer92_reconciliation_coverage_v1(...)`

It reads successful Layer-91 execution events, Layer-92 reconciliation receipts, and the linked Layer-87 snapshot required to validate each Layer-92 receipt. It writes nothing.

## Two measurements

`layer92ReconciliationCoveragePercent` measures receipt coverage.

`healthyLayer92ReconciliationPercent` measures how many Layer-91 claims were actually reconciled.

A valid negative Layer-92 receipt counts as covered but unhealthy. A corrupt Layer-92 receipt is invalid evidence.

## States

Per execution:

- `pending`
- `overdue`
- `invalid-reconciliation`
- `reconciled`
- `missing-layer87-receipt`
- `invalid-layer87-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Overall:

- **idle**
- **normal**
- **pending**
- **gap**
- **invalid**

## Independent integrity

Layer 93 recomputes Layer-92 proof SHA-256 and revalidates the proof envelope, exact Layer-91 binding, Layer-91 action result, no-rerun/no-rewrite flags and the linked durable Layer-87 snapshot.

Layer 93 does not rerun Layer 92's evaluator or writer.

## Authority boundary

Foundation runtime and service role may read the audit. Gateway reads only through existing `foundation_runtime` membership and receives no direct grant. Shine Core, Shine Defence and browser roles are denied.

## Deliberate non-actions

Layer 93 creates no Layer-92 receipt, reruns no Layer 91/87/86/82/81/verification work, repairs no evidence, rewrites no receipt, changes no incident history or release truth, and grants no authority.

## Acceptance coverage

CI proves six materially different cases: reconciled; pending; overdue; valid `missing-layer87-receipt`; valid `execution-receipt-mismatch`; and a structurally invalid Layer-92 receipt.

## Production proof

Layer 93 is deployed in the Shine Foundation Supabase project as migration:

`20261001001719 — foundation_layer_093_layer92_reconciliation_coverage_audit`

Pull request **#121** passed the complete Foundation + Concierge and Shine Defence workflows. CI caught two fixture-only defects before merge: synthetic fingerprints that exceeded the real 64-hex contract and an ambiguous PL/pgSQL fixture timestamp. The Layer-93 coverage reader itself remained unchanged through both corrections.

Live production verification confirms:

- current Layer-93 state: **idle**;
- current problem count: **0**;
- successful Layer-91 execution count: **0**;
- Layer-92 reconciliation receipt count: **0**;
- Layer-92 reconciliation coverage: **100%**;
- healthy Layer-92 reconciliation: **100%**;
- Layer-92 proof integrity is recomputed by the reader;
- linked Layer-87 snapshots are revalidated;
- the coverage read performs no Layer-92 reconciliation and no Layer-91/87/86/82/81/verification rerun;
- Foundation runtime and service role can read Layer 93;
- Gateway reads only through existing `foundation_runtime` inheritance and receives no direct grant;
- Shine Core, Shine Defence and browser roles cannot read Layer 93;
- Supabase performance advisors report no Layer-93-specific finding;
- Supabase security advisors report no Layer-93-specific finding.

Two project-wide INFO security advisor notices currently exist for unrelated `public.grant_protocol` and `public.grant_build_evidence` tables having RLS enabled without policies. Those migrations landed outside Layer 93 and are deliberately not altered by this layer.

## Invariant

> Missing Layer-92 evidence, negative Layer-92 evidence and corrupt Layer-92 evidence are three different truths.
