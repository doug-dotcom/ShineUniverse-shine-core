# Foundation Layer 63 — Producer/consumer contract parity

**Status:** IMPLEMENTED — CI verification pending  
**Scope:** prove the actual PostgreSQL producer and pinned JavaScript consumer contract agree end to end

Layer 62 pinned the promoted-release schema and consumer validator.

That still left one seam: PostgreSQL producer tests could pass and JavaScript validator tests could pass without the validator ever consuming the producer's real JSON in the same gate.

Layer 63 closes that seam.

## Parity verifier

The verifier foundation/integration-kit/verify-promoted-release-producer-consumer-parity-v1.mjs executes the actual foundation.get_foundation_promoted_release_v1 function inside the Foundation persistence database.

It captures the JSON emitted by PostgreSQL and passes that exact value directly into validatePromotedReleaseResponse.

There is no hand-copied response fixture between producer and consumer.

## Mandatory states

The parity gate proves both legal branches.

### Current closure

The real Layer-61 SQL producer must emit a response accepted as promoted, including the exact source commit and artifact identity, while making no runtime-readiness or authoritative-mutation claim.

### Stale closure

The same producer must emit a response accepted as hold, with promotedRelease null, no promoted-release SHA field and the fail-closed stale reason.

## No persistent test mutation

The Layer-60 dependency is replaced only inside a PostgreSQL transaction. Each parity probe ends with ROLLBACK.

The verifier therefore tests producer behaviour without changing persistent test-database authority or production state.

## CI position

The gate runs after Layer 60 and Layer 61 are installed and tested. Node 22 is explicitly provisioned in the persistence job rather than relying on runner defaults.

## Invariant

> Producer green and consumer green are insufficient when tested separately. Foundation promotion contracts are green only when the actual producer output passes the actual pinned consumer validator end to end.
