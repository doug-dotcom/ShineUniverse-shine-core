# Foundation Layer 85 — Reconciliation coverage incident response policy

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** govern what Foundation may do in response to a Layer-84 reconciliation-coverage incident

Layer 84 can tell Foundation that reconciliation coverage has become a persistent operational problem.

Layer 85 answers:

> **Which response is permitted without turning an incident into permission to rewrite history?**

## Cause classifier

`foundation.get_case_audit_verify_reconcile_incident_cause_v1(...)`

It reads only:

- the current Layer-84 incident summary;
- the current Layer-83 reconciliation coverage audit.

It classifies the current problem as:

- **none**
- **reconciliation-receipt-integrity**
- **verification-proof-integrity**
- **executor-receipt-mismatch**
- **verification-proof-missing**
- **durable-evidence-drift**
- **verification-coverage-drift**
- **reconciliation-omission**
- **reconciliation-coverage-gap**
- **unknown**

### Cause precedence

Integrity failures dominate omissions.

1. structurally invalid Layer-82 reconciliation receipt;
2. invalid Layer-77 verification proof;
3. Layer-81 executor-receipt mismatch;
4. missing Layer-77 proof already recorded by Layer 82;
5. durable-evidence drift;
6. Layer-78 verification-coverage drift;
7. overdue Layer-81 execution with no Layer-82 receipt;
8. generic reconciliation-coverage gap.

That ordering prevents a missing reconciliation elsewhere from hiding evidence that existing receipts or proofs are already untrustworthy.

## Response evaluator

`foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(...)`

Every action gets:

- action class;
- decision;
- required control;
- reason code;
- current cause.

The evaluator never executes the action.

## Admitted responses

### Read-only diagnosis

Always admissible:

- `inspect-reconciliation-coverage`

Conditionally admissible:

- `inspect-overdue-reconciliations`
- `inspect-reconciliation-receipt`
- `inspect-executor-receipt`
- `inspect-verification-chain`
- `inspect-durable-evidence-chain`
- `inspect-verification-coverage`

Each is admitted only when relevant to the classified cause.

### Bounded reconciliation

`run-independent-reconciliation`

is admitted only when:

- Layer 84 is WATCHING or CRITICAL; and
- the sole leading cause is **reconciliation-omission**.

Required control:

`layer-82-bounded-reconciler`

Referenced primitive:

`foundation.run_case_audit_verify_exec_reconciliation_v1(...)`

Layer 85 does **not** invoke it.

A Layer-82 receipt that already truthfully reports `missing-proof`, `receipt-mismatch`, `invalid-proof`, `evidence-drift` or `coverage-drift` is immutable evidence. Re-running reconciliation would only replay that receipt, so those states remain diagnosis-only.

## Explicitly prohibited responses

Layer 85 always denies:

- rerunning Layer 81;
- rerunning verification;
- manufacturing a reconciliation receipt;
- rewriting or deleting a reconciliation receipt;
- repairing the reconciliation ledger by mutation;
- manufacturing, rewriting or deleting verification proofs;
- repairing durable evidence in place;
- suppressing the Layer-84 incident;
- deleting Layer-84 incident history;
- mutating release truth.

## Response plan

`foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(...)`

The plan returns the complete governed action set and the current decision for each action.

It exposes the Layer-82 reconciler by name only. It grants no execution authority.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Foundation Gateway reads only through existing `foundation_runtime` membership and receives no direct EXECUTE grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

## Deliberate non-actions

Layer 85:

- performs no reconciliation;
- performs no verification;
- reruns no Layer-81 execution;
- writes no reconciliation receipt;
- rewrites no proof or receipt;
- repairs no evidence;
- changes no incident history;
- changes no release truth;
- grants no approval;
- grants no execution authority.

## Invariant

> The incident may identify the next bounded control. It never becomes the control itself.
