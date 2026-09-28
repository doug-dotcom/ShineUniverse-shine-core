# Foundation Layer 24 — Service dependency & health roll-up

**Status:** LIVE  
**Scope:** service dependency graph + safe failure modes + blast radius + Foundation roll-up

Layer 23 made Foundation watch its own Gateway automatically.

Layer 24 teaches Foundation what a service depends on and, crucially, **what is still safe to keep running when a dependency is impaired**.

A dependency failure is no longer treated as a binary “everything is down” event.

## Dependency types

Layer 24 models four dependency classes:

- **hard** — the dependent cannot safely perform the declared scope; failure blocks it;
- **guard** — the dependency protects a scope; failure or uncertainty fails that scope closed while unrelated work can continue;
- **soft** — the dependent continues in a degraded mode;
- **optional** — dependency state is visible but does not change the dependent state.

Each dependency records:

- dependent service;
- dependency service;
- environment;
- version;
- dependency type;
- impact scope;
- failure mode;
- description and evidence.

The dependency graph is append-only and versioned.

## Explicit state sources

Not every Foundation component has the same kind of health evidence.

Layer 24 therefore adds `foundation.service_state_sources`.

The initial providers are:

- `standard-health` — Layer 21 deployment truth + Layer 22/23 service health;
- `defence-posture` — Shine Defence’s dated operational posture.

This prevents Foundation from inventing HTTP “health” for an internal control such as Defence merely to make the data model look uniform.

## Production graph

The first production dependency is:

```
foundation.gateway
    └── guard → foundation.defence
        scope: protected-operations
        failure: fail-closed
```

This records the Foundation v1 access-decision invariant: protected operations depend on Shine Defence policy gates.

The meaning is precise:

- Defence **pass** → Gateway remains operational;
- Defence **warning** → protected operations are degraded;
- Defence **fail** → protected operations are guarded/fail-closed;
- Defence **missing or stale** → protected operations are guarded/fail-closed;
- unrelated public or standalone surfaces do not have to stop merely because the guard is unavailable.

## New control-plane objects

Layer 24 adds:

- `foundation.service_state_sources`;
- `foundation.service_dependencies`;
- `foundation.current_service_state_source`;
- `foundation.current_service_dependencies`;
- `foundation.get_service_native_state_v1`;
- `foundation.get_service_dependency_rollup_v1`;
- `foundation.get_service_blast_radius_v1`;
- `foundation.get_dependency_graph_health_v1`;
- `foundation.get_foundation_dependency_rollup_v1`.

It also registers `foundation.defence` as an internal service node whose state comes from the existing Defence posture rather than a fabricated health probe.

## Effective service states

Dependency-aware roll-up returns:

- **operational** — own state and relevant dependencies are healthy;
- **degraded** — service can continue but one or more declared scopes are impaired;
- **guarded** — guarded scopes must fail closed, while unrelated scopes may continue;
- **blocked** — a hard dependency or the service itself makes operation unsafe;
- **unknown** — Foundation lacks enough trustworthy state to decide.

The response includes explicit:

- blocked scopes;
- guarded scopes;
- degraded scopes;
- direct dependency states;
- dependency types and failure modes.

## Blast radius

`get_service_blast_radius_v1` walks the dependency graph in reverse.

For a hypothetical dependency failure it reports:

- direct and transitive affected services;
- dependency path;
- graph depth;
- dependency types along the path;
- potential impact: blocked, guarded or degraded.

The traversal is cycle-safe and bounded.

This means Foundation can answer questions such as:

> “If Defence fails, what actually stops?”

without falsely saying the entire Universe is down.

## Graph integrity

`get_dependency_graph_health_v1` checks the active graph for dependency cycles.

A cyclic graph is reported as **fail**, including the cycle paths. Foundation-wide dependency roll-up returns unknown rather than pretending a cyclic dependency model is trustworthy.

## Production behaviour

At closure:

- Foundation Gateway is healthy and deployment-aligned;
- Shine Defence production posture is current and **pass**;
- the production dependency graph is acyclic;
- Gateway’s dependency-aware state is **operational**;
- the protected-operations guard is explicitly present but has no active impact while Defence passes.

## Acceptance coverage

The rollback acceptance suite proves:

- passing Defence → Gateway operational;
- warning Defence → protected scope degraded;
- failed Defence → protected scope guarded/fail-closed;
- failed hard dependency → dependent blocked;
- transitive soft dependent → degraded blast-radius result;
- dependency cycles are detected;
- dependency and state-source ledgers are append-only;
- public roles cannot read the graph or execute dependency readers;
- Foundation runtime retains read-only dependency intelligence.

No synthetic production health was created for Shine ID or Vault simply because those concepts exist. Future services should enter the graph only when Foundation has a trustworthy state source for them.

## Machine-readable contract

`foundation/contracts/service-dependency-rollup-v1.json`

Layer 24 is where Foundation stops asking only **“is this service healthy?”** and starts answering **“what does its health mean for everything that depends on it?”**
