# Foundation Layer 57 — Shine-core runtime-health owner workflow

**Status:** LIVE — owner acknowledged and canonical release bound

Layer 57 delivers the Layer-56 runtime-health investigation proposal to the actual Shine-core control-plane owner and records one immutable acknowledgement without granting runtime mutation authority.

Layer 56 established that the active readiness problem is Gateway own-health, not dependency health, and generated a real production runtime-health investigation proposal owned by `shine-core`.

Layer 57 closes the next operational seam:

`proposal → verified owner inbox → explicit owner acknowledgement`

## Why a dedicated owner capability was required

The first Layer-57 design attempted to use `foundation_runtime` as the owner acknowledgement principal.

CI correctly rejected that design.

Foundation's runtime hierarchy intentionally contains:

`foundation_gateway → foundation_runtime`

The Gateway execution role therefore inherits `foundation_runtime` privileges.

Granting owner acknowledgement to `foundation_runtime` would have allowed the unhealthy Gateway execution surface to acknowledge its own investigation.

That violates the separation Layer 57 is intended to create.

## Isolated Shine-core control-plane role

Layer 57 therefore introduces:

`shine_core_control_plane`

The role is:

- NOLOGIN
- NOINHERIT
- NOSUPERUSER
- NOCREATEDB
- NOCREATEROLE
- NOBYPASSRLS

Existing role posture is verified on subsequent applies. The migration fails closed if the role ever acquires broader posture.

The role is explicitly grantable to the trusted PostgreSQL control plane so an administrator must deliberately use:

`SET ROLE shine_core_control_plane`

before exercising owner acknowledgement.

The Gateway is not a member of this role.

This follows the same capability-role pattern already used by Foundation remediation approver, executor, mutator and verifier roles.

## Raw ledger access tightened

Layer 57 revokes direct Layer-56 proposal-ledger SELECT from `foundation_runtime`.

The owner capability also receives no direct SELECT on:

- `foundation.readiness_runtime_health_investigation_proposals`
- `foundation.readiness_runtime_health_investigation_responses`

and no direct INSERT on the response ledger.

The owner uses bounded SECURITY DEFINER APIs only.

## Owner inbox

Function:

`foundation.get_readiness_runtime_health_owner_inbox_v1(environment, limit)`

Reader:

`shine_core_control_plane`

The inbox exposes only proposals that are:

- for `foundation.gateway`;
- owned by `shine-core`;
- current;
- integrity verified;
- still awaiting an owner response.

The default limit is 25 and the accepted range is 1–100.

Each inbox item carries the proposal's health evidence and explicit authority boundaries.

## Owner acknowledgement

Function:

`foundation.respond_readiness_runtime_health_investigation_v1(...)`

Allowed response states:

- `accepted`
- `rejected`
- `clarification-requested`

Only `shine_core_control_plane` may execute the response function.

The following cannot acknowledge the investigation:

- `foundation_runtime`
- `foundation_gateway`
- `service_role`
- `shine_defence_runtime`
- anonymous clients
- authenticated clients

Only one authoritative response is accepted per proposal.

Replay returns the original response rather than replacing it.

## Acceptance means investigation ownership only

An accepted response records:

- `acknowledgesInvestigationOwnership: true`
- `investigationAuthorityOnly: true`

It simultaneously records:

- `runtimeMutationAuthorityGranted: false`
- `healthPolicyMutationAuthorityGranted: false`
- `releaseRebindAuthorityGranted: false`
- `safeModeBypassAuthorityGranted: false`
- `readinessChanged: false`
- `incidentClosurePerformed: false`
- `approvalGranted: false`
- `executionAuthorityGranted: false`
- `executesRemediation: false`

Acknowledgement cannot restart, redeploy, change health policy, clear safe mode, close the incident or alter readiness.

## Immutable response ledger

Append-only ledger:

`foundation.readiness_runtime_health_investigation_responses`

Each response binds:

- proposal ID;
- readiness incident event ID;
- environment;
- service ID;
- owner component;
- response state;
- reason code;
- response note;
- proposal SHA-256;
- semantic condition fingerprint;
- immutable response JSON;
- response SHA-256;
- response timestamp.

Status is exposed through:

`foundation.get_readiness_runtime_health_investigation_response_status_v1(...)`

If the underlying proposal later becomes stale, the response remains immutable history but its current status becomes `stale`.

## CI boundary discoveries

### First CI failure — inherited Gateway authority

Run:

`36530032576`

The test proved that `foundation_gateway` could execute the acknowledgement function when it was granted to `foundation_runtime`.

That happened because Gateway intentionally inherits the broader runtime role.

No privilege was loosened.

Layer 57 introduced the isolated `shine_core_control_plane` capability instead.

### Second CI failure — test attempted raw-ledger read

Run:

`36530313706`

After capability isolation, the stale-history test attempted to SELECT the response ledger while impersonating `shine_core_control_plane`.

