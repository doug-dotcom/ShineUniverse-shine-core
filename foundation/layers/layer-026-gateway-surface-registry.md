# Foundation Layer 26 — Gateway surface registry & drift detection

**Status:** LIVE  
**Scope:** canonical Gateway route inventory + control classification + repo/runtime drift prevention

Layer 25 made dependency admission enforceable.

Layer 26 makes the entire Gateway surface **knowable**.

Foundation now has a canonical registry for every live HTTP route, including what it does, how it authenticates, what kind of effect it has, and which control protects it. CI compares that contract to the Gateway handler so route additions/removals cannot be silent.

## Production inventory

At closure, Foundation Gateway exposes **39 route contracts**.

Control modes:

- **4 public-exempt** — intentionally public, read-only metadata/health;
- **12 auth-only** — authenticated, read-only surfaces;
- **20 service-guard** — mutating/executing operations protected by named atomic/service controls;
- **2 internal-worker** — authenticated worker control routes;
- **1 dependency-admission** — `access.evaluate`, enforced by Layer 25.

The registry records, per route:

- route symbol;
- HTTP method;
- path template;
- operation key;
- risk class;
- effect class;
- authentication class;
- control mode;
- concrete control reference;
- public exemption reason where applicable.

## Canonical contract

`foundation/contracts/gateway-operation-registry-v1.json`

Its invariants require:

- every declared route is registered;
- every registered route exists in the handler;
- method/path pairs are unique;
- public exemptions are read-only;
- auth-only controls are read-only;
- mutating/executing routes name a concrete control;
- protected execution is never public.

## CI drift verifier

`foundation/integration-kit/verify-gateway-operation-registry-v1.mjs`

The verifier parses `foundation/gateway/http-handler-v1.mjs` and compares the handler route symbols, paths and HTTP methods to the registry.

CI now fails when:

- code introduces a route that the registry does not know;
- the registry contains a stale route;
- a route's method/path changes without updating the contract;
- a public exemption becomes mutating;
- a mutating route loses its named guard.

## Control-plane persistence

Layer 26 adds:

- `foundation.gateway_operation_contracts`;
- `foundation.current_gateway_operation_contracts`;
- `foundation.get_gateway_operation_inventory_v1(text)`;
- `foundation.get_gateway_operation_registry_health_v1(text)`.

The contract ledger is append-only.

The health reader checks:

- route count;
- duplicate method/path pairs;
- invalid control semantics;
- missing admission bindings for routes classified as `dependency-admission`;
- control-mode distribution.

A synthetic dependency-admission route without a binding correctly returns **FAIL**.

## Drift found during the build

Layer 26 found a material truth gap while it was being built.

The live v74 Gateway handler exposed **39** routes, while the canonical repository handler exposed only **12**.

The repository Edge composition was also behind the live v74 composition.

This was not treated as an acceptable historical difference. The canonical repository was reconciled to the live v74 source:

- `foundation/gateway/http-handler-v1.mjs` now matches the live v74 handler;
- `foundation/runtime/edge-function/index.ts` now matches the live v74 Edge composition.

After reconciliation:

- live route declarations: **39**;
- repo route declarations: **39**;
- registry routes: **39**;
- method/path mismatches: **0**.

No production Edge deployment was required for this reconciliation because v74 was already the authoritative running bundle; the repository was brought forward to match runtime truth.

## Production verification

At closure:

- operation registry health: **PASS**;
- routes: **39**;
- duplicate method/path pairs: **0**;
- invalid contracts: **0**;
- missing dependency-admission bindings: **0**;
- Gateway deployment truth: **aligned** to v74;
- Gateway health: **healthy**;
- protected access admission: **admit / dependency-admission-clear**.

Supabase security and performance advisors reported no Layer-26-specific finding.

## Why this matters

The v73 incident demonstrated that a repository can silently fall behind the composed production Gateway.

Layer 26 converts that lesson into a permanent invariant:

> Foundation must know every route that exists and the control that protects it, and code/registry drift must fail CI.

This strengthens the original Foundation promise: **know what exists, what it can do, who may reach it, and what protects it.**
