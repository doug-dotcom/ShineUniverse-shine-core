# Foundation Layer 97 — Layer-96 execution reconciliation

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** independently reconcile each successful Layer-96 bounded Layer-92 reconciliation execution against durable Layer-92 truth

Layer 96 closes direct service-role access to Layer 92.

Layer 97 closes the next trust seam:

> **Layer 96 saying it invoked Layer 92 is not evidence that Layer 92 actually produced the claimed receipt.**

## Independent evaluator

`foundation.evaluate_case_audit_layer96_execution_outcome_v1(...)`

For one successful Layer-96 event, the evaluator independently re-checks:

- the exact Layer-91 target;
- the Layer-95 decision snapshot and Layer-96 policy fingerprint;
- the bound Layer-94 incident event;
- the before/after Layer-93 coverage snapshots;
- the durable Layer-92 receipt;
- the Layer-92 receipt SHA-256 and proof structure;
- the Layer-96 action result against the durable Layer-92 receipt.

## Truth states

Layer 97 records one of:

- `reconciled`
- `missing-layer92-receipt`
- `invalid-layer92-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Integrity failures dominate downstream claim mismatches. A missing Layer-92 receipt is recorded as missing; it is never manufactured.

## Reconciler

`foundation.run_case_audit_layer96_execution_reconciliation_v1(...)`

The reconciler accepts one Layer-96 event ID, evaluates it, and appends one immutable Layer-97 receipt.

It does **not** invoke Layer 96, Layer 92, Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification.

Replay returns the existing Layer-97 receipt.

## Ledger

`foundation.case_audit_layer96_exec_reconciliations`

The ledger is append-only, RLS protected and explicitly denies browser-client access. Service role can invoke the Layer-97 reconciler but cannot directly insert rows.

## Read boundary

Foundation runtime and service role may read Layer-97 evaluation and summary functions. Gateway reads through existing `foundation_runtime` membership only. Shine Core, Shine Defence, anon and authenticated cannot reconcile.

The direct Layer-92 service-role bypass closed by Layer 96 must remain closed.

## Acceptance coverage

CI proves:

- faithful Layer-96 claim + valid Layer-92 receipt → `reconciled`;
- missing Layer-92 receipt → `missing-layer92-receipt`;
- valid Layer-92 receipt with mismatched Layer-96 result → `execution-receipt-mismatch`;
- malformed Layer-92 proof → `invalid-layer92-receipt`;
- altered Layer-96 policy fingerprint → `policy-drift`;
- all five states can be durably recorded without changing Layer-96, Layer-92 or Layer-91 counts;
- replay returns the existing receipt;
- direct service-role Layer-92 execution remains revoked;
- direct service-role ledger insert is denied;
- role and append-only boundaries hold.

## Invariant

> Layer 97 may attest what Layer 96 actually did. It may never make Layer 96's claim true.
