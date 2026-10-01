# Foundation Layer 106 — Bounded Layer-102 reconciliation executor

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** execute the single bounded action Layer 105 may admit: independent Layer-102 reconciliation of one overdue successful Layer-101 execution

Layer 105 can identify a pure omission where a successful Layer-101 execution is old enough to require Layer-102 reconciliation, no Layer-102 receipt exists, and the Layer-104 incident lifecycle is active.

Layer 106 is the narrow execution boundary for that case.

> **One Layer-101 event. One current Layer-105 decision. One existing Layer-102 reconciler. Nothing else.**

## Executor

`foundation.execute_case_audit_overdue_layer102_reconciliation_v1(...)`

Before invoking anything, Layer 106 requires the exact Layer-101 event to exist, be successful, be older than reconciliation grace, have no Layer-102 receipt, sit under an active Layer-104 watch/incident, and still receive an admitted `run-independent-layer102-reconciliation` decision from Layer 105 requiring `layer-102-bounded-reconciler`.

Layer 106 re-checks every no-authority, no-rerun and no-rewrite flag immediately before execution.

## Only executable target

The only function Layer 106 may invoke is:

`foundation.run_case_audit_layer101_execution_reconciliation_v1(...)`

There is no dynamic function selection and no arbitrary-SQL path.

## Closing the bypass

Layer 106 revokes direct `service_role` EXECUTE on the Layer-102 writer.

The route becomes:

**Layer 105 policy → Layer 106 exact-target gate → Layer 102 reconciler**

Layer 106 is a private-schema `SECURITY DEFINER` function with an empty search path. Service role cannot call Layer 102 directly.

## Execution evidence

Ledger:

`foundation.case_audit_layer102_reconcile_exec_events`

Events are `executed`, `denied` or `failed`. The ledger is append-only and permits only one successful Layer-106 execution per target Layer-101 event.

Semantic replay returns the original Layer-106 receipt instead of invoking Layer 102 again.

## Allowed effect

A successful call can create exactly one immutable Layer-102 reconciliation receipt. Layer 102 remains responsible for the truth of that receipt and may conclude:

- `reconciled`
- `missing-layer97-receipt`
- `invalid-layer97-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Layer 106 never reinterprets the result.

## Forbidden effects

Layer 106 cannot rerun Layer 101, Layer 97, Layer 96, Layer 92, Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification; manufacture or repair evidence; rewrite Layer-102/101/97 receipts; alter Layer-104 incident history; mutate release truth; or create arbitrary execution authority.

## Acceptance coverage

CI proves:

- one overdue successful Layer-101 event with no Layer-102 receipt can pass through the Layer-106 exact-target gate;
- exactly one Layer-102 receipt is created through the real Layer-102 reconciler;
- replay returns the first Layer-106 receipt;
- within-grace Layer-101 targets are denied;
- non-successful Layer-101 targets are denied;
- missing targets are not applicable;
- Layer-101 and deeper upstream counts do not change;
- direct service-role Layer-102 bypass is revoked;
- service role cannot directly insert Layer-106 ledger rows;
- append-only and role boundaries hold.

## Invariant

> Layer 106 may complete missing Layer-102 reconciliation. It may never manufacture or repair the truth being reconciled.
