# Foundation Layer 30 — Control-plane readiness gate

**Status:** LIVE  
**Scope:** one conservative operational-readiness decision across Foundation registry, deployment, health, dependencies, policy coverage, audit integrity and Defence posture

Layers 21–29 made the individual Foundation control-plane pillars trustworthy.

Layer 30 combines them into one machine-evaluable answer:

> **Is Foundation safe to operate right now, and in what mode?**

The readiness gate does not flatten every condition into a simplistic green/red signal. It distinguishes a healthy core that is deliberately fail-closed from a genuinely broken control plane.

## Readiness states

Layer 30 returns five states.

### READY

All required control-plane evidence is current and passing.

- safe mode: `normal`;
- privileged operations: `normal`;
- workers: `normal`.

### RESTRICTED

Foundation core is healthy and coherent, but a guard dependency requires protected scopes to remain fail-closed.

- safe mode: `guarded`;
- privileged operations: `guarded`;
- workers: `normal`.

This is the expected state when, for example, Shine Defence is unhealthy while the Gateway itself is healthy. Foundation does **not** mislabel that as a total outage.

### DEGRADED

The control plane can continue operating, but non-critical health, dependency or audit evidence requires remediation.

- safe mode: `degraded`;
- privileged operations: `degraded`;
- workers: `degraded`.

### NOT_READY

A hard invariant has failed.

Examples include:

- deployment drift;
- unhealthy required core runtime;
- broken dependency graph;
- hard dependency block;
- invalid Gateway route registry;
- incomplete privileged-operation policy coverage;
- broken operation-audit hash chain.

The recommended mode is blocked until remediated.

### UNKNOWN

Foundation does not have enough current evidence to make a safe readiness claim.

Examples include:

- deployment truth unknown;
- health evidence missing/stale;
- health evidence belongs to a different runtime version;
- dependency state unknown;
- audit state unknown;
- the current runtime has not yet produced its own complete privileged policy/outcome audit trace.

Unknown is intentional. Missing evidence is never converted into ready.

## Control-plane checks

`foundation.evaluate_foundation_readiness_v1(environment, as_of)`

combines:

1. required core service registry;
2. exact deployment truth;
3. deployment-bounded runtime health;
4. health/runtime-version consistency;
5. dependency graph integrity;
6. dependency roll-up and safe failure mode;
7. Gateway route registry;
8. privileged-operation policy coverage;
9. canonical privileged-operation audit health;
10. current-runtime complete audit proof;
11. Shine Defence posture.

The gate uses a strict precedence:

1. hard invariant failure → **NOT_READY**;
2. missing/current-runtime evidence → **UNKNOWN**;
3. fail-closed guard dependency → **RESTRICTED**;
4. non-critical impairment → **DEGRADED**;
5. otherwise → **READY**.

## New-deployment rule

A new Gateway deployment cannot inherit readiness from the runtime it replaced.

Layer 30 requires:

- health evidence whose `runtimeVersion` matches deployment truth;
- at least one complete privileged policy/outcome audit trace recorded by that same runtime.

The acceptance suite proves a fresh deployment with healthy probes but no current-runtime audit trace remains **UNKNOWN**.

This closes an important false-confidence path: “the previous version was healthy” is not evidence that the replacement version is ready.

## Append-only readiness observations

Layer 30 adds:

- `foundation.foundation_readiness_observations`;
- `foundation.current_foundation_readiness_observation`;
- `foundation.evaluate_foundation_readiness_v1`;
- `foundation.record_foundation_readiness_observation_v1`.

Observations are:

- append-only;
- RLS-protected;
- read-only to Foundation runtime;
- writable only through the recorder by the service role.

The observation stores the complete control-plane snapshot plus a compact state fingerprint.

The fingerprint is used only for change detection/deduplication; it is not a security integrity primitive. Layer 29 audit integrity remains SHA-256 hash-linked.

Identical readiness evidence is not appended repeatedly.

## Continuous observer

