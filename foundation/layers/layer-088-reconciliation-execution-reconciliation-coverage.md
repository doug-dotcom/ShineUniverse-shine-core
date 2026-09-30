# Foundation Layer 88 — Layer-87 reconciliation coverage audit

**Status:** LIVE — CI green and production verification complete  
**Scope:** audit coverage and structural integrity of Layer-87 reconciliation receipts over successful Layer-86 executions

Layer 87 can independently prove whether a Layer-86 execution claim matches its durable Layer-82 truth.

Layer 88 asks:

> **Did every successful Layer-86 execution receive exactly one trustworthy Layer-87 receipt?**

## Coverage reader

`foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(...)`

It reads successful Layer-86 execution events, Layer-87 reconciliation receipts, and the linked Layer-82 identity/snapshot required to validate each Layer-87 receipt. It writes nothing.

## Two different measurements

`layer87ReconciliationCoveragePercent` asks what percentage of successful Layer-86 executions have a Layer-87 receipt.

`healthyLayer87ReconciliationPercent` asks what percentage were actually reconciled by Layer 87.

A structurally valid negative Layer-87 receipt still counts as covered. It is trustworthy bad news: **covered, but unhealthy**.

A corrupt Layer-87 receipt is different: it is **invalid evidence**.

## Per-execution states

- `pending`
- `overdue`
- `invalid-reconciliation`
- `reconciled`
- `missing-layer82-receipt`
- `invalid-layer82-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

## Independent receipt integrity

Layer 88 recomputes Layer-87 proof SHA-256 and revalidates proof identity, exact Layer-86 binding, Layer-86 action result, policy/incident/coverage flags, linked Layer-82 snapshot, state semantics and every no-rerun/no-rewrite/no-authority flag.

Layer 88 does not rerun Layer 87's evaluator.

## Overall states

- **idle** — no successful Layer-86 executions;
- **normal** — all required Layer-87 receipts exist, are valid and reconcile;
- **pending** — only within-grace receipts remain;
- **gap** — an overdue execution or a valid negative Layer-87 result exists;
- **invalid** — at least one Layer-87 receipt itself fails structural/proof integrity.

## Authority boundary

Foundation runtime and service role may read the audit. Gateway reads only through its existing `foundation_runtime` membership and receives no direct grant. Shine Core, Shine Defence and browser roles are denied.

## Deliberate non-actions

Layer 88 creates no Layer-87 receipt, reruns no Layer 86/82/81/verification work, repairs no evidence, rewrites no receipt/proof, changes no incident history or release truth, and grants no authority.

## Acceptance coverage

CI proves six materially different cases: reconciled; pending; overdue; valid `missing-layer82-receipt`; valid `execution-receipt-mismatch`; and a structurally invalid Layer-87 receipt.

The fixture explicitly proves that coverage, truthfulness and health are different concepts.

## Production proof

Layer 88 is deployed in the Shine Foundation Supabase project as migration:

`20260930222126 — foundation_layer_088_layer87_reconciliation_coverage_audit`

Live production verification confirms:

- current Layer-88 state: **idle**;
- current problem count: **0**;
- successful Layer-86 execution count: **0**;
- Layer-87 receipt count: **0**;
- Layer-87 reconciliation coverage: **100%**;
- healthy Layer-87 reconciliation: **100%**;
- Layer-87 proof integrity is recomputed by the reader;
- linked Layer-82 snapshots are revalidated;
- the coverage read changed Layer-82 reconciliation count: **0 → 0**;
- the coverage read changed Layer-86 execution count: **0 → 0**;
- the coverage read changed Layer-87 reconciliation count: **0 → 0**;
- Foundation runtime and service role can read Layer 88;
- Gateway reads only through existing `foundation_runtime` inheritance and receives no direct grant;
- Shine Core, Shine Defence and browser roles cannot read Layer 88;
- Supabase security advisors report no Layer-88-specific finding;
- Supabase performance advisors report no Layer-88-specific finding.

CI also caught a malformed synthetic policy fingerprint before production. The fixture was corrected to preserve the real 64-hex fingerprint invariant; no Layer-88 production object existed at the time of that failure.

## Invariant

> Missing evidence, negative evidence and corrupt evidence are not the same failure.
