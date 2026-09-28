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

## Production rollout and recovery

Layer 25 was exercised against the live Gateway rather than closed from database-only tests.

The first rollout, Gateway **v73**, exposed a repository/runtime parity defect: the repository copy of `supabase-runtime-adapters-v1.mjs` was behind the already deployed v72 integration/Concierge surface. Replacing the live runtime adapter with that stale repository file caused v73 to fail during service construction with:

`missing integration consent adapter: verifyIntegrationIdentity`

The automatic health collector detected the regression immediately:

- Gateway health returned HTTP 500;
- Concierge retry returned HTTP 500;
- the failed probes were written to immutable health history;
- Gateway health degraded/unhealthy according to the existing policy;
- dependency admission failed safe rather than treating the service as healthy.

The failed v73 evidence was **not removed or rewritten**.

The runtime adapter surface was then reconstructed against the live Gateway service contracts and Foundation database functions. A permanent runtime-surface test now asserts the complete Gateway adapter interface so the repository cannot silently fall behind the deployed service composition again.

Gateway **v74** was deployed from the complete live bundle with the repaired runtime and Layer-25 Gateway core.

Post-recovery verification:

- Gateway health: HTTP 200;
- Concierge retry: HTTP 200;
- v74 runtime error log: no error events observed;
- deployment truth: **aligned** to v74;
- artefact SHA-256: `73b751265954fe05ad02a9830e22027490434aef0d20ab9e6fbc34a1c4564513`.

The health collector was also tightened during recovery. Health windows are now bounded by the **current deployment observation time**. This preserves v73's failed evidence as historical incident data while preventing failures from a superseded runtime from being falsely attributed to v74.

v74 then earned a fresh current-deployment health window:

- probes: 3;
- 4xx: 0;
- 5xx: 0;
- runtime/probe errors: 0;
- average round-trip: approximately 6.9 ms;
- p95 round-trip: approximately 8.3 ms;
- health: **healthy**.

At closure the current Shine Defence posture is `pass`, so the live protected admission result is:

- admission state: **admit**;
- reason: `dependency-admission-clear`;
- Gateway own state: **operational**;
- dependency effective state: **operational**;
- safe mode: **normal**.

Supabase security and performance advisors reported no Layer-25-specific finding.

## Closure invariant

A future Gateway deployment is not allowed to inherit the health verdict of the runtime it replaced, and a Gateway build is not considered safe merely because its Edge Function status is `ACTIVE`.

Layer 25 therefore closes with all three independently true:

1. deployment truth matches the current artefact;
2. the current deployment has earned fresh health evidence;
3. dependency admission is evaluated from current service/dependency state before protected execution.

