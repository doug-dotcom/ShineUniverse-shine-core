# Foundation Layer 25 — Dependency-aware admission control

**Status:** LIVE  
**Scope:** operation-scoped dependency admission enforced inside the Foundation Gateway

Layer 24 made dependency impact understandable.

Layer 25 turns that understanding into runtime enforcement.

The Foundation Gateway now checks the dependency graph **before protected execution** and fails unsafe scopes closed without unnecessarily disabling unrelated Foundation surfaces.

## Production admission binding

The first production binding is:

- service: `foundation.gateway`;
- environment: `production`;
- operation: `access.evaluate`;
- impact scope: `protected-operations`.

That binding is append-only and versioned in `foundation.service_admission_bindings`.

## Gateway enforcement order

The access path is now:

1. validate the gateway envelope;
2. verify the calling app;
3. verify canonical Shine identity;
4. verify the app manifest actually declares the requested scope;
5. evaluate dependency admission;
6. only if admitted, read Vault resource metadata and grants;
7. evaluate request-specific Shine Defence policy;
8. evaluate the final access decision;
9. write one canonical access audit event;
10. respond.

Manifest validation intentionally remains before dependency admission so malformed/undeclared requests keep their precise denial reason instead of being masked by infrastructure state.

Admission remains **before Vault, grant and request-level Defence work**, so guarded requests do not touch protected resource/grant paths.

## Admission states

`foundation.evaluate_service_admission_v1` returns:

- **admit** — normal protected execution may continue;
- **admit-degraded** — execution may continue, but the dependency condition is recorded;
- **deny** — the relevant dependency scope is guarded or blocked and must fail closed;
- **unavailable** — Foundation cannot safely evaluate the admission model.

Reason codes include:

- `dependency-admission-clear`;
- `dependency-degraded`;
- `dependency-guarded`;
- `dependency-blocked`;
- `service-state-unavailable`;
- `admission-binding-missing`;
- `admission-binding-disabled`;
- `dependency-graph-invalid`.

## Current Defence behaviour

The Layer 24 production edge remains:

```
foundation.gateway
    └── guard → foundation.defence
        scope: protected-operations
        failure: fail-closed
```

Layer 25 enforces that graph:

- Defence **pass** → `access.evaluate` admitted;
- Defence **warning** → admitted degraded;
- Defence **fail/stale/unknown** → protected access denied before Vault/grant reads;
- a failed hard dependency for the protected scope → denied blocked;
- invalid dependency graph or missing admission binding → request becomes unavailable rather than guessing.

Unrelated public Gateway routes such as health and capability discovery are not sent through this protected admission binding.

## One audit trail

Layer 25 deliberately does **not** create a second decision ledger.

The dependency admission result is attached to:

`foundation.access_audit_events.request_context.dependencyAdmission`

The audit context records:

- admission state;
- reason code;
- service/environment/operation;
- impact scope;
- own/effective service state;
- safe mode;
- binding evidence;
- relevant dependency evidence.

Guard/block denials are therefore normal audited Foundation access decisions.

Degraded admissions are also preserved in the final allow/deny audit event, so operators can later explain that an access request was served while a dependency was degraded.

## Runtime adapter

The Edge runtime uses:

`foundation.evaluate_service_admission_v1(text,text,text,timestamptz)`

through the existing Foundation database role.

The evaluator reads the Layer 24 graph/state providers rather than introducing a parallel health model.

## Acceptance

Layer 25 is complete when:

- clean dependency state admits;
- warning guard state admits degraded;
- failed guard denies;
- failed hard dependency denies blocked;
- missing admission binding fails safe;
- guard denial happens before Vault, grant and request-Defence calls;
- degraded admission continues to normal final authorization;
- admission result is written into the canonical access audit context;
- admission bindings are append-only;
- public roles cannot read bindings or execute the evaluator;
- Foundation Gateway can execute the evaluator;
- the live Edge bundle deploys without dropping newer Gateway features;
- production protected access remains admitted while current Defence posture is pass.

## Machine-readable contract

`foundation/contracts/dependency-admission-v1.json`

Layer 25 closes the loop:

**observe → understand → enforce**.
