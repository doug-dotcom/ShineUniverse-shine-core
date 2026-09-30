# Foundation Layer 76 — Bounded safe-response executor

**Status:** IMPLEMENTED — CI and production verification pending  
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

## Invariant

> A safe response may be executable without becoming authoritative repair. Layer 76 can collect evidence or re-run existing work materialisation; it can never rewrite truth or history.
