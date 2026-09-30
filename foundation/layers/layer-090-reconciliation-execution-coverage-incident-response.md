# Foundation Layer 90 — Layer-89 incident response policy

**Status:** LIVE — CI green and production verification complete  
**Scope:** govern what Foundation may do in response to a persistent Layer-88 coverage incident

Layer 89 makes persistent Layer-88 GAP/INVALID coverage operationally visible.

Layer 90 answers:

> **Which response is permitted without turning that incident into permission to rewrite evidence?**

## Cause classifier

`foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(...)`

It reads only the current Layer-89 incident summary and current Layer-88 coverage.

Cause precedence deliberately puts deeper integrity trouble ahead of omission:

1. invalid Layer-87 receipt;
2. invalid Layer-82 receipt;
3. Layer-86 execution-receipt mismatch;
4. Layer-85 policy drift;
5. Layer-84 incident-binding drift;
6. Layer-83 coverage-binding drift;
7. missing Layer-82 receipt already truthfully reported by Layer 87;
8. overdue successful Layer-86 execution with no Layer-87 receipt;
9. generic Layer-87 coverage gap.

That ordering prevents Foundation from “fixing” a missing Layer-87 receipt while ignoring evidence that the underlying chain is already untrustworthy.

## Admitted read-only responses

Always available:

- `inspect-layer88-coverage`
- `inspect-layer89-incident-state`

Conditionally admitted:

- `inspect-overdue-layer87-reconciliations`
- `inspect-layer87-reconciliation-receipt`
- `inspect-layer82-reconciliation-chain`
- `inspect-layer86-execution-receipt`
- `inspect-layer85-policy-binding`
- `inspect-layer84-incident-binding`
- `inspect-layer83-coverage-binding`

## Bounded Layer-87 reconciliation

`run-independent-layer87-reconciliation`

is admitted only when Layer 89 is WATCHING/CRITICAL and the classified cause is a pure **layer87-reconciliation-omission**.

Required control:

`layer-87-bounded-reconciler`

Referenced primitive:

`foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(...)`

Layer 90 does not invoke it.

A Layer-87 receipt that already truthfully records missing Layer-82 truth, invalid evidence, receipt mismatch or drift is immutable evidence and remains diagnosis-only.

## Explicitly prohibited

Layer 90 denies Layer-86/82/81/verification reruns; manufacturing, rewriting, deleting or repairing Layer-87 evidence; manufacturing/rewriting Layer-86 or Layer-82 receipts; upstream evidence repair; suppressing/deleting Layer-89 incident history; and mutating release truth.

## Response plan

`foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(...)`

The plan returns all **26** governed actions and their current decisions.

It grants no execution authority.

## Read boundary

Foundation runtime and service role may read the policy. Gateway reads only through existing `foundation_runtime` membership and receives no direct grant. Shine Core, Shine Defence and browser roles are denied.

## Deliberate non-actions

Layer 90 performs no Layer-87 reconciliation, no upstream rerun, no repair, no receipt/proof rewrite, no history mutation and no release-truth mutation.

## Production proof

Layer 90 is deployed in the Shine Foundation Supabase project as migration:

`20260930225148 — foundation_layer_090_layer89_incident_response_policy`

Live production verification confirms:

- current Layer-89 operational state: **normal**;
- current Layer-88 coverage state: **idle**;
- current cause class: **none**;
- next evidence action: **none**;
- `inspect-layer88-coverage`: **admit / read-only**;
- `run-independent-layer87-reconciliation`: **not-applicable** on healthy production;
- `rerun-layer86`: **deny / prohibited**;
- `mutate-release-truth`: **deny / prohibited**;
- policy evaluation changed Layer-82 reconciliation count: **0 → 0**;
- policy evaluation changed Layer-86 execution count: **0 → 0**;
- policy evaluation changed Layer-87 reconciliation count: **0 → 0**;
- policy evaluation changed Layer-89 incident-event count: **0 → 0**;
- Foundation runtime and service role can read the policy;
- Gateway reads only through existing `foundation_runtime` inheritance and receives no direct grant;
- Shine Core, Shine Defence and browser roles cannot read the policy;
- direct service-role Layer-87 execution remains available at Layer 90 and is intentionally left for the next bounded-executor layer to close;
- Supabase advisors report no Layer-90-specific security or performance finding.

## Invariant

> Layer 89 may select the next bounded control. Layer 90 may admit it. Neither layer executes it.
