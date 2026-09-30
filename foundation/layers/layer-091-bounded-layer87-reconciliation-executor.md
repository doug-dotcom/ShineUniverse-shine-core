# Foundation Layer 91 — Bounded Layer-87 reconciliation executor

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** execute the single bounded action Layer 90 may admit: independent Layer-87 reconciliation of one overdue successful Layer-86 execution

Layer 90 can identify a pure omission where a successful Layer-86 execution is old enough to require Layer-87 reconciliation, no Layer-87 receipt exists, and the Layer-89 incident lifecycle is active.

Layer 91 is the narrow execution boundary for that case.

> **One Layer-86 event. One current Layer-90 decision. One existing Layer-87 reconciler. Nothing else.**

## Executor

`foundation.execute_case_audit_overdue_layer87_reconciliation_v1(...)`

Before invoking anything, Layer 91 requires the exact Layer-86 event to exist, be successful, be older than reconciliation grace, have no Layer-87 receipt, sit under an active Layer-89 watch/incident, and still receive an admitted `run-independent-layer87-reconciliation` decision from Layer 90 requiring `layer-87-bounded-reconciler`.

Layer 91 re-checks the no-authority, no-rerun and no-rewrite flags immediately before execution.

## Only executable target

The only function Layer 91 may invoke is:

`foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(...)`

There is no dynamic function selection and no arbitrary-SQL path.

## Closing the bypass

Layer 91 revokes direct `service_role` EXECUTE on the Layer-87 writer.

The route becomes:

**Layer 90 policy → Layer 91 exact-target gate → Layer 87 reconciler**

Layer 91 is a private-schema `SECURITY DEFINER` function with an empty search path. Service role cannot call Layer 87 directly.

## Execution evidence

Ledger:

`foundation.case_audit_reconcile_exec_reconcile_exec_events`

Events are `executed`, `denied` or `failed`. The ledger is append-only and permits only one successful Layer-91 execution per target Layer-86 event.

Semantic replay returns the original Layer-91 receipt instead of invoking Layer 87 again.

## Allowed effect

A successful call can create exactly one immutable Layer-87 reconciliation receipt. Layer 87 remains responsible for the truth of that receipt and may conclude:

- `reconciled`
- `missing-layer82-receipt`
- `invalid-layer82-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Layer 91 never reinterprets the result.

## Forbidden effects

Layer 91 cannot rerun Layer 86, Layer 82, Layer 81 or verification; manufacture or repair evidence; rewrite Layer-87/86/82 receipts; alter Layer-89 incident history; mutate release truth; or create arbitrary execution authority.

## Acceptance coverage

CI proves:

- one overdue successful Layer-86 event with no Layer-87 receipt can be admitted through the real Layer-90 policy;
- exactly one Layer-87 receipt is created through the real Layer-87 reconciler;
- replay returns the first Layer-91 receipt;
- within-grace Layer-86 targets are denied;
- non-successful Layer-86 targets are denied;
- missing targets are not applicable;
- Layer-81, Layer-82 and Layer-86 counts do not change;
- direct service-role Layer-87 bypass is revoked;
- service role cannot directly insert Layer-91 ledger rows;
- append-only and role boundaries hold.

## Deliberate split implementation

Layer 91 is intentionally split into schema, runtime and summary SQL files so each control boundary remains small and independently reviewable while CI applies them as one ordered layer.

## Invariant

> Layer 91 may complete missing Layer-87 reconciliation. It may never manufacture or repair the truth being reconciled.
