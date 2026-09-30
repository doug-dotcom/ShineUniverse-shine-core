# Foundation Layer 60 — Immutable promotion-closure receipts

**Status:** IMPLEMENTED — CI and production promotion pending  
**Scope:** make canonical source-truth closure a durable release fact rather than a one-time successful query

Layer 59 answers:

> Do the immutable binding, Universe registry, readiness-release ledger and current deployment all tell the exact same story right now?

Layer 60 answers the next question:

> Has that exact source-truth state been immutably recorded as a completed promotion?

Those are deliberately different.

## Why binding is not closure

A new deployment may legitimately create a new immutable binding before the Universe registry and readiness-release ledger have converged.

Blocking the binder on Layer 59 would create a deadlock:

1. new deployment changes canonical runtime identity;
2. a new binding is required;
3. projections still point to the previous release;
4. Layer 59 correctly fails until projections are repaired;
5. if binding itself required Layer 59 PASS, the new binding could never be created.

Layer 60 therefore does **not** weaken or replace the existing transition.

It adds a separate finalisation fact after convergence.

## Closure ledger

Append-only ledger:

`foundation.foundation_release_promotion_closures`

Each receipt binds to the exact:

- environment;
- immutable binding ID;
- release ref;
- Foundation layer;
- Git source ref;
- runtime version;
- artifact SHA-256;
- Layer-59 canonical source-truth fingerprint;
- complete Layer-59 evidence snapshot;
- closure timestamp;
- receipt SHA-256.

The closure ledger cannot update or delete historical receipts.

`service_role` has no direct INSERT privilege.

## Recorder

`foundation.record_foundation_release_promotion_closure_v1(...)`

may record a receipt only when:

`foundation.get_foundation_canonical_source_truth_v1(...)`

returns:

`state: pass`

If Layer 59 is FAIL, the recorder returns `not-closed` and writes nothing.

Replay for the same binding and source-truth fingerprint returns the original receipt rather than creating a duplicate.

## Automatic staleness

The status reader:

`foundation.get_foundation_release_promotion_closure_status_v1(...)`

independently re-runs Layer 59.

A previously valid receipt becomes stale if:

- the Layer-59 fingerprint changes;
- the binding changes;
- release ref changes;
- layer changes;
- source commit changes;
- runtime version changes;
- artifact changes.

Historical evidence remains append-only.

Current closure does not.

## Assertion boundary

`foundation.assert_foundation_release_promotion_closed_v1(...)`

is service-role-only.

It raises unless the current status is exactly:

`closed`

This gives deployment/release workflows one simple fail-closed promotion assertion without allowing those workflows to mutate the registry, ledger or immutable binding.

## Hosted cycle

The hosted recorder is staggered after existing projection and incident reconciliation.

It runs every five minutes.

When source truth is not closed, it writes nothing.

When source truth converges, it records one immutable closure receipt.

## Explicit separation from runtime health

A Layer-60 receipt states:

- `runtimeReadinessClaimed: false`
- `mutatesAuthoritativeTruth: false`

This matters for the current production state: source truth may be fully closed while runtime health/readiness is separately degraded or not-ready.

Layer 60 never converts one dimension into the other.

## Acceptance coverage

CI proves:

- PASS Layer-59 truth records one closure receipt;
- receipt SHA-256 verifies;
- replay is idempotent;
- a changed Layer-59 fingerprint makes the old receipt stale;
- the service-role assertion fails while stale;
- a fresh closure receipt restores closed state;
- FAIL Layer-59 truth cannot mint a receipt;
- recorder failure writes no authoritative state;
- runtime has read-only status access;
- runtime cannot record or assert closure;
- service role cannot bypass the recorder with direct ledger INSERT;
- browser/API roles cannot read closure status.

## Invariant

> A release may be bound while transition work is still in progress. It may be called promotion-closed only after independent canonical source truth has converged and that exact evidence has been immutably receipted.
