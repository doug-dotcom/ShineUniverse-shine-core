# Foundation Layer 87 — Reconciliation executor reconciliation

**Status:** LIVE — CI green and production verification complete  
**Scope:** independently prove that a successful Layer-86 execution claim agrees with the durable Layer-82 receipt and the policy/incident evidence that authorised it

Layer 86 is now the only service-role path that can invoke Layer 82.

Layer 87 refuses to trust Layer 86 merely because it says it succeeded.

> **Execution evidence is a claim. Layer 87 proves whether the claim agrees with durable truth.**

## Evaluator

`foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(...)`

For one successful Layer-86 event it independently checks:

- the Layer-86 policy fingerprint;
- the stored Layer-85 admitted decision;
- the exact Layer-81 target binding;
- the exact Layer-84 incident event and semantic fingerprint;
- the durable Layer-82 reconciliation row;
- the Layer-82 proof SHA-256 and proof envelope;
- the Layer-86 action result against that durable Layer-82 row;
- the stored before/after Layer-83 coverage envelopes.

It executes nothing.

## Important semantic distinction

Layer 87's **reconciled** state means:

> Layer 86 truthfully reported what Layer 82 actually recorded.

That is deliberately separate from whether Layer 82's own outcome was healthy.

For example, Layer 82 may truthfully record `missing-proof`. If Layer 86 accurately reports that immutable negative outcome and all bindings are intact, Layer 87 can still mark the **Layer-86 execution claim** as reconciled.

This prevents Foundation from confusing *truthful bad news* with *dishonest execution evidence*.

## Reconciliation states

- `reconciled`
- `missing-layer82-receipt`
- `invalid-layer82-receipt`
- `execution-receipt-mismatch`
- `policy-drift`
- `incident-drift`
- `coverage-drift`

Invalid or missing Layer-82 evidence dominates policy/receipt claims because the durable target evidence must exist and be structurally trustworthy before the executor claim can be accepted.

## Immutable Layer-87 receipt

Runner:

`foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(...)`

Ledger:

`foundation.case_audit_verify_reconcile_exec_reconciliations`

Only one Layer-87 reconciliation exists per successful Layer-86 execution. Replay returns the first immutable receipt.

## Supporting index

Layer-87 receipts retain a foreign key to the exact Layer-82 reconciliation they verified. The covering Layer-82 FK index keeps that referential-integrity path indexed as the ledger grows:

`foundation.case_audit_verify_reconcile_exec_reconcile_layer82_idx`

## Authority boundary

Runner:

- service role only.

Read-only evaluator and summary:

- Foundation runtime;
- service role.

Foundation Gateway reads the summary only through its existing `foundation_runtime` membership and receives no direct grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

Service role cannot directly insert Layer-87 reconciliation rows.

## Deliberate non-actions

Layer 87 does not:

- invoke Layer 82;
- invoke Layer 86;
- invoke Layer 81;
- invoke Layer 77;
- create or repair upstream evidence;
- rewrite/delete any Layer-77, Layer-81, Layer-82 or Layer-86 receipt;
- change Layer-84 incident history;
- mutate release truth;
- grant approval or execution authority.

## Acceptance coverage

CI proves:

1. a truthful Layer-86 claim matching a structurally valid negative Layer-82 `missing-proof` receipt reconciles successfully;
2. a Layer-86 success claim with no durable Layer-82 receipt becomes `missing-layer82-receipt`;
3. a valid Layer-82 receipt with a mismatched Layer-86 action result becomes `execution-receipt-mismatch`;
4. an invalid Layer-82 proof hash becomes `invalid-layer82-receipt` and dominates other drift;
5. Layer-87 replay is idempotent;
6. Layer-82, Layer-86 and verification counts do not change while Layer 87 runs;
7. the Layer-87 ledger is append-only;
8. role and Gateway-inheritance boundaries remain intact.

## Production proof

Layer 87 is deployed in the Shine Foundation Supabase project as:

- `20260930215952 — foundation_layer_087_reconciliation_executor_reconciliation`

Advisor hardening added the Layer-82 foreign-key covering index. Two concurrent rooms applied the same idempotent `CREATE INDEX IF NOT EXISTS` one second apart, so migration history truthfully contains both entries:

- `20260930220436 — foundation_layer_087_reconciliation_executor_layer82_fk_index`
- `20260930220437 — foundation_layer_087_layer82_fk_index`

There is only one physical index:

`foundation.case_audit_verify_reconcile_exec_reconcile_layer82_idx`

Live production verification confirms:

- Layer-87 ledger, evaluator, runner and summary exist;
- current Layer-87 receipt count: **0**;
- current Layer-86 event count: **0**;
- current Layer-82 reconciliation count: **0**;
- current Layer-81 execution count: **0**;
- current Layer-77 verification count: **0**;
- current Layer-87 problem count: **0**;
- service role can run Layer 87 but cannot directly INSERT reconciliation rows;
- Foundation runtime cannot run Layer 87, but can use its read-only evaluator and summary;
- Gateway cannot run Layer 87 and reads the summary only through existing `foundation_runtime` membership with no direct grant;
- Shine Core, Shine Defence and browser roles cannot run Layer 87;
- a nonexistent Layer-86 event returns `not-applicable / event-not-found`;
- that harmless negative probe creates no Layer-87 receipt and changes no upstream ledger count;
- Layer 83 remains **idle** and Layer 84 remains **normal**;
- Supabase security advisors report no Layer-87-specific finding;
- Supabase no longer reports an unindexed Layer-87 foreign key;
- the three Layer-87 indexes currently appear only as expected `unused_index` INFO because the healthy production ledger is empty.

## Invariant

> Layer 87 may prove an execution claim. It may never improve the truth that execution produced.
