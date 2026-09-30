# Foundation Layer 62 — Pinned promoted-release contract

**Status:** IMPLEMENTED — CI verification pending  
**Scope:** freeze the Layer-61 promoted-release wire contract so downstream consumers cannot reinterpret promotion completion

Layer 61 makes one consumer-safe release projection.

Layer 62 makes its exact shape canonical.

## Canonical schema

New pinned schema:

`foundation/schemas/promoted-release-response-v1.schema.json`

Contract identity:

`shine-foundation/promoted-release-response-v1`

Schema version:

`1.0.0`

The schema defines both legal response modes:

### Promoted

Requires:

- `available: true`
- `state: promoted`
- `reasonCode: promotion-closure-current`
- `promotionClosureState: closed`
- exact promoted-release identity/provenance fields
- promoted-release SHA-256

### Hold

Requires:

- `available: false`
- `state: hold`
- `promotedRelease: null`
- no promoted-release SHA-256

Both modes require:

- `runtimeReadinessClaimed: false`
- `mutatesAuthoritativeTruth: false`

## Consumer validator

Reusable integration helper:

`foundation/integration-kit/promoted-release-response-v1.mjs`

Exports:

- `validatePromotedReleaseResponse(...)`
- `assertPromotedReleaseResponse(...)`
- canonical contract identity metadata

The validator is intentionally strict:

- unknown fields fail;
- malformed UUIDs fail;
- malformed Git source refs fail;
- malformed source/artifact/closure hashes fail;
- promoted state without closed promotion fails;
- hold state carrying promoted identity fails;
- runtime-readiness claims fail;
- authoritative-mutation claims fail.

## Object registry pin

The schema is registered in:

`foundation/object-registry-v1.json`

Registry version advances to:

`1.8.0`

The registry pins the schema to its exact Git blob SHA.

Existing `verify-object-registry-v1.mjs` therefore turns any silent schema edit into a red build until the schema version/registry entry is explicitly updated.

## Layer-61 contract linkage

The Layer-61 consumer contract now declares:

- its canonical response schema;
- its reusable consumer validator;
- the invariant that consumers validate the response before trusting release identity.

## Acceptance coverage

Foundation contract CI runs Node tests covering:

- schema identity matches validator identity;
- production-shaped promoted response passes;
- fail-closed hold response passes;
- stale closure cannot masquerade as promoted;
- hold cannot carry a promoted release;
- readiness/mutation claims are rejected;
- malformed provenance is rejected;
- extra uncontracted fields are rejected;
- promoted-release fingerprint omission is rejected.

The existing object-registry verifier separately proves the schema file itself has not drifted from its registered Git blob.

## Invariant

> A promoted release is not merely a JSON object with familiar fields. It is one exact, versioned Foundation contract whose schema identity, validator semantics and Git blob are pinned together.
