# Foundation Layer 28 — Universal privileged admission enforcement

**Status:** LIVE  
**Scope:** HTTP front-door policy enforcement for all privileged Gateway POST operations

Layer 27 created complete scope-aware operation policy coverage.

Layer 28 makes that policy coverage unavoidable in the actual Gateway request path.

## Enforcement gap found

Layer 28 began as an audit-truth pass and immediately found a more important correctness gap.

The Layer 27 policy model was live:

- 23 privileged operations had policy records;
- 21 used dependency admission;
- 2 were worker-only;
- six Shine Defence dependency scopes existed.

However, inspection of the live v76 Gateway showed that only `access.evaluate` called the policy adapter in runtime code. The other privileged routes still went directly from route-specific authentication/validation to their existing atomic/service guard.

The policies were real, but the HTTP front door was not universally invoking them.

Layer 28 fixes that before adding another audit layer on top.

## Universal route-policy broker

Layer 28 adds:

`foundation.evaluate_gateway_route_policy_v1(text,text,text,timestamptz)`

The broker:

1. resolves the HTTP method/path against the Layer 26 route registry;
2. resolves that route to its canonical operation key;
3. invokes the Layer 27 operation policy broker;
4. returns the route identity plus the policy state and reason.

Supported runtime states are:

- **admit** — continue;
- **admit-degraded** — continue under degraded dependency semantics;
- **worker-only** — continue to the existing worker authentication path;
- **deny** — fail closed with HTTP 403;
- **unavailable** — fail closed with HTTP 503;
- **not-registered** — continue to normal handler routing, preserving the ordinary 404 for an unknown POST path.

## HTTP front-door enforcement

The Gateway HTTP handler now accepts:

- `evaluateOperationPolicy`;
- `operationPolicyRequired`.

The production Edge composition sets:

`operationPolicyRequired: true`

and wires:

`evaluateOperationPolicy: adapters.evaluateGatewayRoutePolicy`

If the required production broker is absent, the Gateway constructor fails rather than silently running unguarded.

Every POST request now passes the route-policy broker before route-specific service execution.

This ordering is intentionally infrastructure-first:

1. route-to-operation policy;
2. route-specific authentication and input validation;
3. existing atomic/service guard;
4. domain outcome/audit.

Layer 28 does **not** remove any existing guard. Grant consent still reaches `foundation.issue_access_grant_v1`; delegation refresh still reaches the rotation guard; Concierge execution still reaches its execution gate; one-time ticket redemption still reaches ticket consumption.

## Worker routes remain separate

The two internal retry routes remain explicit worker controls:

- `concierge.retry.claim`;
- `concierge.retry.finish`.

Their policy state is `worker-only`, which allows the request to continue to the existing integration-client authentication. A Defence dependency denial aimed at user/app operations does not silently turn an internal worker policy into a user admission policy.

## Unknown routes remain normal routes

The front-door broker distinguishes an unknown POST path from a broken policy.

An unregistered path returns `not-registered` from the broker and then falls through to the HTTP handler's normal routing logic.

Production proof:

`POST /v1/not-a-real-route → HTTP 404`

This avoids converting ordinary routing mistakes into misleading infrastructure failures.

## Real privileged-route proof

A production request was issued to:

`POST /v1/grants/consent`

without user/app credentials.

v77 returned:

`HTTP 401 unauthenticated`

This proves the new front-door policy broker admitted the currently healthy permission-operation scope and the request then reached its existing route authentication boundary.

If the front-door broker had been unavailable, the same request would have stopped at HTTP 503 before authentication.

Rollback database tests separately prove a failed Defence posture produces:

- policy state: `deny`;
- reason: `dependency-guarded`.

HTTP unit tests prove that deny returns 403 before authentication/service execution and unavailable returns 503 before service execution.

## Exact-source deployment

Layer 28 did not deploy from an approximate main-branch state.

A dedicated exact runtime tree was created from the proven v76 source commit:

`989f5284333999742d7c7404c1d07347e33859b5`

Only three Edge bundle files were changed:

- `foundation/gateway/http-handler-v1.mjs`;
- `foundation/runtime/supabase-runtime-adapters-v1.mjs`;
- `foundation/runtime/edge-function/index.ts`.

The exact v77 source commit is:

`f4421209d45d64ce4d2778bce73e4703a7c871ca`

Production deployment truth is aligned to:

- Gateway runtime version: **77**;
- artefact SHA-256: `1d81b65a21c9e8c4576df40f6153a7a572e7c58d09eb3a02c4038b59e7b36de0`;
- source reference: `github://doug-dotcom/ShineUniverse-shine-core/commit/f4421209d45d64ce4d2778bce73e4703a7c871ca`.

## v77 production proof

v77 earned a fresh deployment-bounded health window:

- probes: **3**;
- 4xx: **0**;
- 5xx: **0**;
- runtime/probe errors: **0**;
- average probe round-trip: ~16.2 ms;
- p95 probe round-trip: ~16.2 ms;
- health: **healthy**.

Observed live traffic on v77 includes:

- `/health` → HTTP 200;
- `/v1/concierge/retry/claim` → HTTP 200;
- `/v1/grants/consent` without credentials → HTTP 401 after policy admission;
- unknown POST route → HTTP 404.

No v77 function error events were observed during closure verification.

## Coverage at closure

Operation policy coverage:

- privileged operations: **23**;
- covered operations: **23**;
- dependency-admission policies: **21**;
- worker-only policies: **2**;
- missing policies: **0**;
- missing admission bindings: **0**;
- missing dependency scopes: **0**.

Gateway route registry:

- registered routes: **39**;
- registry state: **PASS**.

Current representative policies:

- `grant.consent` → **admit**;
- `concierge.execute` → **admit**;
- `concierge.retry.claim` → **worker-only**.

## CI and regression protection

CI now runs:

- the Layer 28 database broker acceptance suite;
- a static Gateway policy-wiring verifier.

The wiring verifier requires:

- the runtime adapter to expose `evaluateGatewayRoutePolicy`;
- that adapter to call the hosted route-policy broker;
- the HTTP handler to evaluate the broker;
- the Edge composition to wire the broker;
- `operationPolicyRequired: true` in production;
- the expected 23 privileged-route surface.

## Advisors

No Layer-28-specific Supabase security finding was reported.

No Layer-28-specific structural performance finding was reported. Existing INFO-level unused-index notices remain separate from this layer.

## Machine-readable contracts

- `foundation/contracts/gateway-universal-admission-v1.json`
- `foundation/deployments/layer-028-gateway-source.json`

## Closure

Layer 28 changes Foundation from:

> “every privileged operation has a policy”

to:

> “every privileged POST request must pass that policy at the actual HTTP front door before its existing route guard can execute.”

The next audit layer can now record policy decisions with confidence that the policy is not merely declarative.
