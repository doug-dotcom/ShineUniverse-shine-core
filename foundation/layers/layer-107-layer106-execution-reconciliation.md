# Foundation Layer 107 — Layer-106 execution reconciliation

**Status:** LIVE — CI green and production verification complete  
**Scope:** independently reconcile each successful Layer-106 bounded Layer-102 reconciliation execution against durable Layer-102 truth

Layer 106 closes direct service-role access to Layer 102.

Layer 107 closes the next trust seam:

> **Layer 106 saying it invoked Layer 102 is not evidence that Layer 102 actually produced the claimed receipt.**

## Independent evaluator

`foundation.evaluate_case_audit_layer106_execution_outcome_v1(...)`

For one successful Layer-106 event, the evaluator independently re-checks:

- the exact Layer-101 target;
- the Layer-105 decision snapshot and Layer-106 policy fingerprint;
- the bound Layer-104 incident event;
- the before/after Layer-103 coverage snapshots;
- the durable Layer-102 receipt;
- the Layer-102 receipt SHA-256 and proof structure;
- the Layer-106 action result against the durable Layer-102 receipt.

## Truth states

Layer 107 records one of:

- `reconciled`
- `missing-layer102-receipt`
- `invalid-layer102-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Integrity failures dominate downstream claim mismatches. Missing Layer-102 truth is recorded as missing; it is never manufactured.

## Reconciler

`foundation.run_case_audit_layer106_execution_reconciliation_v1(...)`

The reconciler accepts one Layer-106 event ID, evaluates it, and appends one immutable Layer-107 receipt.

It does **not** invoke Layer 106, Layer 102, Layer 101, Layer 97, Layer 96, Layer 92, Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification.

Replay returns the existing Layer-107 receipt.

## Ledger

`foundation.case_audit_layer106_exec_reconciliations`

The ledger is append-only, RLS protected and explicitly denies browser-client access. Service role can invoke the Layer-107 reconciler but cannot directly insert rows.

## Read boundary

Foundation runtime and service role may read Layer-107 evaluation and summary functions. Gateway reads through existing `foundation_runtime` membership only. Shine Core, Shine Defence and browser roles cannot reconcile.

The direct Layer-102 service-role bypass closed by Layer 106 must remain closed.

## Acceptance coverage

CI proves:

- faithful Layer-106 claim + valid Layer-102 receipt → `reconciled`;
- missing Layer-102 receipt → `missing-layer102-receipt`;
- valid Layer-102 receipt with mismatched Layer-106 result → `execution-receipt-mismatch`;
- malformed Layer-102 proof → `invalid-layer102-receipt`;
- altered Layer-106 policy fingerprint → `policy-drift`;
- all five states can be durably recorded without changing Layer-106, Layer-102 or Layer-101 counts;
- replay returns the existing receipt;
- direct service-role Layer-102 execution remains revoked;
- direct service-role ledger insert is denied;
- role and append-only boundaries hold.

## Production proof

Layer 107 is deployed in the Shine Foundation Supabase project as migration:

`20261001042950 — foundation_layer_107_layer106_execution_reconciliation`

Pull request **#151** passed the complete Foundation + Concierge and Shine Defence workflows.

Live production verification confirms:

- Layer-107 ledger, evaluator, reconciler and summary exist;
- current Layer-106 execution count: **0**;
- current Layer-107 reconciliation count: **0**;
- current Layer-102 reconciliation count: **0**;
- current Layer-101 execution count: **0**;
- `service_role` can invoke the Layer-107 reconciler but cannot directly INSERT Layer-107 ledger rows;
- direct `service_role` execution of the Layer-102 reconciler remains **revoked**;
- Foundation runtime, Gateway, Shine Core, Shine Defence, anon and authenticated cannot reconcile;
- Foundation runtime can read the Layer-107 summary;
- Gateway reads the summary only through existing `foundation_runtime` membership;
- Layer-106 production summary remains empty and continues to report `directLayer102ServiceRoleBypassAllowed=false`;
- Layer-105 production cause remains **none**;
- a nonexistent Layer-106 target invoked under `service_role` returns `not-applicable / case-audit-layer106-event-not-found`;
- that negative probe reports no Layer-106/102/101/97/96/92/91/87/86/82/81 or verification rerun and no mutation;
- Supabase security advisors report **0 findings** after deployment;
- the three new Layer-107 indexes are reported unused, expected while the production reconciliation ledger is empty.

## Invariant

> Layer 107 may attest what Layer 106 actually did. It may never make Layer 106's claim true.
