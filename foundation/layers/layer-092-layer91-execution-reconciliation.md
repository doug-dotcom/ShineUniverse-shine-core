# Foundation Layer 92 — Layer-91 execution reconciliation

**Status:** LIVE — CI green and production verification complete  
**Scope:** independently reconcile each successful Layer-91 bounded Layer-87 reconciliation execution against durable Layer-87 truth

Layer 91 closes the direct service-role bypass into Layer 87.

Layer 92 closes the next trust seam:

> **Layer 91 saying it invoked Layer 87 is not evidence that Layer 87 actually produced the claimed receipt.**

## Independent evaluator

`foundation.evaluate_case_audit_layer91_execution_outcome_v1(...)`

For one successful Layer-91 event, the evaluator independently re-checks:

- the exact Layer-86 target;
- the Layer-90 decision snapshot and Layer-91 policy fingerprint;
- the bound Layer-89 incident event;
- the before/after Layer-88 coverage snapshots;
- the durable Layer-87 receipt;
- the Layer-87 receipt SHA-256 and proof structure;
- the Layer-91 action result against the durable Layer-87 receipt.

## Truth states

Layer 92 records one of:

- `reconciled`
- `missing-layer87-receipt`
- `invalid-layer87-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Integrity failures dominate downstream claim mismatches. A missing receipt is recorded as missing; it is never manufactured.

## Reconciler

`foundation.run_case_audit_layer91_execution_reconciliation_v1(...)`

The reconciler accepts one Layer-91 event ID, evaluates it, and appends one immutable Layer-92 receipt.

It does **not** invoke Layer 91, Layer 87, Layer 86, Layer 82, Layer 81 or verification.

Replay returns the existing Layer-92 receipt.

## Ledger

`foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations`

The ledger is append-only, RLS protected and explicitly denies browser-client access. Service role can invoke the bounded reconciler but cannot directly insert reconciliation rows.

## Read boundary

Foundation runtime and service role may read Layer-92 evaluation and summary functions. Gateway reads through existing `foundation_runtime` membership only. Shine Core, Shine Defence, anon and authenticated cannot reconcile.

## Acceptance coverage

CI proves:

- truthful Layer-91 claim + valid Layer-87 receipt → `reconciled`;
- missing Layer-87 receipt → `missing-layer87-receipt`;
- valid Layer-87 receipt with mismatched Layer-91 result → `execution-receipt-mismatch`;
- malformed Layer-87 proof → `invalid-layer87-receipt`;
- altered Layer-91 policy fingerprint → `policy-drift`;
- all five states can be durably recorded without changing Layer-91 or Layer-87 counts;
- replay returns the existing receipt;
- direct service-role ledger insert is denied;
- role and append-only boundaries hold.

## Production proof

Layer 92 is deployed in the Shine Foundation Supabase project as migration:

`20260930235834 — foundation_layer_092_layer91_execution_reconciliation`

Pull request **#120** passed the complete Foundation + Concierge and Shine Defence workflows after CI caught and corrected one fixture-only fingerprint-width error. The runtime design was unchanged by that correction.

Live production verification confirms:

- Layer-92 ledger, evaluator, reconciler and summary exist;
- current Layer-91 execution count: **0**;
- current Layer-87 reconciliation count: **0**;
- current Layer-92 reconciliation count: **0**;
- `service_role` can invoke the Layer-92 reconciler but cannot directly INSERT Layer-92 ledger rows;
- Foundation runtime, Gateway, Shine Core, Shine Defence, anon and authenticated cannot reconcile;
- Foundation runtime can read the Layer-92 summary;
- Gateway reads the summary only through existing `foundation_runtime` membership;
- a nonexistent Layer-91 target invoked under `service_role` returns `not-applicable / case-audit-layer91-event-not-found`;
- that negative probe performs no Layer-87/86/82/81 or verification rerun and no mutation;
- all three new Layer-92 indexes are reported unused, which is expected while the production ledger is empty;
- Supabase reports no Layer-92-specific security finding.

A separate migration landed after Layer 92 and currently produces one project-wide INFO security advisor notice for `public.grant_protocol` having RLS enabled without a policy. That finding is not caused by Layer 92 and is deliberately not altered by this layer.

## Invariant

> Layer 92 may attest what Layer 91 actually did. It may never make Layer 91's claim true.
