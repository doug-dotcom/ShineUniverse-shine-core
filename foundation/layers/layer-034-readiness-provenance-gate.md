# Foundation Layer 34 — Readiness provenance gate

**Status:** LIVE  
**Scope:** require fresh trusted deployment-publication provenance for the strongest Foundation READY state

Layer 30 established the control-plane readiness gate.

Layer 33 established durable GitHub OIDC publication attestation for deployment receipts.

Layer 34 connects those two truths.

Foundation can no longer report **READY** merely because runtime, health, dependencies, policies and audit are green. The current deployment must also have a fresh trusted publication attestation that matches the exact canonical runtime version, source commit and artefact SHA.

## Publication assurance check

The readiness evaluator now calls:

`foundation.get_deployment_receipt_publication_health_v1('foundation.gateway', environment, 86400)`

and includes a new:

`checks.publicationAttestation`

object containing:

- publication assurance state;
- assurance class;
- reason code;
- runtime version;
- source reference;
- artefact SHA-256;
- whether the publication matches deployment truth;
- publication ID/outcome;
- transport;
- GitHub run ID/attempt;
- publication timestamp.

## READY requirement

A deployment is READY-eligible only when publication assurance is:

**PASS**

and the publication identity matches canonical deployment truth on all three:

1. runtime version;
2. exact Git source commit;
3. artefact SHA-256.

A valid GitHub OIDC publication for the wrong deployment is not considered evidence for the current deployment.

## Readiness semantics

Layer 34 adds publication provenance to readiness precedence.

### PASS

Fresh trusted GitHub OIDC publication for the exact current deployment.

No readiness penalty.

### DEGRADED

The current deployment receipt has publication evidence, but the latest attestation is stale or non-OIDC/manual.

Readiness becomes:

**DEGRADED**

However this is an assurance degradation, not a runtime failure.

Therefore operation modes remain:

- safe mode: **normal**;
- privileged operations: **normal**;
- worker operations: **normal**.

### UNKNOWN

The current deployment receipt has no publication attestation.

Foundation cannot truthfully claim READY.

Readiness becomes:

**UNKNOWN**

with:

`deployment-publication-attestation-missing`

### NOT_READY

A valid publication attestation exists but identifies a runtime/source/artefact different from canonical deployment truth.

This is a hard evidence-integrity failure.

Readiness becomes:

**NOT_READY**

with:

`deployment-publication-attestation-mismatch`

## Fingerprint integration

Publication evidence now participates in the Layer-30 meaningful-evidence fingerprint.

The fingerprint includes:

- publication state;
- assurance;
- runtime version;
- source ref;
- artefact SHA;
- deployment-match boolean;
- publication ID;
- GitHub run ID.

The existing five-minute readiness observer therefore automatically creates a new readiness observation whenever trusted publication provenance materially changes.

No new scheduler is required.

## Acceptance coverage

Layer 34 rollback tests prove:

- fresh matching GitHub OIDC publication keeps a clean control plane READY;
- matching manual/non-OIDC publication degrades readiness while preserving normal runtime operation modes;
- missing publication attestation makes readiness UNKNOWN;
- fresh valid OIDC publication for the wrong deployment makes readiness NOT_READY;
- mismatch reason is explicit;
- runtime/public permission boundaries remain unchanged.

## Production evidence

The current Gateway deployment is:

- runtime: **85**;
- source:
  `b7c5331f93eff28a781f0794c89ccf50e90a4045`;
- artefact:
  `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`.

Current Layer-33 publication assurance is:

- state: **PASS**;
- assurance: `github-oidc`;
- publication:
  `2649330b-6117-44a0-9614-aae8f6fb8478`;
- GitHub run:
  `36395350182`;
- run attempt: `1`;
- repository:
  `doug-dotcom/ShineUniverse-shine-core`;
- ref:
  `refs/heads/main`;
- workflow SHA:
  `81a3888fdc743100b07f7c710373e0cabaee2ed9`.

The publication runtime/source/artefact match deployment truth exactly.

Live readiness can still independently move between READY / RESTRICTED / DEGRADED according to Defence, health and dependency state. Layer 34 only strengthens the evidence required for READY; it does not override those existing controls.

## CI

Foundation CI now applies:

`foundation/postgres/readiness-publication-assurance-v1.sql`

and runs:

`foundation/postgres/readiness-publication-assurance-v1.test.sql`.

The canonical readiness contract has been upgraded to schema version **1.1.0**.

## Closure invariant

Foundation READY now means:

> **The current deployment is aligned, healthy, dependency-safe, policy-complete, audit-complete, Defence-safe, and has fresh trusted publication provenance for that exact runtime/source/artefact.**

A green runtime with missing or mismatched publication provenance cannot claim READY.
