# Foundation Layer 55 — Defence owner outcome receipts

**Status:** LIVE — release binding intentionally withheld by readiness gate

Layer 55 closes the communication loop between Foundation and the dependency owner.

Layers 52–54 established:

1. Defence returns bounded owner evidence.
2. Foundation independently retests canonical readiness.
3. Foundation reconciles the owner claim against canonical truth.

The remaining seam was visibility back to the owner.

Before Layer 55, Defence could submit evidence but could not read the final reconciliation result without broader ledger access.

Layer 55 adds a least-privilege read-only receipt projection.

## Owner receipt projection

Function:

`foundation.get_readiness_dependency_remediation_owner_outcome_receipts_v1(environment, limit)`

Reader role:

`shine_defence_runtime`

The function returns only reconciliation receipts for handoffs that were originally addressed to:

- owner component: `universe`
- dependency service: `foundation.defence`

It exposes no unrelated Foundation remediation history.

## No ledger access

Defence still has no direct SELECT privilege on:

- `foundation.readiness_dependency_remediation_evidence_retests`
- `foundation.readiness_dependency_remediation_outcome_reconciliations`

The receipt function is therefore the only owner-facing outcome path.

This follows Supabase's current least-privilege guidance: functions must have EXECUTE explicitly restricted to the intended role, while underlying tables remain unavailable to callers that do not need direct access.

## Integrity filtering

Every candidate receipt is revalidated through:

`foundation.get_readiness_dependency_remediation_outcome_reconciliation_status_v1(...)`

Only reconciliation rows that are:

- `completed`;
- integrity verified;
- bound to the expected reconciliation ID

are exposed as owner receipts.

Invalid or unverifiable rows are not exposed as outcome content.

Instead, they increase:

`invalidCount`

so the owner can see that a receipt could not safely be surfaced without receiving unverified data.

## Historical receipts

Unlike the Layer-50 pending-work inbox, Layer 55 does **not** discard a reconciliation merely because the original handoff later becomes stale.

That is intentional.

A reconciliation receipt is historical evidence of what Foundation concluded after a completed owner handoff.

The current handoff state is still included in the receipt as:

`handoffState`

so Defence can distinguish a current handoff from historical work without losing the historical outcome.

## Receipt contents

A verified receipt includes:

- handoff ID;
- proposal ID;
- source readiness incident event ID;
- routed scopes;
- handoff state;
- owner-reported outcome;
- evidence-return ID and timestamp;
- independent retest ID and cycle ID;
- source readiness state;
- canonical readiness state;
- canonical condition fingerprint;
- canonical outcome;
- reconciliation verdict;
- reconciliation reason code;
- semantic condition-change flag;
- reconciliation SHA-256;
- reconciliation timestamp.

It explicitly carries:

- `receiptState: verified`
- `integrityVerified: true`
- `readinessChanged: false`
- `incidentClosurePerformed: false`
- `approvalGranted: false`
- `executionAuthorityGranted: false`
- `executesRemediation: false`

## Bounded projection

The receipt call is bounded by:

`limit`

with an accepted range of:

**1–100**

The response includes:

- `receiptCount`
- `visibleCount`
- `invalidCount`
- `hasMore`

The default limit is:

**25**

## Access boundary

CI proves:

- `shine_defence_runtime` can execute the receipt function;
- `service_role` cannot use the Defence owner projection;
- `foundation_runtime` cannot use the Defence owner projection;
- Defence cannot directly SELECT the reconciliation ledger;
- Defence cannot directly SELECT the independent retest ledger;
- only handoffs addressed to Defence are eligible;
- only integrity-verified reconciliation results are exposed;
- owner receipt projection remains read-only and authority-free.

## Functional CI

Full Foundation functional run:

`36518359219`

passed end-to-end.

Layer-55 steps:

- Apply Foundation owner outcome receipts: **success**
- Run Foundation owner outcome receipt tests: **success**

All downstream Shine Defence acceptance tests also remained green.

A fully rolled-back production-schema dry run completed successfully before deployment.

## Production deployment

Layer 55 is live.

Production privilege verification:

- receipt function exists: **yes**
- Defence can execute receipt function: **yes**
- service role can execute owner projection: **no**
- Foundation runtime can execute owner projection: **no**
- Defence direct reconciliation SELECT: **no**
- Defence direct retest SELECT: **no**

Current production receipt result:

- receipt count: **0**
- visible count: **0**
- invalid count: **0**

That is correct.

There is still no real dependency-remediation reconciliation chain in production because the active Foundation condition is a Gateway runtime-health issue rather than a dependency issue.

## Current readiness

At Layer-55 verification:

- Gateway runtime: **v90**
- health state: **unhealthy**
- reason: `critical-p95-latency`
- p95 latency: **10033.395 ms**
- critical threshold: **10000 ms**
- request count: **12**
- HTTP 5xx count: **0**
- runtime error count: **0**

Foundation remains:

- readiness: **not-ready**
- safe mode: **blocked**
- reason: `runtime-unhealthy`
- dependency impact: **operational**
- dependency affected scopes: **0**

Layer 55 does not alter this truth.

## Release identity

Layer 55 attempted the normal immutable release bind.

The binder rejected it with:

`release-identity-readiness-not-bindable`

because Foundation remains `not-ready`.

No bypass, forced bind or direct release-ledger mutation was used.

The canonical bound release remains:

`foundation:layer-49:1a8148a8`

Gateway remains:

**v90**

## Advisors

Post-deployment advisor review found:

- no new Layer-55-specific security finding;
- no new Layer-55-specific performance finding;
- Layer 55 adds no new table or index;
- pre-existing project-wide advisor notices remain unrelated.

## Invariant

> The owner that supplied evidence may see Foundation's verified conclusion for its own handoff, but only through a bounded read-only receipt. Seeing the verdict never grants authority to change it.
