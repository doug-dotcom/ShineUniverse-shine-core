# Foundation Layer 62 — Pinned promoted-release contract

**Status:** LIVE — canonical schema pinned, consumer validator green and production payload verified  
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

Full Foundation CI run `36665199189` completed successfully.

The contract job passed the object-registry verifier, the Layer-61 raw-binding boundary and all Layer-62 validator tests. The full persistence chain also completed successfully through every downstream Shine Defence acceptance step.

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

## Production proof

The canonical schema is pinned in object-registry v1.8.0 to Git blob:

`5d67cfd13f4f300d9702970063142670c95c1c2a`

The live production promoted-release response was checked against the Layer-62 contract invariants and returned:

- contract ID: `shine-foundation/promoted-release-response-v1`
- schema version: `1.0.0`
- state: **promoted**
- available: **true**
- promotion closure: **closed**
- release: `foundation:layer-58:1a8148a8`
- source commit: `1a8148a8eb748a19ac03107d9e9ec7313297384b`
- promoted-release SHA-256: `ed4e6f4d7234161a6261fc98d58fd3bfd05ca35045fabfdc57dbf8c5ac51040f`
- runtime readiness claimed: **false**
- authoritative truth mutation: **false**
- live contract-shape check: **PASS**

Layer 62 does not alter production database state. It freezes the already-live Layer-61 interface at the repository/consumer-contract boundary.

## Invariant

> A promoted release is not merely a JSON object with familiar fields. It is one exact, versioned Foundation contract whose schema identity, validator semantics and Git blob are pinned together.
