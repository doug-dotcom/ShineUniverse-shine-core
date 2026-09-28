# Foundation Layer 36 — Continuous release projection reconciliation

**Status:** LIVE  
**Scope:** continuously reconcile Universe registry projection, readiness-release ledger and immutable Foundation release identity

Layer 35 established an immutable release identity for each verified Foundation layer.

Layer 36 makes the projections around that identity continuously self-checking.

Foundation now evaluates whether the human-facing Universe registry and readiness-release ledger still agree with the immutable binding and records only meaningful reconciliation changes.

## Reconciliation reader

Layer 36 adds:

`foundation.get_foundation_release_projection_health_v1(text,timestamptz)`

The reader checks:

1. the Universe app registry exists;
2. the Universe readiness-release ledger exists;
3. a current immutable Foundation release binding exists;
4. registry `current_layer` matches the binding layer;
5. registry `readiness_release_ref` matches the binding release ref;
6. the registry release target exists in `universe.readiness_releases`;
7. the binding release also exists in that ledger;
8. the release ledger's `source_layer_ref` matches the bound Foundation layer;
9. the canonical repository remains `doug-dotcom/ShineUniverse-shine-core` and confirmed;
10. registry status remains verified/deployed;
11. Layer-35 release identity health remains non-failing.

## States

### ALIGNED

Registry, readiness-release ledger and immutable binding agree.

### DEGRADED

Identity still agrees, but registry verification/build state or release evidence quality is degraded.

### UNKNOWN

Required projection schema or release identity health cannot be established.

### FAIL

A required registry, release-ledger or binding invariant is missing or mismatched.

Hard failures include:

- missing Foundation registry row;
- missing immutable binding;
- missing registry release ref;
- registry/binding release-ref mismatch;
- registry/binding layer mismatch;
- registry release target missing;
- binding release missing from the Universe ledger;
- release-layer mismatch;
- canonical repo mismatch;
- Layer-35 release identity failure.

## Meaningful-change observation ledger

Layer 36 adds the append-only table:

`foundation.foundation_release_projection_observations`

and current view:

`foundation.current_foundation_release_projection_observation`

The recorder is:

`foundation.record_foundation_release_projection_observation_v1(text,timestamptz)`

Each evaluation gets a deterministic evidence fingerprint from the meaningful reconciliation fields.

If the fingerprint is unchanged, the recorder returns:

`unchanged`

and does not add another row.

If the projection materially changes, it appends a new observation.

This prevents five-minute polling from producing useless ledger noise.

## Continuous observer

Production pg_cron job:

`shine-foundation-release-projection-5m`

Schedule:

`1,6,11,16,21,26,31,36,41,46,51,56 * * * *`

The one-minute offset follows the normal five-minute Foundation readiness/health cycle.

The observer only detects and records drift.

It does **not** silently repair the Universe registry or release ledger. Authoritative mutation remains an explicit control-plane action.

## Production release

Layer 36 release projection:

`foundation:layer-36:b7c5331f`

The suffix remains the exact deployed Gateway source because Layer 36 changes database control-plane reconciliation rather than the Gateway runtime artefact.

Current bound runtime identity:

- Gateway runtime: **85**;
- source:
  `b7c5331f93eff28a781f0794c89ccf50e90a4045`;
- artefact:
  `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`;
- deployment receipt:
  `bac106fe-57c4-4b38-b8bb-0acb5de11086`;
- publication:
  `2649330b-6117-44a0-9614-aae8f6fb8478`;
- publication assurance: **github-oidc**.

The Layer-36 binding was made while Foundation readiness was **READY**.

## Live reconciliation evidence

Current release projection state:

**ALIGNED**

Current checks:

- registry schema present: **true**;
- release-ledger schema present: **true**;
- registry matches binding: **true**;
- registry release target exists: **true**;
- bound release exists: **true**;
- bound release layer matches: **true**;
- canonical repo confirmed: **true**.

Current reconciliation fingerprint:

`d920970b982c3857125de07cb78c4514`

The first live observation was recorded once.

An immediate second recorder call returned `unchanged`, leaving the observation count at one.

The hosted pg_cron observer then ran automatically at:

`2026-09-28 09:36:00 UTC`

with status:

**succeeded**

and again produced no duplicate evidence because truth had not changed.

## Acceptance coverage

Layer-36 CI proves:

- aligned registry/release/binding projection reports ALIGNED;
- identical observations deduplicate;
- a stale registry release pointer fails closed;
- a stale registry layer fails closed;
- the stale transition is appended as new evidence;
- a missing release-ledger projection fails closed with explicit missing-target reasons;
- runtime may read reconciliation health;
- runtime may not write reconciliation observations;
- service role may invoke the controlled recorder;
- service role may not bypass the recorder with direct table INSERT.

Foundation CI run:

`36404247467`

completed successfully end-to-end after correcting the missing-row boolean classification.

## Advisor result

Post-deployment advisors show:

- **no Layer-36 security findings**;
- **no Layer-36 performance findings**.

## Closure invariant

Foundation's verified release projection now means:

> **The Universe registry, the Universe readiness-release ledger and the immutable Foundation release binding all point to the same layer release, and that agreement is continuously re-evaluated and recorded when it changes.**

A stale registry pointer or missing release projection can no longer quietly remain green between manual audits.
