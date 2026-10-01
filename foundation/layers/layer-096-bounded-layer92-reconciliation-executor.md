# Foundation Layer 96 — Bounded Layer-92 reconciliation executor

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** execute the single bounded action Layer 95 may admit: independent Layer-92 reconciliation of one overdue successful Layer-91 execution

Layer 95 can identify a pure omission where a successful Layer-91 execution is old enough to require Layer-92 reconciliation, no Layer-92 receipt exists, and the Layer-94 incident lifecycle is active.

Layer 96 is the narrow execution boundary for that case.

> **One Layer-91 event. One current Layer-95 decision. One existing Layer-92 reconciler. Nothing else.**

## Executor

`foundation.execute_case_audit_overdue_layer92_reconciliation_v1(...)`

Before invoking anything, Layer 96 requires the exact Layer-91 event to exist, be successful, be older than reconciliation grace, have no Layer-92 receipt, sit under an active Layer-94 watch/incident, and still receive an admitted `run-independent-layer92-reconciliation` decision from Layer 95 requiring `layer-92-bounded-reconciler`.

Layer 96 re-checks every no-authority, no-rerun and no-rewrite flag immediately before execution.

## Only executable target

The only function Layer 96 may invoke is:

`foundation.run_case_audit_layer91_execution_reconciliation_v1(...)`

There is no dynamic function selection and no arbitrary-SQL path.

## Closing the bypass

Layer 96 revokes direct `service_role` EXECUTE on the Layer-92 writer.

The route becomes:

**Layer 95 policy → Layer 96 exact-target gate → Layer 92 reconciler**

Layer 96 is a private-schema `SECURITY DEFINER` function with an empty search path. Service role cannot call Layer 92 directly.

## Execution evidence

Ledger:

`foundation.case_audit_layer92_reconcile_exec_events`

Events are `executed`, `denied` or `failed`. The ledger is append-only and permits only one successful Layer-96 execution per target Layer-91 event.

Semantic replay returns the original Layer-96 receipt instead of invoking Layer 92 again.

## Allowed effect

A successful call can create exactly one immutable Layer-92 reconciliation receipt. Layer 92 remains responsible for the truth of that receipt and may conclude:

- `reconciled`
- `missing-layer87-receipt`
- `invalid-layer87-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Layer 96 never reinterprets the result.

## Forbidden effects

Layer 96 cannot rerun Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification; manufacture or repair evidence; rewrite Layer-92/91/87 receipts; alter Layer-94 incident history; mutate release truth; or create arbitrary execution authority.

## Acceptance coverage

CI proves:

- one overdue successful Layer-91 event with no Layer-92 receipt can pass through the Layer-96 exact-target gate;
- exactly one Layer-92 receipt is created through the real Layer-92 reconciler;
- replay returns the first Layer-96 receipt;
- within-grace Layer-91 targets are denied;
- non-successful Layer-91 targets are denied;
- missing targets are not applicable;
- Layer-91/87/86 counts do not change;
- direct service-role Layer-92 bypass is revoked;
- service role cannot directly insert Layer-96 ledger rows;
- append-only and role boundaries hold.

## Deliberate split implementation

Layer 96 is intentionally split into schema, runtime and summary SQL files so each control boundary remains small and independently reviewable while CI applies them as one ordered layer.

## Invariant

> Layer 96 may complete missing Layer-92 reconciliation. It may never manufacture or repair the truth being reconciled.
