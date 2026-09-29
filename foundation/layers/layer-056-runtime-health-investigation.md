# Foundation Layer 56 — Cause-aware runtime-health investigation

**Status:** LIVE — release binding intentionally withheld by readiness gate

Layer 56 moves Foundation incident response onto the actual live failure mode.

Layers 51–55 completed the dependency-remediation lifecycle, but the active production incident is not dependency-caused. Gateway runtime health is unhealthy because p95 latency is above the critical policy threshold while dependency impact remains operational with zero affected scopes.

Layer 56 therefore fixes the response router and creates a first-class, non-executing runtime-health investigation proposal owned by `shine-core`.

## Cause-routing correction

Before Layer 56, the Layer-45 response router admitted:

`propose-dependency-remediation`

for any persistent readiness incident.

That generic routing was no longer correct after Layer 51 separated Gateway own-health failure from dependency-edge failure.

Layer 56 makes proposal admission cause-aware.

For the current production incident:

- runtime cause: **true**
- dependency cause: **false**
- dependency impact: **operational**
- dependency scope count: **0**

The router now returns:

### Dependency proposal

- decision: `not-applicable`
- reason: `readiness-incident-not-dependency-caused`

### Runtime-health investigation

- decision: `admit`
- control: `operator-investigation-proposal`
- reason: `persistent-runtime-health-incident-investigation`

This prevents Foundation from sending a runtime-own-health problem into the dependency-remediation path.

## Containment plan

`foundation.get_readiness_incident_containment_plan_v1(...)`

is now cause-aware.

The live recommended action is:

`maintain-safe-mode-and-propose-runtime-health-investigation`

The plan explicitly records:

- `automaticRuntimeRepair: false`
- `automaticDependencyRepair: false`
- `canonicalTruthMutationAllowed: false`
- `releaseRebindAllowedByThisPolicy: false`

Safe mode remains active while investigation proceeds.

## Runtime-health investigation proposal

New action:

`propose-runtime-health-investigation`

New proposal function:

`foundation.propose_readiness_runtime_health_investigation_v1(...)`

New append-only ledger:

`foundation.readiness_runtime_health_investigation_proposals`

New status function:

`foundation.get_readiness_runtime_health_investigation_proposal_status_v1(...)`

Only `service_role` may generate a proposal.

The following cannot generate one:

- `foundation_runtime`
- Foundation Gateway
- `shine_defence_runtime`
- anonymous clients
- authenticated clients

The service role also has no direct INSERT privilege on the proposal ledger.

## Ownership

Foundation's service registry identifies:

- service: `foundation.gateway`
- owner component: `shine-core`
- service kind: `supabase-edge-function`

Layer 56 verifies that ownership before creating a proposal.

The runtime-health investigation therefore routes to the Gateway's actual owner rather than Defence.

## Investigation packet

Each proposal captures:

- readiness incident event ID;
- semantic condition fingerprint;
- severity;
- Gateway runtime version;
- exact service-health evidence;
- current health policy;
- deployment truth;
- proposal SHA-256.

Requested investigation work includes:

- inspect health-probe latency distribution;
- inspect Foundation Gateway runtime logs;
- compare the health endpoint execution path;
- inspect recent runtime/platform changes;
- collect a fresh health window;
- return investigation evidence.

## Explicitly prohibited work

A Layer-56 proposal explicitly prohibits:

- relaxing health thresholds to clear readiness;
- mutating/deleting health evidence;
- restarting the runtime without separate admission;
- redeploying the runtime without separate admission;
- rebinding the Foundation release;
- bypassing safe mode;
- automatic unapproved repair.

The proposal is investigation authority only.

It carries:

- `readinessChanged: false`
- `incidentClosurePerformed: false`
- `approvalGranted: false`
- `executionAuthorityGranted: false`
- `executesRemediation: false`

## Production proposal

A real production proposal was generated for the active incident.

Proposal ID:

`019c701d-28b3-4b6f-a994-830a621ed30f`

Owner:

`shine-core`

Service:

`foundation.gateway`

Incident:

`3224107d-b1cd-4c99-aa4f-db47093f07ed`

Condition fingerprint:

`1839a5cade89989319a5edc391abc2e3`

Proposal SHA-256:

`1074398e198a62e5d364bd3778bc15bc326322d7af70df47d6b0c5ac6bdb8ee5`

The proposal status is:

- state: **current**
- usable: **true**
- integrity verified: **true**

The evidence captured at proposal generation was:

`health-probe-window:foundation.gateway:production:90:1538`

with:

- runtime: **v90**
- p95 latency: **10037.982 ms**
- average latency: **5996.086 ms**
- requests: **12**
- 5xx responses: **0**
- runtime errors: **0**
- critical p95 policy threshold: **10000 ms**

## Current production truth

A fresher verification window after proposal generation is:

`health-probe-window:foundation.gateway:production:90:1544`

Current measurements:

- runtime: **v90**
- health state: **unhealthy**
- reason: `critical-p95-latency`
- p95 latency: **10081.109 ms**
- average latency: **6006.149 ms**
- requests: **12**
- 5xx responses: **0**
- runtime errors: **0**
- critical p95 threshold: **10000 ms**

Foundation remains:

- readiness: **not-ready**
- safe mode: **blocked**
- privileged operations: **blocked**
- worker operations: **blocked**
- reason: `runtime-unhealthy`

Dependency state remains:

- impact: **operational**
- affected scopes: **0**

Layer 56 does not soften or hide this failure.

## CI history

The first Layer-56 CI run:

`36528554826`

failed only in the new test's integrity re-hash.

The implementation itself applied successfully.

The test had attempted to call `extensions.digest(...)` while running as `service_role`, and PostgreSQL correctly rejected that with:

`permission denied for schema extensions`

No privilege was expanded to make the test pass.

Instead, the integrity re-hash was moved outside the service-role impersonation block, preserving least privilege.

Corrected functional CI:

`36528756221`

passed end-to-end.

After production advisor review, the new proposal table's `service_id` foreign key was given a covering index.

Final hardened functional CI:

`36529097844`

passed end-to-end, including:

- cause-aware routing tests;
- runtime-health investigation proposal tests;
- proposal integrity/replay tests;
- downstream Shine Defence acceptance tests.

## Production dry run

A fully rolled-back production-schema dry run of the corrected Layer-56 SQL and tests succeeded before promotion.

## Advisors

Post-deployment security advisors show no Layer-56-specific security finding.

The first performance advisor pass identified one Layer-56-specific INFO:

- unindexed `service_id` foreign key on the runtime-health proposal ledger.

Layer 56 added:

`readiness_runtime_health_proposals_service_idx`

covering:

`(service_id, environment, created_at desc)`

The unindexed-FK advisor finding is now gone.

The new index appears only as expected unused-index INFO because the production proposal ledger currently contains one row.

Remaining advisor notices are pre-existing project-wide items.

## Release identity

Layer 56 attempted the normal immutable release bind.

The binder correctly rejected it with:

`release-identity-readiness-not-bindable`

because production readiness remains `not-ready`.

No forced bind, bypass or direct release-ledger mutation was used.

The canonical bound release remains:

`foundation:layer-49:1a8148a8`

Gateway remains:

**v90**

## Invariant

> Foundation routes remediation by the cause it actually observes. A runtime-health incident may create an investigation proposal, but investigation cannot silently become threshold relaxation, restart, redeploy, release rebinding or recovery.
