# Foundation Layer 51 — Readiness cause separation

**Status:** LIVE — release binding intentionally withheld by readiness gate

Layer 51 fixes a control-plane attribution defect discovered while extending the Layer-50 Defence handoff loop.

Foundation correctly knew that Gateway runtime health was unhealthy, but the service dependency roll-up also folds a service's **own** native health into its overall `effectiveState`. The Layer-30 readiness evaluator was then treating that aggregate service state as though it were a dependency-edge failure.

The result was an impossible combination in production:

- readiness reason: `runtime-unhealthy`;
- readiness reason: `dependency-blocked`;
- blocked dependency scopes: **0**;
- guarded dependency scopes: **0**;
- degraded dependency scopes: **0**.

A dependency-remediation proposal consequently failed with:

`readiness-remediation-no-affected-scopes`

Layer 51 separates those two meanings.

## Cause separation

Foundation now preserves both values:

- **service effective state** — the aggregate service roll-up, which may be blocked because Gateway itself is unhealthy;
- **dependency impact state** — derived only from actual dependency-edge impacts.

Dependency impact is evaluated in strict order:

1. blocked scopes;
2. guarded scopes;
3. unknown dependency-edge impact;
4. degraded scopes;
5. otherwise operational.

Readiness reason codes for:

- `dependency-blocked`
- `dependency-guarded`
- `dependency-degraded`
- `dependency-unknown`

now come only from dependency-edge impact.

Gateway's own health continues to be evaluated independently.

An unhealthy Gateway therefore still drives Foundation to `not-ready`, but it no longer fabricates a dependency failure.

## Diagnostic projection

The readiness response now exposes:

- `checks.dependencyRollup.state` — true dependency impact;
- `checks.dependencyRollup.serviceEffectiveState` — aggregate service state retained for diagnosis.

This preserves visibility into the original roll-up without conflating its meaning.

## Dependency remediation applicability

`foundation.propose_readiness_dependency_remediation_v1(...)`

no longer throws when the current readiness incident contains no dependency scopes.

It now returns a bounded non-executing response:

- proposed: **false**
- status: **not-applicable**
- reason: `readiness-remediation-no-dependency-scopes`
- approval granted: **false**
- execution authority granted: **false**

Dependency remediation therefore exists only when there is an actual dependency scope to remediate.

## CI

Final full Foundation run:

`36510264394`

passed end-to-end.

The Layer-51 acceptance tests prove:

- Gateway own-runtime failure does not imply dependency failure;
- runtime failure still makes Foundation not-ready;
- the raw aggregate service state remains available diagnostically;
- a real blocked dependency still produces `dependency-blocked`;
- real blocked dependency scopes remain explicit;
- a readiness incident with no dependency scopes returns dependency remediation as not applicable instead of throwing.

All downstream Shine Defence acceptance tests also remained green.

## Production proof

Before Layer 51, the live critical readiness incident carried:

- `runtime-unhealthy`
- `dependency-blocked`

despite all dependency scope arrays being empty.

After deployment, live readiness reports:

- readiness: **not-ready**
- safe mode: **blocked**
- privileged operations: **blocked**
- worker operations: **blocked**
- reason codes:
  - `runtime-unhealthy`

Dependency projection is now:

- dependency impact state: **operational**
- service effective state: **blocked**
- blocked scopes: **0**
- guarded scopes: **0**
- degraded scopes: **0**

The aggregate service state remains blocked because Gateway itself is unhealthy. The dependency impact is correctly operational because no dependency edge is failing.

## Fresh semantic retest

Foundation then ran a fresh Layer-46 semantic retest.

Cycle:

`671f49c8-83ec-4d14-8240-3f59af86d50b`

New incident event:

`3224107d-b1cd-4c99-aa4f-db47093f07ed`

Condition fingerprint:

`1839a5cade89989319a5edc391abc2e3`

Transition:

**changed**

Current incident truth is now:

- readiness: **not-ready**
- severity: **critical**
- reason: `runtime-unhealthy`
- dependency scopes: **none**

The Layer-50 owner inbox remains empty because there is no current dependency-remediation handoff to Defence.

The dependency proposal function now returns:

`readiness-remediation-no-dependency-scopes`

as an explicit not-applicable result.

## Current runtime evidence

At verification time:

- Gateway runtime: **v90**
- health state: **unhealthy**
- reason: `critical-p95-latency`
- p95 latency: **10031.725 ms**
- critical threshold: **10000 ms**
- request count: **12**
- HTTP 5xx count: **0**
- runtime error count: **0**

This remains a runtime-health problem, not a dependency problem.

## Release identity

Layer 51 attempted the normal immutable release bind.

The binder rejected it with:

`release-identity-readiness-not-bindable`

because current Foundation readiness remains:

`not-ready`

No bypass or direct ledger edit was used.

The authoritative release therefore remains:

`foundation:layer-49:1a8148a8`

Gateway remains:

**v90**

The existing release identity continues to report **PASS** against deployment and GitHub-OIDC publication truth, while separately recording that readiness has changed since the Layer-49 bind.

## Advisors

Post-deployment advisor review found no new Layer-51-specific security or performance finding.

Existing project-wide advisor notices remain unchanged and are unrelated to this layer.

## Invariant

> A service's own failure must never be relabelled as a dependency failure. Dependency remediation is applicable only when a real dependency edge produces an affected scope.
