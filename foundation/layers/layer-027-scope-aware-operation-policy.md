# Foundation Layer 27 — Scope-aware Gateway operation policy

**Status:** LIVE  
**Scope:** privileged operation policy coverage + multi-scope dependency admission + least-privilege runtime broker + exact source-bound deployment

Layer 26 established the full 39-route Gateway inventory.

Layer 27 gives every privileged route an explicit operation policy.

## Coverage

The production Gateway currently has:

- 39 registered routes;
- 23 privileged non-read operations;
- 21 dependency-admission policies;
- 2 worker-only policies;
- 0 missing privileged-operation policies;
- 0 missing admission bindings;
- 0 missing dependency scopes.

The two worker-only operations are:

- `concierge.retry.claim`;
- `concierge.retry.finish`.

They remain explicit internal client-authenticated worker controls rather than user/app admission operations.

Every other privileged write, credential or execution operation now has a scope-aware dependency-admission policy in front of its existing atomic/service guard.

## Six admission scopes

Gateway → Shine Defence dependency edges can now coexist by impact scope.

The active policy scopes are:

1. `protected-operations`
2. `permission-operations`
3. `credential-operations`
4. `identity-operations`
5. `context-operations`
6. `control-operations`

The Layer-24 current dependency view previously selected one edge per service pair/environment, which meant multiple scopes for the same dependency pair could logically overwrite one another.

Layer 27 changes the current-view identity to:

`dependent service + dependency service + environment + impact scope`

so all six Defence guard scopes coexist.

## Existing execution guards remain

Admission is an additional front-door layer, not a replacement for atomic invariants.

Examples:

- `grant.consent` → dependency admission, then `foundation.issue_access_grant_v1`;
- `grant.revoke` → dependency admission, then `foundation.revoke_access_grant_v1`;
- `integration.delegation.refresh` → dependency admission, then refresh-rotation control;
- `concierge.execute` → dependency admission, then `foundation.gate_concierge_execution_v1`;
- `capability.ticket.redeem` → dependency admission, then one-time ticket consumption;
- `access.evaluate` → dependency admission, then Gateway permission engine + request-level Defence evaluation.

This provides layered enforcement rather than replacing one guard with another.

## Operation policy broker

Layer 27 adds:

- `foundation.gateway_operation_policies`;
- `foundation.current_gateway_operation_policies`;
- `foundation.evaluate_gateway_operation_policy_v1`;
- `foundation.get_gateway_operation_policy_coverage_v1`.

The broker returns:

- `admit`;
- `admit-degraded`;
- `deny`;
- `unavailable`;
- or `worker-only`.

Missing privileged-operation policy is a coverage failure.

## Real runtime-role gap discovered

Layer 27 explicitly tested admission as the actual Edge database role:

`SET ROLE foundation_gateway`

That uncovered a Layer-25 runtime gap.

Although `foundation_gateway` had EXECUTE permission on the admission function, the underlying security-invoker traversal reached `foundation.current_defence_posture`, where RLS/view permissions caused:

`permission denied for view current_defence_posture`

Service-role tests had not exposed that failure.

Layer 27 fixes the runtime path with a narrowly scoped `SECURITY DEFINER` operation-policy broker using a fixed search path. The Gateway now asks for an operation decision rather than requiring new direct Defence-posture privileges.

The existing role hierarchy remains unchanged: `foundation_gateway` is a member of `foundation_runtime` and therefore inherits the runtime read plane. Layer 27 does **not** claim otherwise; the broker's privilege improvement is specifically that no new raw Defence-table grant was required to evaluate policy.

The broker was successfully executed under the real `foundation_gateway` role for both protected-access and Concierge operations.

## Policy behaviour verified

Rollback acceptance tests proved:

- Defence pass → privileged operations admit;
- Defence warning → matching scopes admit degraded;
- Defence fail → matching scopes deny/fail closed;
- permission, credential, identity, context and control scopes resolve independently;
- Concierge retry worker policy remains worker-only regardless of Defence posture;
- missing privileged-operation policy fails coverage;
- policy history is append-only;
- public roles cannot execute the broker.

## Exact-source deployment

During the v75 rollout, Foundation's newly installed source-binding trigger correctly rejected a required-core deployment expectation without a GitHub commit source reference.

The candidate runtime commit was then checked against the deployed v75 bundle. It was not exact: 26/27 files matched, but the deployed `index.ts` still used the earlier live composition while the canonical repository contained the newer typed composition.

Rather than binding a false source reference, Layer 27 froze the canonical Gateway tree at:

`989f5284333999742d7c7404c1d07347e33859b5`

All 27 Edge bundle paths were checked against that commit. Before the final deployment:

- 26/27 v75 files already matched;
- the only mismatch was `foundation/runtime/edge-function/index.ts`.

Gateway **v76** was deployed by replacing that last file with the exact frozen-commit version.

The resulting production expectation is now source-bound to:

`github://doug-dotcom/ShineUniverse-shine-core/commit/989f5284333999742d7c7404c1d07347e33859b5`

Production deployment truth is **aligned** to:

- runtime version: 76;
- artefact SHA-256: `2e5dcdbdd02ef3edf4d558b3ba56a074c29a73e211025bb4178f39a258d9737e`;
- exact source commit: `989f5284333999742d7c7404c1d07347e33859b5`.

## v76 production proof

v76 earned a fresh current-deployment health window:

- probes: 3;
- 4xx: 0;
- 5xx: 0;
- runtime/probe errors: 0;
- average round-trip: ~6.8 ms;
- p95 round-trip: ~6.8 ms;
- health: **healthy**.

Normal scheduled Gateway traffic also continued after deployment:

- `/v1/concierge/retry/claim` returned HTTP 200 on v76;
- no v76 function error events were observed during closure verification.

Current Defence posture is `pass` and current privileged policies resolve `admit`.

## Advisors

No Layer-27-specific Supabase security finding was reported.

No Layer-27 missing-FK or other structural performance finding was reported. The performance advisor still reports an INFO-level unused index on `service_dependencies_dependent_idx`, which predates Layer 27 and is not a correctness failure.

## Machine-readable contract

`foundation/contracts/gateway-operation-policy-v1.json`

## Closure

Layer 27 changes Foundation from:

> “this route has a named guard”

to:

> “every privileged operation has a declared policy scope, a dependency-admission decision, and its original execution guard — and the production Gateway can actually evaluate that policy under its real runtime role.”

It also makes required-core deployment provenance concrete rather than approximate.
