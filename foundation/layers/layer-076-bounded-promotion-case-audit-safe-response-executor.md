# Foundation Layer 76 — Bounded safe-response executor

**Status:** LIVE — bounded executor green, production upgrade path converged and canonical schema verified  
**Scope:** execute only the two safe Layer-75 responses through a policy-coupled append-only dispatcher

Layer 75 classifies what may happen next.

Layer 76 adds a bounded execution path for exactly two actions:

1. `record-fresh-promotion-case-audit-observation`
2. `materialise-current-owner-handoff`

Nothing else is dispatchable.

## Why this is not a generic executor

The caller supplies only:

- action key;
- environment;
- request time.

There is:

- no SQL payload;
- no mutation payload;
- no arbitrary function name;
- no proposal object.

The dispatcher re-evaluates Layer 75 at execution time and requires the exact expected control:

- observation refresh → `evidence-only`
- current handoff materialisation → `layer-67-bounded-generator`

## Current incident binding

Execution requires a current Layer-74:

- detected;
- opened; or
- changed

event.

The event ID, source state and evidence fingerprint must match the current Layer-74 summary.

The execution receipt fingerprints the semantic Layer-75 decision plus the exact current Layer-74 event evidence.

## Safe target 1 — fresh evidence

Action:

`record-fresh-promotion-case-audit-observation`

Target:

`foundation.record_foundation_promoted_release_case_audit_observation_v1(...)`

This creates Layer-73 evidence only.

It cannot repair the case chain it observes.

## Safe target 2 — existing handoff materialiser

Action:

`materialise-current-owner-handoff`

Target:

`foundation.generate_foundation_promoted_release_owner_handoff_v1(...)`

This does not create a new repair mechanism.

It reuses Layer 67, which independently validates the live promotion-trust incident, Layer-66 response plan and owner route before creating anything.

Layer 67 remains idempotent.

## Explicit exclusions

Layer 76 cannot execute:

- registry repair;
- release-ledger repair;
- release rebind;
- automatic case-chain repair;
- history rewrite;
- history deletion;
- incident suppression;
- incident-history deletion.

Those action keys are rejected before policy dispatch.

## Append-only execution evidence

Ledger:

`foundation.case_audit_safe_response_exec_events`

Each attempt records:

- Layer-74 incident event;
- action;
- cause;
- semantic Layer-75 policy fingerprint;
- decision snapshot;
- incident snapshot;
- before evidence;
- bounded action result;
- after evidence;
- failure detail when applicable;
- timestamp.

Lifecycle:

- executed
- denied
- failed

The same incident/action/policy fingerprint replays to the existing receipt instead of dispatching twice.

### Identifier convergence

The original Layer-76 draft used a 64-character table identifier. PostgreSQL identifiers are limited to 63 bytes and silently truncated it.

Layer 76 therefore standardises the physical ledger name to:

`foundation.case_audit_safe_response_exec_events`

Fresh databases create that name directly. Existing production uses an idempotent convergence migration that renames the already-created table plus its identity sequence, constraints, indexes and append-only trigger so fresh CI and production expose the same canonical schema names.

Because PL/pgSQL stores function source text, an already-live rename also requires the Layer-76 executor/summary functions to be replaced so their SQL text references the new canonical table. A second idempotent convergence step reapplies those already-tested function definitions after the rename.

## Authority boundary

Execute:

`service_role`

Read summary/ledger:

- Foundation runtime
- service role

Denied execution:

- Foundation runtime
- Gateway
- Shine Core owner
- Shine Defence runtime
- browser roles

The service role cannot directly INSERT execution rows.

Layer 76 is deliberately not cron-driven.

## Acceptance coverage

Initial full Foundation CI run `36705378585` completed successfully and proved the bounded dispatcher itself across the full Foundation/Defence chain.

The first production advisor/schema sweep then exposed a naming issue before Layer 76 was stamped live: the original execution-ledger identifier was 64 characters, while PostgreSQL identifiers are limited to 63 bytes. PostgreSQL had silently truncated the physical table, sequence, constraints, indexes and trigger names.

The ledger was therefore standardised to:

`foundation.case_audit_safe_response_exec_events`

A dedicated identifier-convergence migration now upgrades already-live databases, while fresh databases create the short name directly.

The production rename also exposed a second upgrade-only seam: PL/pgSQL function source text still referenced the old identifier after the physical table rename. A separate idempotent function-convergence step now reapplies the already-tested executor/summary definitions against the canonical table.

Full convergence CI run `36706561597` completed successfully:

- Foundation contracts: **28/28**
- persistence: **211/211**
- canonical Layer-76 create: **PASS**
- identifier convergence: **PASS**
- stored-function convergence: **PASS**
- bounded executor tests: **PASS**
- downstream Shine Defence chain: **PASS**

CI proves:

- GAP dispatches only the Layer-67 bounded generator;
- successful dispatch records before/result/after evidence;
- semantic replay returns the existing execution receipt;
- observer freshness dispatches only Layer-73 evidence collection;
- Layer-75 denial records a denial and does not dispatch;
- history rewrite action is rejected before dispatch;
- service role cannot directly insert the execution ledger;
- runtime/Gateway/owner/Defence cannot execute;
- execution history is append-only.

## Production proof

Layer 76 is deployed in the Shine Foundation Supabase project through:

- `foundation_layer_076_promoted_release_case_audit_safe_response_executor`
- `foundation_layer_076_case_audit_safe_response_identifier_convergence`
- `foundation_layer_076_case_audit_safe_response_function_identifier_convergence`

Healthy production currently has no Layer-74 structural incident.

A direct bounded-executor attempt therefore correctly fails before dispatch with:

`promotion-case-audit-safe-response-current-incident-required`

and creates **no execution receipt**.

Current execution summary:

- total: **0**
- executed: **0**
- denied: **0**
- failed: **0**
- arbitrary SQL execution: **false**
- history rewrite performed: **false**
- release-truth mutation performed: **false**
- incident-history mutation performed: **false**

Canonical physical schema proof:

- table: `foundation.case_audit_safe_response_exec_events`
- old truncated table: **absent**
- identity sequence: `foundation.case_audit_safe_response_exec_events_event_sequence_seq`
- append-only trigger: `case_audit_safe_response_exec_append_only`
- PK/unique/FK/check constraints: canonical short names
- incident index: `case_audit_safe_response_exec_incident_idx`
- action index: `case_audit_safe_response_exec_action_idx`

Production privilege proof:

- service role can execute bounded dispatcher: **yes**
- Foundation runtime can execute: **no**
- Gateway can execute: **no**
- Shine Core owner can execute: **no**
- Shine Defence runtime can execute: **no**
- service role direct execution-ledger INSERT: **no**
- Foundation runtime can read bounded execution summary: **yes**
- anonymous/authenticated roles can read summary: **no**

Supabase advisors:

- no Layer-76-specific security finding;
- no Layer-76 unindexed foreign-key finding;
- the two Layer-76 query indexes currently appear as `unused_index` INFO because production contains zero execution receipts;
- remaining estate-wide findings are unrelated to Layer 76.

## Invariant

> A safe response may be executable without becoming authoritative repair. Layer 76 can collect evidence or re-run existing work materialisation; it can never rewrite truth or history.
