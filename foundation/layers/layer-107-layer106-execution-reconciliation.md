# Foundation Layer 107 — Layer-106 execution reconciliation

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** independently reconcile each successful Layer-106 bounded Layer-102 reconciliation execution against durable Layer-102 truth

Layer 106 closes direct service-role access to Layer 102.

Layer 107 closes the next trust seam:

> **Layer 106 saying it invoked Layer 102 is not evidence that Layer 102 actually produced the claimed receipt.**

## Independent evaluator

`foundation.evaluate_case_audit_layer106_execution_outcome_v1(...)`

For one successful Layer-106 event, the evaluator independently re-checks:

- the exact Layer-101 target;
- the Layer-105 decision snapshot and Layer-106 policy fingerprint;
- the bound Layer-104 incident event;
- the before/after Layer-103 coverage snapshots;
- the durable Layer-102 receipt;
- the Layer-102 receipt SHA-256 and proof structure;
- the Layer-106 action result against the durable Layer-102 receipt.

## Truth states

Layer 107 records one of:

- `reconciled`
- `missing-layer102-receipt`
- `invalid-layer102-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Integrity failures dominate downstream claim mismatches. Missing Layer-102 truth is recorded as missing; it is never manufactured.

## Reconciler

`foundation.run_case_audit_layer106_execution_reconciliation_v1(...)`

The reconciler accepts one Layer-106 event ID, evaluates it, and appends one immutable Layer-107 receipt.

It does **not** invoke Layer 106, Layer 102, Layer 101, Layer 97, Layer 96, Layer 92, Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification.

Replay returns the existing Layer-107 receipt.

## Ledger

`foundation.case_audit_layer106_exec_reconciliations`

The ledger is append-only, RLS protected and explicitly denies browser-client access. Service role can invoke the Layer-107 reconciler but cannot directly insert rows.

## Read boundary

Foundation runtime and service role may read Layer-107 evaluation and summary functions. Gateway reads through existing `foundation_runtime` membership only. Shine Core, Shine Defence and browser roles cannot reconcile.

The direct Layer-102 service-role bypass closed by Layer 106 must remain closed.

## Acceptance coverage

CI proves:

- faithful Layer-106 claim + valid Layer-102 receipt → `reconciled`;
- missing Layer-102 receipt → `missing-layer102-receipt`;
- valid Layer-102 receipt with mismatched Layer-106 result → `execution-receipt-mismatch`;
- malformed Layer-102 proof → `invalid-layer102-receipt`;
- altered Layer-106 policy fingerprint → `policy-drift`;
- all five states can be durably recorded without changing Layer-106, Layer-102 or Layer-101 counts;
- replay returns the existing receipt;
- direct service-role Layer-102 execution remains revoked;
- direct service-role ledger insert is denied;
- role and append-only boundaries hold.

## Invariant

> Layer 107 may attest what Layer 106 actually did. It may never make Layer 106's claim true.
