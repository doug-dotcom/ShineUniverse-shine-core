# Foundation Layer 50 — Defence owner inbox

**Status:** LIVE — release binding intentionally withheld by readiness gate

Layer 50 closes the delivery gap left after Layer 49.

Layer 48 can route a remediation handoff to the correct dependency owner and Layer 49 lets that owner acknowledge it, but the Defence runtime previously had no least-privilege read surface for discovering which handoffs were actually waiting for it.

Layer 50 adds that surface without weakening any existing authority boundary.

## Owner inbox

The reader is:

`foundation.get_readiness_dependency_remediation_owner_inbox_v1(text,integer)`

The only application role allowed to execute it is:

`shine_defence_runtime`

The inbox is fixed to the registered owner route:

- owner component: `universe`
- dependency service: `foundation.defence`

It returns only handoffs that are simultaneously:

- addressed to Defence;
- in the requested environment;
- current under Layer-48 handoff status;
- integrity verified;
- still pending under Layer-49 response status.

Stale, invalid or already-responded handoffs do not appear.

## Least privilege

Layer 50 deliberately does **not** grant Defence direct `SELECT` access to:

`foundation.readiness_dependency_remediation_handoffs`

Instead, the SECURITY DEFINER inbox function exposes the bounded owner packet required for acknowledgement.

Function EXECUTE is revoked from:

- PUBLIC
- anon
- authenticated
- service_role
- foundation_runtime
- foundation_gateway

and granted only to:

`shine_defence_runtime`

The existing Layer-49 response function remains the only acknowledgement write path.

## Returned evidence

Every visible packet includes the exact:

- handoff ID;
- proposal ID;
- readiness incident event ID;
- routed scopes;
- handoff payload;
- handoff SHA-256;
- proposal SHA-256;
- semantic condition fingerprint;
- routing fingerprint;
- creation time.

Every item and the inbox envelope explicitly carry:

- approval granted: **false**
- execution authority granted: **false**
- executes action: **false**

Reading an owner packet therefore never grants permission to repair or mutate anything.

## Index

Layer 50 adds:

`readiness_remediation_handoffs_owner_inbox_idx`

over:

- owner component;
- dependency service;
- environment;
- descending handoff sequence.

The index is advisory-clean apart from the expected unused-index INFO immediately after creation on the very small production handoff ledger.

## CI proof

Full Foundation workflow run:

`36508072094`

passed end-to-end.

The Layer-50 acceptance test proves:

- service_role cannot read the owner inbox;
- foundation_runtime cannot read the owner inbox;
- Defence runtime can read it;
- Defence still has no direct handoff-table SELECT;
- a current integrity-verified pending handoff is visible;
- a stale handoff disappears;
- an acknowledged handoff disappears;
- inbox access never grants approval or execution authority.

All downstream Shine Defence persistence tests also passed after Layer 50 was inserted into the Foundation chain.

## Production proof

The production function and owner-route index were deployed successfully.

Immediately after deployment, the inbox correctly exposed one current pending packet:

`4c2d0de7-98b8-4a52-b20b-7901ae3b0b3c`

for:

`foundation.defence`

with all six routed scopes and integrity verification intact.

Privilege verification showed:

- Defence inbox EXECUTE: **yes**
- service_role inbox EXECUTE: **no**
- Foundation runtime inbox EXECUTE: **no**
- Defence direct handoff-table SELECT: **no**

The available Supabase administration connection still cannot assume `shine_defence_runtime`.

Layer 50 did not weaken that boundary and did not manufacture an owner acknowledgement.

## Fresh readiness transition

Before closing Layer 50, Foundation ran a fresh semantic readiness retest.

The current Gateway health evidence had moved from degraded to unhealthy:

- runtime version: **90**
- health state: **unhealthy**
- reason: `critical-p95-latency`
- p95 latency: **10037.593 ms**
- critical threshold: **10000 ms**
- request count: **12**
- HTTP 5xx count: **0**
- runtime error count: **0**

The retest appended cycle:

`a1bec795-6803-4a16-a6b8-e7b8a9fecc3b`

and incident event:

`20a4cf95-8129-42ed-a6f9-3be8f0f31750`

with:

- readiness: **not-ready**
- severity: **critical**
- transition: **changed**
- reason codes:
  - `runtime-unhealthy`
  - `dependency-blocked`

That semantic change automatically made the previous Layer-49 proposal/handoff stale.

The Layer-50 inbox then became empty:

- pending count: **0**
- visible count: **0**

This is the intended fail-closed behaviour: stale owner work disappears rather than remaining actionable.

## Release identity

Layer 50 attempted the normal immutable Foundation release bind.

The binder rejected it with:

`release-identity-readiness-not-bindable`

because live readiness is currently:

`not-ready`

No bypass, manual ledger edit or weakened policy was used.

The authoritative bound release therefore remains:

`foundation:layer-49:1a8148a8`

Gateway runtime remains:

**v90**

The existing release identity itself still reports **PASS** against the deployed Gateway and GitHub-OIDC publication evidence, while separately reporting that readiness has changed since binding.

Layer 50 is deployed and operational, but it is intentionally **not release-bound** until Foundation returns to a bindable readiness state.

## Advisors

Post-deployment advisor review found:

- no Layer-50-specific security finding;
- the new owner-inbox index appears only as expected unused-index INFO immediately after creation;
- pre-existing project-wide security/performance advisories remain unrelated to Layer 50.

## Invariant

> Defence may discover only the current work addressed to it. Discovery grants no authority, stale work disappears automatically, and Foundation will not advance its immutable release identity while readiness is not bindable.
