# Foundation Layer 95 — Layer-94 incident response policy

**Status:** LIVE — CI green and production verification complete  
**Scope:** govern what Foundation may do in response to a persistent Layer-93 coverage incident

Layer 94 makes persistent Layer-93 GAP/INVALID coverage operationally visible.

Layer 95 answers:

> **Which response is permitted without turning that incident into permission to manufacture Layer-92 evidence?**

## Cause classifier

`foundation.get_case_audit_layer92_coverage_incident_cause_v1(...)`

It reads only the current Layer-94 incident summary and Layer-93 coverage.

Cause precedence deliberately puts integrity and deeper-chain trouble ahead of omission:

1. invalid Layer-92 receipt;
2. invalid Layer-87 receipt;
3. Layer-91 execution-receipt mismatch;
4. Layer-90 policy drift;
5. Layer-89 incident-binding drift;
6. Layer-88 coverage-binding drift;
7. missing Layer-87 truth already reported by Layer 92;
8. overdue successful Layer-91 execution with no Layer-92 receipt;
9. generic Layer-92 reconciliation coverage gap.

That ordering prevents Foundation from creating a Layer-92 receipt merely to hide a deeper truth failure.

## Admitted read-only responses

Always available:

- `inspect-layer93-coverage`
- `inspect-layer94-incident-state`

Conditionally admitted:

- `inspect-overdue-layer92-reconciliations`
- `inspect-layer92-reconciliation-receipt`
- `inspect-layer87-reconciliation-chain`
- `inspect-layer91-execution-receipt`
- `inspect-layer90-policy-binding`
- `inspect-layer89-incident-binding`
- `inspect-layer88-coverage-binding`

## Bounded Layer-92 reconciliation

`run-independent-layer92-reconciliation`

is admitted only when Layer 94 is WATCHING/CRITICAL and the classified cause is a pure **layer92-reconciliation-omission**.

Required control:

`layer-92-bounded-reconciler`

Referenced primitive:

`foundation.run_case_audit_layer91_execution_reconciliation_v1(...)`

Layer 95 does not invoke it.

A Layer-92 receipt that already truthfully reports missing/invalid Layer-87 truth, execution mismatch or drift is immutable evidence and remains diagnosis-only.

## Explicitly prohibited

Layer 95 denies Layer-91/87/86/82/81/verification reruns; manufacturing, rewriting, deleting or repairing Layer-92 evidence; manufacturing/rewriting Layer-91 or Layer-87 receipts; upstream evidence repair; suppressing/deleting Layer-94 incident history; and mutating release truth.

## Response plan

`foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(...)`

The plan returns all **28** governed actions and their current decisions.

It grants no execution authority.

## Read boundary

Foundation runtime and service role may read the policy. Gateway reads only through existing `foundation_runtime` membership and receives no direct grant. Shine Core, Shine Defence and browser roles are denied.

## Deliberate non-actions

Layer 95 performs no Layer-92 reconciliation, no upstream rerun, no repair, no receipt rewrite, no history mutation and no release-truth mutation.

## Production proof

Layer 95 is deployed in the Shine Foundation Supabase project as migration:

`20261001003420 — foundation_layer_095_layer94_incident_response_policy`

Pull request **#124** passed the complete Foundation + Concierge and Shine Defence workflows.

Live production verification confirms:

- current Layer-94 operational state: **normal**;
- current Layer-93 coverage state: **idle**;
- current cause class: **none**;
- next evidence action: **none**;
- `inspect-layer93-coverage`: **admit / read-only**;
- `run-independent-layer92-reconciliation`: **not-applicable** on clean production;
- `rerun-layer91`: **deny / prohibited**;
- `mutate-release-truth`: **deny / prohibited**;
- the response plan exposes **28** governed actions;
- Layer-91 execution count remained **0**;
- Layer-92 reconciliation count remained **0**;
- Layer-94 incident-event count remained **0**;
- Foundation runtime and service role can read the policy;
- Gateway reads only through existing `foundation_runtime` inheritance;
- Shine Core, Shine Defence and browser roles cannot read the policy;
- direct service-role Layer-92 reconciliation remains available at Layer 95 and is deliberately left for the next bounded-executor layer to close;
- Supabase security advisors report **0 findings** after deployment;
- Supabase performance advisors report no Layer-95-specific finding.

The policy remains non-executing: even prohibited action metadata identifies what an attempted action would mutate, while `decision=deny`, `requiredControl=prohibited` and `executesAction=false` keep it fail-closed.

## Invariant

> Layer 94 may surface the problem. Layer 95 may choose the next bounded control. Neither layer executes it.
