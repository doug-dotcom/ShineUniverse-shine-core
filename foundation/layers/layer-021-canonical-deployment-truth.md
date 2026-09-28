# Foundation Layer 21 — Canonical deployment truth

**Status:** LIVE  
**Scope:** service registry + expected deployment state + observed runtime state + drift detection

Layer 21 gives Foundation a canonical answer to a question the control plane must never guess at:

> What service should exist here, what does the runtime actually report, and do those two states agree?

This layer was prompted by a real control-plane discrepancy: Foundation Layer 20 existed in the canonical GitHub repository while the Universe registry still reported Layer 19. The lesson is broader than one stale counter. Foundation needs a first-class deployment-truth contract rather than relying on humans to mentally reconcile repository state, runtime state and registry state.

## New persistence

Layer 21 adds:

- `foundation.service_registry` — canonical identity and ownership for Foundation services;
- `foundation.service_deployment_expectations` — append-only expected deployment state;
- `foundation.service_deployment_observations` — append-only runtime observations;
- `foundation.current_service_deployment_expectations` — latest expected state per service/environment;
- `foundation.current_service_deployment_observations` — latest observed state per service/environment;
- `foundation.get_service_deployment_truth_v1(text,text)` — one read contract returning deployment truth plus health state.

Expectations and observations are deliberately separate. A deployment collector is never allowed to silently rewrite what Foundation expected, and an expectation change is never allowed to masquerade as runtime evidence.

Both event stores are append-only.

## Truth states

The reader returns exactly three deployment truth states:

- **aligned** — expectation and observation both exist and all pinned fields match;
- **drift** — expectation and observation both exist but at least one pinned field differs;
- **unknown** — Foundation lacks enough evidence to compare safely.

Reason codes identify the failure precisely:

- `unknown-service`;
- `missing-expectation`;
- `missing-observation`;
- `runtime-ref-mismatch`;
- `version-mismatch`;
- `artifact-mismatch`;
- `runtime-state-mismatch`.

Missing evidence is never treated as success.

## Health is separate from deployment

A service can be deployed exactly as expected and still be unhealthy.

Layer 21 therefore returns `healthState` independently from `truthState`. The initial Foundation Gateway observation is:

- deployment truth: **aligned**;
- runtime state: **active**;
- health state: **unknown**.

That is intentional. Supabase reporting an Edge Function as ACTIVE proves the deployment exists; it does not prove request success rates, latency, dependency health or business correctness.

A later health collector can append a stronger observation without changing this contract.

## Initial canonical service

The first registered service is:

- service: `foundation.gateway`;
- owner: `shine-core`;
- kind: `supabase-edge-function`;
- project: `sjpxqeyewahraxvidvcc`;
- function: `foundation-gateway`;
- observed runtime version: `71`;
- observed artifact SHA-256: `18b6b0e4198bab8054234b325a80a6f98009817fbc2c38953922f5b4018f8c3b`;
- observed runtime state: `active`;
- observed health state: `unknown`.

The expectation is pinned to that verified runtime observation. Git commit provenance is deliberately left unset because Layer 21 does not have evidence proving which repository commit produced Edge Function v71.

No provenance is better than invented provenance.

## Security boundary

The deployment-truth tables are private Foundation control-plane data:

- RLS is enabled;
- `anon` and `authenticated` receive no table access;
- `foundation_runtime` has read-only access;
- `service_role` may register services and append evidence;
- the reader is `SECURITY INVOKER`, not `SECURITY DEFINER`;
- public roles cannot execute the reader.

## Machine-readable contract

`foundation/contracts/deployment-truth-v1.json`

The contract explicitly states that:

- expected and observed states are independent;
- ACTIVE does not imply healthy;
- missing evidence returns unknown;
- observations and expectations are append-only.

## Acceptance

Layer 21 is complete when:

- a clean Postgres rebuild creates all deployment-truth objects;
- the seeded Foundation Gateway returns `truthState: aligned`;
- its initial `healthState` remains `unknown`;
- a newer mismatched observation produces `truthState: drift` with `version-mismatch`;
- mutation of an observation is rejected;
- public database roles cannot read the control-plane tables or execute the truth reader;
- `foundation_runtime` can execute the reader;
- Supabase security and performance advisors show no new Layer 21 regression.

This is the first layer where Foundation stops merely storing deployment metadata and starts **proving whether runtime reality matches declared truth**.
