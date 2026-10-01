# Foundation Layer 101 — Bounded Layer-97 reconciliation executor

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** execute the single bounded action Layer 100 may admit: independent Layer-97 reconciliation of one overdue successful Layer-96 execution

Layer 100 can identify a pure omission where a successful Layer-96 execution is old enough to require Layer-97 reconciliation, no Layer-97 receipt exists, and the Layer-99 incident lifecycle is active.

Layer 101 is the narrow execution boundary for that case.

> **One Layer-96 event. One current Layer-100 decision. One existing Layer-97 reconciler. Nothing else.**

## Executor

`foundation.execute_case_audit_overdue_layer97_reconciliation_v1(...)`

Before invoking anything, Layer 101 requires the exact Layer-96 event to exist, be successful, be older than reconciliation grace, have no Layer-97 receipt, sit under an active Layer-99 watch/incident, and still receive an admitted `run-independent-layer97-reconciliation` decision from Layer 100 requiring `layer-97-bounded-reconciler`.

Layer 101 re-checks every no-authority, no-rerun and no-rewrite flag immediately before execution.

## Only executable target

The only function Layer 101 may invoke is:

`foundation.run_case_audit_layer96_execution_reconciliation_v1(...)`

There is no dynamic function selection and no arbitrary-SQL path.

## Closing the bypass

Layer 101 revokes direct `service_role` EXECUTE on the Layer-97 writer.

The route becomes:

**Layer 100 policy → Layer 101 exact-target gate → Layer 97 reconciler**

Layer 101 is a private-schema `SECURITY DEFINER` function with an empty search path. Service role cannot call Layer 97 directly.

## Execution evidence

Ledger:

`foundation.case_audit_layer97_reconcile_exec_events`

Events are `executed`, `denied` or `failed`. The ledger is append-only and permits only one successful Layer-101 execution per target Layer-96 event.

Semantic replay returns the original Layer-101 receipt instead of invoking Layer 97 again.

## Allowed effect

A successful call can create exactly one immutable Layer-97 reconciliation receipt. Layer 97 remains responsible for the truth of that receipt and may conclude:

- `reconciled`
- `missing-layer92-receipt`
- `invalid-layer92-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Layer 101 never reinterprets the result.

## Forbidden effects

Layer 101 cannot rerun Layer 96, Layer 92, Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification; manufacture or repair evidence; rewrite Layer-97/96/92 receipts; alter Layer-99 incident history; mutate release truth; or create arbitrary execution authority.

## Acceptance coverage

CI proves:

- one overdue successful Layer-96 event with no Layer-97 receipt can pass through the Layer-101 exact-target gate;
- exactly one Layer-97 receipt is created through the real Layer-97 reconciler;
- replay returns the first Layer-101 receipt;
- within-grace Layer-96 targets are denied;
- non-successful Layer-96 targets are denied;
- missing targets are not applicable;
- Layer-96/92/91 counts do not change;
- direct service-role Layer-97 bypass is revoked;
- service role cannot directly insert Layer-101 ledger rows;
- append-only and role boundaries hold.

## Invariant

> Layer 101 may complete missing Layer-97 reconciliation. It may never manufacture or repair the truth being reconciled.
