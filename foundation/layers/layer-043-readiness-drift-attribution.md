# Foundation Layer 43 — Post-bind readiness drift attribution

**Status:** LIVE

Layer 43 makes readiness drift first-class without conflating it with immutable deployment identity.

## Classification

- `stable` — current readiness fingerprint equals the binding baseline and deployment identity is stable.
- `operational-degradation` — readiness changed, but Gateway source/version/artefact/publication identity still matches.
- `identity-drift` — deployment/publication identity no longer matches the immutable binding.
- `not-bindable` — binding is absent or readiness is unknown/not-ready.

## Evidence

Append-only table:

`foundation.foundation_readiness_drift_observations`

Reader:

`foundation.get_foundation_readiness_drift_v1(...)`

Recorder:

`foundation.record_foundation_readiness_drift_observation_v1(...)`

Each observation preserves bind-time readiness, current readiness, deployment-identity stability, privileged/worker modes, reason codes and guarded/degraded/blocked dependency scopes.

## Live Layer-42 drift proof

Before Layer-43 promotion, production was:

- Gateway runtime v90
- deployment identity stable
- release projection aligned
- readiness degraded
- reason: `dependency-degraded`
- degraded scopes: context, control, credential, identity, permission and protected operations
- privileged operations mode: degraded

Layer 43 classified this as:

`operational-degradation`

with:

- `requiresReleaseRebind: false`
- `requiresMonitoring: true`
- `privilegedOperationsRestricted: true`

The observation was recorded append-only before promotion.

## Layer-43 baseline

Layer 43 then bound the same trusted Gateway v90 identity while readiness was honestly `degraded`.

Therefore the current Layer-43 drift state is `stable` relative to its bind-time baseline.

This does **not** mean readiness is healthy.

It means:

- deployment identity has not drifted;
- current readiness has not drifted from the Layer-43 baseline;
- readiness remains degraded;
- privileged and worker operation modes remain degraded.

## CI

Foundation run `36415506181` passed the Layer-43 classifier and the full downstream chain.

CI proves operational degradation does not require a release rebind, matching readiness is stable, and true deployment mismatch is classified as identity drift.

## Advisors

- Layer-43 security findings: 0
- missing Layer-43 FK indexes: 0
- only unused-index INFO remains while observation volume is minimal

## Invariant

> Readiness may change without release identity changing. Preserve both truths instead of rewriting one to hide the other.
