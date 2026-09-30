# Foundation Layer 87 — Reconciliation execution verification

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** independently prove that a successful Layer-86 execution really corresponds to the durable Layer-82 reconciliation it claims to have produced

Layer 86 says: **I ran the bounded Layer-82 reconciler for this exact Layer-81 event.**

Layer 87 asks: **Does that claim independently agree with the durable reconciliation receipt and the policy evidence that authorised it?**

## Independent evaluator

`foundation.evaluate_case_audit_reconcile_exec_verification_v1(...)`

For each successful Layer-86 event it checks the exact Layer-81 target binding, Layer-86 semantic policy fingerprint, Layer-85 admitted action/no-authority flags, Layer-84 incident binding, durable Layer-82 receipt, Layer-82 proof SHA/envelope/state semantics, and the Layer-86 action result against the durable Layer-82 row.

It calls no upstream writer.

## Verification states

- **verified**
- **missing-reconciliation**
- **policy-mismatch**
- **receipt-mismatch**
- **invalid-reconciliation-proof**

## Immutable verification receipt

Runner: `foundation.run_case_audit_reconcile_exec_verification_v1(...)`

Ledger: `foundation.case_audit_verify_reconcile_exec_verifications`

Replay returns the first immutable receipt.

## Authority boundary

Only service role may run verification. Foundation runtime and service role may read the evaluator/summary. Gateway reads only through existing Foundation-runtime inheritance and receives no direct grant. Core, Defence and browser roles are denied.

## Deliberate non-actions

Layer 87 reruns no Layer 82, Layer 81 or Layer 77 work; rewrites no proof/receipt; repairs no evidence; mutates no incident history or release truth; and grants no authority.

## Acceptance coverage

CI proves a real Layer-86 execution verifies against a real Layer-82 receipt, replay is immutable, denied Layer-86 events are not applicable, missing reconciliation is detected, policy and receipt mismatches are detected, transaction-local Layer-82 proof-hash corruption is detected, upstream counts do not change, and all role/append-only boundaries hold.

## Invariant

> Layer 86 is evidence that an action ran. Layer 87 is evidence that the claimed result still matches the immutable truth underneath it.
