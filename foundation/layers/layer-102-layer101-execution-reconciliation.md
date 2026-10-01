# Foundation Layer 102 — Layer-101 execution reconciliation

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** independently reconcile each successful Layer-101 bounded Layer-97 reconciliation execution against durable Layer-97 truth

Layer 101 closes direct service-role access to Layer 97.

Layer 102 closes the next trust seam:

> **Layer 101 saying it invoked Layer 97 is not evidence that Layer 97 actually produced the claimed receipt.**

## Independent evaluator

`foundation.evaluate_case_audit_layer101_execution_outcome_v1(...)`

For one successful Layer-101 event, the evaluator independently re-checks:

- the exact Layer-96 target;
- the Layer-100 decision snapshot and Layer-101 policy fingerprint;
- the bound Layer-99 incident event;
- the before/after Layer-98 coverage snapshots;
- the durable Layer-97 receipt;
- the Layer-97 receipt SHA-256 and proof structure;
- the Layer-101 action result against the durable Layer-97 receipt.

## Truth states

Layer 102 records one of:

- `reconciled`
- `missing-layer97-receipt`
- `invalid-layer97-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Integrity failures dominate downstream claim mismatches. Missing Layer-97 truth is recorded as missing; it is never manufactured.

## Reconciler

`foundation.run_case_audit_layer101_execution_reconciliation_v1(...)`

The reconciler accepts one Layer-101 event ID, evaluates it, and appends one immutable Layer-102 receipt.

It does **not** invoke Layer 101, Layer 97, Layer 96, Layer 92, Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification.

Replay returns the existing Layer-102 receipt.

## Ledger

`foundation.case_audit_layer101_exec_reconciliations`

The ledger is append-only, RLS protected and explicitly denies browser-client access. Service role can invoke the Layer-102 reconciler but cannot directly insert rows.

## Read boundary

Foundation runtime and service role may read Layer-102 evaluation and summary functions. Gateway reads through existing `foundation_runtime` membership only. Shine Core, Shine Defence and browser roles cannot reconcile.

The direct Layer-97 service-role bypass closed by Layer 101 must remain closed.

## Acceptance coverage

CI proves:

- faithful Layer-101 claim + valid Layer-97 receipt → `reconciled`;
- missing Layer-97 receipt → `missing-layer97-receipt`;
- valid Layer-97 receipt with mismatched Layer-101 result → `execution-receipt-mismatch`;
- malformed Layer-97 proof → `invalid-layer97-receipt`;
- altered Layer-101 policy fingerprint → `policy-drift`;
- all five states can be durably recorded without changing Layer-101, Layer-97 or Layer-96 counts;
- replay returns the existing receipt;
- direct service-role Layer-97 execution remains revoked;
- direct service-role ledger insert is denied;
- role and append-only boundaries hold.

## Invariant

> Layer 102 may attest what Layer 101 actually did. It may never make Layer 101's claim true.