PostgreSQL correctly denied the read.

Again, no table privilege was granted to make the test pass.

The test was corrected to identify its fixture under the administrative harness and perform stale verification only through the bounded status API.

### Corrected CI

Run:

`36530449639`

passed the complete Foundation + downstream Defence chain.

### Explicit control-plane binding hardening

The final role model was aligned with the established Foundation privileged-capability pattern:

- `shine_core_control_plane` remains NOLOGIN + NOINHERIT;
- PostgreSQL control plane receives explicit membership;
- use requires deliberate `SET ROLE`;
- Gateway receives no membership.

Final functional run:

`36530900447`

passed end-to-end.

## Production role proof

Production verifies:

- PostgreSQL control plane can explicitly SET the owner role: **yes**
- PostgreSQL is an explicit owner-role member: **yes**
- Gateway is an owner-role member: **no**
- `foundation_runtime` is an owner-role member: **no**
- owner can read bounded inbox: **yes**
- owner can acknowledge: **yes**
- Gateway can acknowledge: **no**
- `foundation_runtime` can acknowledge: **no**
- service role can acknowledge: **no**
- Defence can acknowledge: **no**
- owner direct proposal SELECT: **no**
- owner direct response SELECT: **no**
- owner direct response INSERT: **no**

A production transaction also proved that the PostgreSQL control plane can deliberately SET ROLE into `shine_core_control_plane` and see exactly one pending, current, integrity-verified owner item.

## Production acknowledgement

The real Layer-56 proposal was then accepted through the isolated owner role itself.

Proposal:

`019c701d-28b3-4b6f-a994-830a621ed30f`

Response:

`e68085b2-7a0d-4773-8423-7164895578ce`

Response state:

`accepted`

Reason:

`accepted-for-runtime-health-investigation`

Response SHA-256:

`2c10eabbfa181b396ce830976689d38229b12a11c0236763b44ca3cf34c1a901`

The response is integrity verified.

After acknowledgement:

- pending inbox count: **0**
- proposal remains current;
- investigation ownership is acknowledged;
- runtime mutation authority remains false;
- health-policy mutation authority remains false;
- release-rebind authority from the acknowledgement remains false;
- safe-mode bypass authority remains false;
- remediation execution authority remains false.

## Runtime health improved independently

While Layer 57 was being completed, fresh health-probe evidence improved.

The important separation is:

> owner acknowledgement did not improve readiness; fresh runtime evidence did.

Latest verification window:

`health-probe-window:foundation.gateway:production:90:1574`

Measurements:

- runtime: **v90**
- request count: **12**
- average latency: **3108.247 ms**
- p95 latency: **8332.800 ms**
- HTTP 5xx: **0**
- runtime errors: **0**

Policy:

- warning p95: **5000 ms**
- critical p95: **10000 ms**

Gateway therefore moved from:

`unhealthy / critical-p95-latency`

to:

`degraded / elevated-p95-latency`

Foundation readiness correspondingly moved from:

`not-ready / blocked`

to:

`degraded`

with:

- safe mode: **degraded**
- privileged operations: **degraded**
- worker operations: **degraded**
- dependency impact: **operational**
- dependency affected scopes: **0**

This is improvement, not full recovery.

## Release identity recovery

Because current readiness is now legitimately `degraded`, which the immutable release binder permits, Layer 57 retried the normal release-binding path.

The binder accepted it without bypass.

New canonical binding:

`foundation:layer-57:1a8148a8`

Binding ID:

`36bac900-0a2e-4af0-9f62-bf38c31ca137`

Bound readiness:

`degraded`

Bound readiness fingerprint:

`fc3a81c0bb3aacae8959e1238bc646b4`

Gateway remains:

**v90**

Deployment source remains:

`github://doug-dotcom/ShineUniverse-shine-core/commit/1a8148a8eb748a19ac03107d9e9ec7313297384b`

Artifact SHA-256 remains:

`3294e28293df667224ed9ab2551e2e5a6a88bab6f6805791bec14e7d22512692`

Publication assurance remains:

`github-oidc`

Release identity health reports:

- current deployment matches binding: **true**
- current publication matches binding: **true**
- readiness changed since binding: **false**
- release identity health: **pass**

The release advanced because the normal readiness gate became bindable again, not because Layer 57 weakened it.

## Advisors

Post-deployment security advisors show no Layer-57-specific security finding.

The existing project-wide notices remain:

- internal RLS-enabled tables with no policy;
- `pg_net` installed in the public schema.

Performance advisors show no Layer-57 unindexed foreign key finding.

The two new response-ledger indexes appear as expected unused-index INFO because production currently contains one response row.

## Invariant

> The unhealthy execution surface cannot acknowledge its own investigation. Shine-core ownership is accepted only through an isolated control-plane capability, and acceptance grants investigation responsibility — never repair authority.
