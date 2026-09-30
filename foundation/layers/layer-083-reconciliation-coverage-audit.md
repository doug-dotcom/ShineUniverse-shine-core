# Foundation Layer 83 — Reconciliation coverage audit

**Status:** LIVE — CI green and production verification complete  
**Scope:** prove that every successful Layer-81 execution eventually receives one valid Layer-82 reconciliation receipt

Layer 82 can independently reconcile one successful Layer-81 execution.

Layer 83 asks the estate-level question:

> **Have all successful bounded verification executions actually been reconciled?**

## Reader

`foundation.get_case_audit_verify_reconcile_coverage_v1(...)`

Inputs:

- environment;
- evaluation time;
- explicit reconciliation grace period;
- visible-item limit.

It reads only:

- successful Layer-81 executor events;
- Layer-82 reconciliation receipts.

It writes nothing and executes no verifier.

## Denominator

Only Layer-81 events with:

`event_type = executed`

require reconciliation.

Denied and failed Layer-81 attempts are excluded because they claim no successful Layer-77 invocation.

## Per-execution states

- **reconciled** — a structurally valid Layer-82 receipt reports a healthy reconciliation;
- **pending** — no Layer-82 receipt yet, but the successful Layer-81 execution is still inside the reconciliation grace window;
- **overdue** — no reconciliation receipt and the grace window has expired;
- **invalid-reconciliation** — a Layer-82 receipt exists but its own hash, envelope or state semantics fail integrity;
- **missing-proof** — Layer 82 validly reconciled the execution and found that the claimed Layer-77 proof is absent;
- **receipt-mismatch** — Layer 82 validly recorded a Layer-81/Layer-77 receipt disagreement;
- **invalid-proof** — Layer 82 validly recorded a bad Layer-77 proof;
- **evidence-drift** — Layer 82 validly recorded that current durable evidence no longer supports the Layer-77 result;
- **coverage-drift** — Layer 82 validly recorded disagreement with visible Layer-78 target coverage.

## Coverage is not health

A reconciliation receipt can be perfectly valid while truthfully reporting a problem.

Therefore Layer 83 exposes two separate percentages:

### Reconciliation coverage

> What percentage of successful Layer-81 executions have a Layer-82 receipt?

### Healthy reconciliation

> What percentage of successful Layer-81 executions have a valid Layer-82 receipt whose outcome is `reconciled`?

For example, 100% reconciliation coverage with one `evidence-drift` receipt is **not** 100% healthy.

## Independent reconciliation-receipt integrity

Layer 83 does not trust a Layer-82 row merely because it exists.

It independently recomputes the reconciliation proof SHA-256 and binds:

- reconciliation ID;
- Layer-81 executor event;
- environment;
- Layer-76 target;
- Layer-79 incident event;
- Layer-77 verification ID/state;
- reconciliation state and reason;
- proof-integrity result;
- Layer-81 receipt-match result;
- current-evidence-match result;
- coverage visibility/match result;
- verification snapshot;
- current evidence evaluation;
- current coverage snapshot;
- exact Layer-81 action result;
- reconciliation timestamp;
- every no-rerun/no-mutation/no-authority flag.

Malformed JSON flags or nullable proof fields fail closed as an invalid reconciliation receipt rather than crashing the audit.

## State semantics

The receipt's state must agree with its stored evidence:

- **reconciled** requires a verification ID and true proof/receipt/current-evidence checks; visible coverage must agree;
- **missing-proof** requires no verification ID;
- **receipt-mismatch** requires a verification ID and false receipt-match check;
- **invalid-proof** requires a verification ID and false proof-integrity check;
- **evidence-drift** requires valid proof/receipt checks and a false current-evidence check;
- **coverage-drift** requires valid proof/receipt/current-evidence checks plus visible coverage disagreement.

A hash-valid receipt with semantically impossible fields is therefore still **invalid-reconciliation**.

## Overall states

- **idle** — no successful Layer-81 executions exist;
- **normal** — every successful execution has a healthy reconciliation;
- **pending** — all missing reconciliation receipts are still inside grace;
- **gap** — at least one reconciliation is overdue or validly reports a negative reconciliation outcome;
- **invalid** — at least one Layer-82 reconciliation receipt itself is structurally or semantically invalid.

`invalid` dominates `gap`.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Foundation Gateway reads only through its existing `foundation_runtime` membership and receives no direct grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

## Deliberate non-actions

Layer 83 does not:

- run Layer 82;
- run Layer 81;
- run Layer 77;
- rerun Layer 76;
- create or repair durable evidence;
- rewrite any proof or receipt;
- mutate incident history;
- mutate release truth.

## Acceptance coverage

CI proves:

- a valid reconciliation is healthy;
- a recent unreconciled execution is pending;
- an overdue unreconciled execution is a gap;
- a valid `missing-proof` reconciliation is covered but unhealthy;
- a valid `evidence-drift` reconciliation is covered but unhealthy;
- a reconciliation with a bad proof hash is `invalid-reconciliation`;
- denied Layer-81 executions do not enter the denominator;
- receipt coverage and healthy reconciliation percentages differ correctly;
- empty environments report 100% coverage and health;
- Gateway read remains inherited only;
- Core, Defence and browser roles remain denied.

## Production proof

Layer 83 is deployed in the Shine Foundation Supabase project as migration:

`20260930133108 — foundation_layer_083_reconciliation_coverage_audit`

Live production verification confirms:

- the Layer-83 coverage reader exists and executes successfully;
- current production state: **idle**;
- successful Layer-81 executions: **0**;
- reconciliation-required count: **0**;
- reconciliation receipt count: **0**;
- problem count: **0**;
- reconciliation coverage: **100%**;
- healthy reconciliation: **100%**;
- reconciliation-proof integrity recomputation: **true**;
- verification rerun: **false**;
- Layer-81 rerun: **false**;
- mutation performed: **false**;
- Foundation runtime and service role can read;
- Gateway can read only through existing `foundation_runtime` membership;
- Gateway has no direct EXECUTE grant;
- Shine Core, Shine Defence and browser roles cannot read;
- Supabase security advisors report no Layer-83-specific finding.

## Invariant


> Reconciliation is not complete because Layer 82 exists. It is complete only when every successful Layer-81 execution has a valid reconciliation receipt.
