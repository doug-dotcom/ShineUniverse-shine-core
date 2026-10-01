# Foundation Layer 98 — Layer-97 reconciliation coverage audit

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** audit coverage and structural integrity of Layer-97 reconciliation receipts over successful Layer-96 executions

Layer 97 independently proves whether a Layer-96 execution claim matches durable Layer-92 truth.

Layer 98 asks:

> **Did every successful Layer-96 execution receive exactly one trustworthy Layer-97 receipt?**

## Coverage reader

`foundation.get_case_audit_layer97_reconciliation_coverage_v1(...)`

It reads successful Layer-96 execution events, Layer-97 reconciliation receipts and the linked Layer-92 snapshot required to validate each Layer-97 receipt. It writes nothing.

## Two measurements

`layer97ReconciliationCoveragePercent` measures receipt coverage.

`healthyLayer97ReconciliationPercent` measures how many Layer-96 execution claims were actually reconciled.

A valid negative Layer-97 receipt counts as covered but unhealthy. A corrupt Layer-97 receipt is invalid evidence.

## States

Per execution:

- `pending`
- `overdue`
- `invalid-reconciliation`
- `reconciled`
- `missing-layer92-receipt`
- `invalid-layer92-receipt`
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

Layer 98 recomputes Layer-97 proof SHA-256 and revalidates the proof envelope, exact Layer-96 binding, Layer-96 action result, no-rerun/no-rewrite flags and the linked durable Layer-92 snapshot.

Layer 98 does not rerun Layer 97's evaluator or writer.

## Authority boundary

Foundation runtime and service role may read the audit. Gateway reads only through existing `foundation_runtime` membership and receives no direct grant. Shine Core, Shine Defence and browser roles are denied.

## Deliberate non-actions

Layer 98 creates no Layer-97 receipt, reruns no Layer 96/92/91/87/86/82/81/verification work, repairs no evidence, rewrites no receipt, changes no incident history or release truth, and grants no authority.

## Acceptance coverage

CI proves six materially different cases: reconciled; pending; overdue; valid `missing-layer92-receipt`; valid `execution-receipt-mismatch`; and a structurally invalid Layer-97 receipt.

## Invariant

> Missing Layer-97 evidence, negative Layer-97 evidence and corrupt Layer-97 evidence are three different truths.
