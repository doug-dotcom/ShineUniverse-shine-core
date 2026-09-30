# Foundation Layer 59 — Canonical source-of-truth closure

**Status:** IMPLEMENTED; production verification required after CI  
**Scope:** make “green means green” distinguish build success from canonical production truth

Layer 59 adds one boring rule:

> A Foundation release is not source-of-truth closed until the immutable binding, Universe registry, readiness-release ledger and current deployment all describe the same exact release.

## Why this layer exists

The live Foundation CI was green while the production immutable binding had advanced to Layer 58 but:

- the Universe registry still projected Layer 49;
- the Layer-58 readiness-release row was missing.

The existing Layer-36 reconciliation correctly detected that drift in production, but the build itself could still be green because CI verifies a clean ephemeral database rather than the long-lived production projection.

The drift was repaired through the existing governed path rather than direct table mutation:

1. external approval;
2. approval consumption;
3. execution admission;
4. scoped release-ledger repair;
5. fresh incident evidence;
6. separate scoped registry repair;
7. independent Layer-42 verification.

The control-plane source-truth incident then recovered normally. Runtime/readiness degradation remained separate and visible.

## New reader

`foundation.get_foundation_canonical_source_truth_v1(...)`

It independently requires:

- Layer-36 structural projection closure;
- binding release-ref derived from the binding's exact Git SHA;
- registry layer/release matching the immutable binding;
- registry status `verified` + `deployed`;
- canonical repository confirmed;
- bound readiness-release row present;
- release-ledger layer matching the binding;
- release-ledger source commit matching the binding commit;
- release-ledger evidence URL matching the canonical GitHub commit URL;
- deployment truth aligned;
- deployment source, runtime version and artifact matching the immutable binding.

A structurally closed projection may be `degraded` because runtime/readiness health is intentionally a different truth dimension.

## Assertion boundary

`foundation.assert_foundation_canonical_source_truth_v1(...)`

is service-role-only and raises if canonical source truth is not closed.

It does **not** repair anything.

Layer 59 therefore adds a reusable release/promotion gate without creating automatic authority over the registry, release ledger or binding.

## Acceptance coverage

CI proves:

- structurally closed source truth passes even when runtime identity health is degraded;
- a readiness-release row with the correct layer but wrong Git commit fails;
- a wrong canonical Git evidence URL fails;
- deployment source drift from the immutable binding fails;
- the service-role assertion passes only for closed truth;
- public API roles cannot execute the reader;
- Foundation runtime may read status but cannot execute the assertion.

## Production repair evidence

The Room #1 repair used the existing Layer-39 → Layer-42 governance chain.

- Layer-58 release-ledger repair execution:
  `59100000-0000-4000-8000-000000000005`
- Layer-58 registry repair execution:
  `59300000-0000-4000-8000-000000000005`
- independent verification:
  `59400000-0000-4000-8000-000000000002`
- recovered projection incident:
  `08d5776d-d3d4-49a4-92c5-35c396617722`

After repair, registry, binding and release ledger all project:

`foundation:layer-58:1a8148a8`

The release projection is **DEGRADED**, not FAIL, because the remaining condition is the separate runtime/readiness health path rather than source-of-truth divergence.

## Closure invariant

> Build green, deployment identity, registry projection and release provenance must agree before Foundation may call its source truth closed. Runtime health remains independently truthful.
