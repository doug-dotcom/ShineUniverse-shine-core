# Foundation Layer 86 — Bounded overdue reconciliation executor

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** execute the single bounded action Layer 85 may admit: independent Layer-82 reconciliation of one overdue Layer-81 execution

Layer 85 can decide that a successful Layer-81 execution is missing only its Layer-82 reconciliation receipt.

Layer 86 is the narrow execution boundary for that case.

> **One Layer-81 event. One current policy decision. One existing Layer-82 reconciler. Nothing else.**

## Executor

`foundation.execute_case_audit_overdue_reconciliation_v1(...)`

Before invoking anything, Layer 86 requires the exact Layer-81 event to exist, be successful, be older than reconciliation grace, have no Layer-82 receipt, sit under an active Layer-84 watch/incident, and still receive an admitted `run-independent-reconciliation` decision from Layer 85 requiring `layer-82-bounded-reconciler`.

Layer 86 re-checks every no-authority, no-rerun and no-rewrite flag immediately before execution.

## Only executable target

The only function Layer 86 may invoke is:

`foundation.run_case_audit_verify_exec_reconciliation_v1(...)`

There is no dynamic function selection or arbitrary-SQL path.

## Closing the bypass

Layer 86 revokes direct `service_role` EXECUTE on the Layer-82 writer.

The route becomes:

**Layer 85 policy → Layer 86 exact-target gate → Layer 82 reconciler**

Layer 86 is a private-schema `SECURITY DEFINER` function with an empty search path. Its owner may invoke Layer 82 only after all Layer-86 checks pass; service role cannot call Layer 82 directly.

## Execution evidence

Ledger:

`foundation.case_audit_verify_reconcile_exec_events`

Events are `executed`, `denied` or `failed`. The ledger is append-only and permits only one successful Layer-86 execution per target Layer-81 event.

Semantic replay returns the original Layer-86 receipt instead of invoking Layer 82 again.

## Allowed effect

A successful call can create exactly one immutable Layer-82 reconciliation receipt. That receipt may truthfully conclude `reconciled`, `missing-proof`, `receipt-mismatch`, `invalid-proof`, `evidence-drift` or `coverage-drift`.

Layer 86 never reinterprets the result.

## Forbidden effects

Layer 86 cannot rerun Layer 81, Layer 77 or Layer 76; manufacture or repair evidence; rewrite any Layer-77/81/82 proof or receipt; alter Layer-84 history; mutate release truth; grant approval; or grant new execution authority.

## Acceptance coverage

CI uses real Layer-76 evidence, real Layer-77 verification and the real Layer-82 reconciler to prove:

- overdue unreconciled Layer-81 execution → one real Layer-82 receipt;
- within-grace target → denied;
- non-executed Layer-81 target → denied;
- missing target → not applicable;
- replay → original Layer-86 receipt;
- Layer-81 and Layer-77 counts unchanged;
- exactly one Layer-82 receipt created;
- direct service-role Layer-82 bypass revoked;
- direct Layer-86 ledger insert denied;
- append-only and role boundaries hold.

## Invariant

> Layer 86 may complete missing reconciliation. It may never manufacture the truth being reconciled.
