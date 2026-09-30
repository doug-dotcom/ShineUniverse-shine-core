# Foundation Layer 69 — Shine Core owner evidence return

**Status:** LIVE — corrected CI green, production evidence-return boundary deployed and healthy baseline verified  
**Scope:** let the accepted Shine Core owner return immutable evidence without allowing owner claims to become canonical promotion trust

Layer 68 records explicit ownership.

Layer 69 closes the next seam:

`accepted work → owner evidence → independent Foundation verification`

## Claim-only evidence

Return function:

`foundation.return_foundation_promoted_release_owner_evidence_v1(...)`

The owner may report one of:

- resolved
- improved
- unchanged
- worsened
- inconclusive

It must also provide:

- a bounded summary;
- one or more observed facts;
- one or more evidence references;
- an optional recommended next step.

The function does not accept a caller-supplied canonical trust state.

## Preconditions

Evidence can be returned only when:

- the Layer-67 handoff exists and is current;
- handoff integrity verifies;
- owner routing is still current;
- Layer-68 acknowledgement is accepted;
- acknowledgement integrity verifies;
- acknowledgement still binds the exact handoff SHA and semantic response-plan fingerprint.

A rejected, clarification-requested, stale or unacknowledged handoff cannot return current owner evidence.

## Immutable binding

Each evidence packet binds:

- Layer-67 handoff ID and SHA-256;
- Layer-68 response ID and SHA-256;
- incident event ID;
- owner service/component;
- Layer-66 response-plan fingerprint;
- owner outcome;
- summary/facts/evidence refs;
- recommended next step;
- immutable packet SHA-256.

Only the first packet is authoritative history for that handoff.

Replay returns the original packet.

## Owner evidence is not Foundation truth

Every packet explicitly records:

- `ownerEvidenceIsCanonicalPromotionTrust: false`
- `ownerOutcomeClaimOnly: true`
- `requiresIndependentVerification: true`
- `promotionTrustChangedByOwnerEvidence: false`
- `incidentClosurePerformed: false`
- `layer38ApprovalGranted: false`
- `releaseTruthMutationAuthorityGranted: false`
- `releaseRebindAuthorityGranted: false`
- `incidentHistoryMutationAuthorityGranted: false`
- `runtimeMutationAuthorityGranted: false`
- `approvalGranted: false`
- `executionAuthorityGranted: false`
- `executesAction: false`

Even an owner report of **resolved** cannot close the incident or restore promotion.

## Currentness

Status reader:

`foundation.get_foundation_promoted_release_owner_evidence_status_v1(...)`

States:

- pending — current accepted work has no evidence yet;
- not-accepted — owner has not accepted the work;
- current — evidence integrity and all upstream bindings remain current;
- stale — incident/handoff/acknowledgement no longer current;
- invalid — cryptographic or relational binding failed.

Recovery makes old evidence stale current-state evidence while preserving history.

## Authority boundary

Only `shine_core_control_plane` may submit evidence.

Gateway, Foundation runtime, service role and Defence cannot author it.

The owner capability has no direct SELECT or INSERT on the evidence ledger.

Foundation runtime/service role may read bounded status for later independent verification.

## Acceptance coverage

The first Layer-69 run `36679983525` exposed a test-only privilege violation: after switching to `shine_core_control_plane`, the test attempted to recover the handoff ID through a raw Layer-67 table read. PostgreSQL correctly denied that access.

A concurrent first fix replaced the raw read with a second bounded-inbox lookup, but acceptance intentionally empties that inbox. The final test therefore carries the handoff ID from the original bounded inbox through acknowledgement, evidence return, status and replay checks without any raw-table rediscovery.

Corrected full Foundation CI run `36680299748` completed successfully. Both Foundation jobs passed, the Layer-69 evidence-return tests passed, and all downstream Shine Defence checks remained green.

CI proves:

- accepted current owner work can return evidence;
- evidence binds handoff, acknowledgement and response-plan fingerprints;
- owner outcome remains claim-only;
- owner evidence cannot change promotion trust or close incidents;
- replay cannot replace the first packet;
- only Shine Core capability may submit;
- direct ledger access is denied;
- recovery makes evidence stale but preserves integrity;
- evidence history is append-only.

## Production proof

Layer 69 is deployed in the Shine Foundation Supabase project.

Production is currently healthy:

- promotion-trust incident state: **normal**
- trust state: **normal**
- current owner handoffs: **0**
- pending Shine Core inbox items: **0**
- owner evidence-return rows: **0**

No synthetic incident, handoff, acknowledgement or owner evidence packet was created in production merely to demonstrate the path.

Privilege proof:

- `shine_core_control_plane` may submit owner evidence: **yes**
- Gateway may submit owner evidence: **no**
- Foundation runtime may submit owner evidence: **no**
- service role may submit owner evidence: **no**
- Shine Defence runtime may submit owner evidence: **no**
- owner direct evidence-ledger SELECT: **no**
- owner direct evidence-ledger INSERT: **no**
- service role direct evidence-ledger INSERT: **no**

The live Layer-69 surface therefore exists but remains empty until a real accepted promotion-trust owner handoff needs evidence returned.

Supabase advisors:

- no Layer-69-specific security finding;
- no Layer-69 unindexed foreign-key finding;
- the two new Layer-69 indexes currently appear as `unused_index` INFO because healthy production has zero evidence rows;
- the remaining unindexed foreign-key INFO belongs to concurrent GitHub-OIDC replay-alert work, not Layer 69.

## Invariant

> The owner may explain what it observed. Only independent Foundation evidence may decide whether promotion trust actually recovered.