Production pg_cron job:

`shine-foundation-readiness-5m`

runs every five minutes.

It records a row only when the meaningful evidence fingerprint changes.

Production proof:

- 06:15 UTC cron run → **succeeded**;
- 06:20 UTC cron run → **succeeded**.

The first production history captured meaningful reconciled runtime changes:

- v83 → restricted;
- v84 → restricted;
- v85 → restricted.

The state stayed restricted because Shine Defence remained fail-closed, but each newly reconciled runtime produced distinct deployment-specific evidence.

## Live v85 proof

For closure, Gateway v85 was reconciled against:

`github://doug-dotcom/ShineUniverse-shine-core/commit/b7c5331f93eff28a781f0794c89ccf50e90a4045`

All **27 / 27** deployed Edge bundle files matched that commit byte-for-byte.

Gateway v85 then earned fresh evidence:

- health probes: **3**;
- 4xx: **0**;
- 5xx: **0**;
- runtime/probe errors: **0**;
- p95 health probe: approximately **7.8 ms**;
- health: **HEALTHY**;
- current-runtime complete privileged audit trace: present.

At the same point:

- deployment truth: **aligned**;
- service registry: **pass**;
- dependency graph: **pass**;
- Gateway route registry: **pass**;
- privileged operation policy coverage: **pass**;
- canonical operation audit health: **pass**;
- Shine Defence posture: **unhealthy/fail-closed**.

Layer 30 therefore returned:

- readiness: **RESTRICTED**;
- safe mode: **guarded**;
- privileged operations: **guarded**;
- worker operations: **normal**;
- reason: `dependency-guarded`.

That is the intended distinction between **“the core is broken”** and **“the core is healthy but sensitive scopes are deliberately closed.”**

## Management-plane boundary

Layer 30 consumes Foundation’s canonical deployment expectation/observation truth.

It does **not** directly call the Supabase Management API, and Supabase Gateway health response headers do not expose the Edge Function deployment version.

Therefore a provider-side deployment must first be reconciled into Foundation deployment truth before Layer 30 can make deployment-specific claims about that runtime.

This boundary is explicit rather than hidden.

The build itself demonstrated it: when the Edge runtime moved ahead of the deployment ledger, readiness continued to describe the last reconciled runtime until deployment truth was updated. The runtime was then exact-source reconciled, given fresh health/audit evidence, and a new readiness fingerprint was recorded.

Layer 30 is the readiness evaluator over **canonical control-plane evidence**; it is not a replacement for the external management-plane observer that feeds deployment truth.

## Universe readiness semantics

Layer 30 integrates with the existing Universe readiness model without weakening it.

Foundation can provide release-specific evidence for:

- **built**;
- **tested**;
- **deployed**.

It does **not** automatically claim:

- **human_verified**.

That stage still requires explicit real-human acceptance evidence against the exact deployed release. CI, layer count, deployment, health and control-plane readiness never satisfy human verification by themselves.

## Acceptance coverage

The rollback suite proves all five states:

- healthy/aligned/pass → **READY**;
- warning guard dependency → **DEGRADED**;
- failed guard dependency → **RESTRICTED**;
- unhealthy required core runtime → **NOT_READY**;
- new runtime with healthy probes but no own audit proof → **UNKNOWN**.

It also proves:

- identical evidence deduplicates;
- readiness history is append-only;
- Gateway cannot directly write readiness observations;
- Foundation runtime can evaluate/read readiness but cannot record it;
- public roles cannot read or evaluate readiness.

## Advisors

No Layer-30-specific Supabase security finding was reported.

No Layer-30-specific Supabase structural performance finding was reported.

## Machine-readable contract

`foundation/contracts/control-plane-readiness-v1.json`

## Closure

Layer 30 changes Foundation from a collection of trustworthy control-plane subsystems into a control plane that can answer one operational question coherently:

> **“Given everything Foundation currently knows, what is the safest mode the Shine Universe should be operating in right now?”**
