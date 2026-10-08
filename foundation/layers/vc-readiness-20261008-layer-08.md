# VC readiness — layer 08: purpose-bound grant contract

8 October 2026, Brisbane. Source baseline: fb68223446e5d4f07c72e41a5f2d5eb887b5acef.
After successful merge: 8/40 source-verified Foundation producer layers; 32 remain (80%). Live/consumer acceptance remains separate.

## New enabling outcome

Foundation now supplies createVeteranCarePurposePermissionEvaluator. An appointment-preparation read requires one current server-verified preparation record and a grant with an exact purposeBinding {kind:'appointment-preparation',preparationId}. The same generic purpose label cannot authorise another preparation. Broad legacy grants without that binding, wrong kind/context and extra binding fields cannot match.

Reconciliation: the generic engine and layer 07 already enforce exact purpose-string equality; that old outcome is reused, not counted again. The concrete gap closed here is purpose-instance reuse across preparation records. The new wrapper composes all existing project/caller/identity/audience/session/resource and deny-default checks. Selection is snapshotted before asynchronous work; concurrent requests do not share binding state.

A persisted preparation is not a booking, clinical verification or consent. Free-text purpose/questions/notes do not create authority. No preparation content or booking claim appears in the decision. This binding does not broaden record/version, operation or recipient scope.

## Versioned interface and handover

Producer: foundation/onboarding/veteran-care-purpose-v1.mjs, version 1. Isolated branch foundation/vc-readiness-layer-08.
Input: existing authContext and exact selected-record request, plus purposeContext exactly {preparationId}. UUID canonicalisation is lowercase.
Mandatory trusted getPreparationContext input: {preparationId,ownerShineId,appId,purpose}. Identity is derived from verified Foundation authority.
Output: {status:'available',preparationId,ownerShineId,purpose}, or null/unavailable. It must project a current persisted preparation owned by the verified veteran, with canonical owner mapping and the fixed machine-readable appointment-preparation purpose. Browser values, free text and inferred bookings cannot serve as this projection.

Bound request contract: shine-foundation/veteran-care-purpose-request-v1, schemaVersion 1.0.0. Inherits the exact layer-06 request fields and adds immutable purposeBinding {kind:'appointment-preparation',preparationId}. Layer-07 permission-context authority receives this bound request. Every eligible grant must carry the exact binding as well as its existing exact owner/app/scope/purpose/resource/version and lifecycle fields.

Layer 07 gains an optional server binding hook; its original API is preserved. Consumers needing this outcome must use the new purpose-bound factory. This is a server permission decision with executionPerformed false, not a grant write, portable credential, ticket or invocation.
Legacy unbound grants are deliberately not upgraded automatically. Any persisted binding/migration and explicit consent for it remain with the consumer owner. Existing preparation IDs may retain edited notes; those edits never expand the fixed machine purpose or selected resource/version. Consumers must recheck current preparation existence and relevant authority at execution/delivery; changes after lookup are not atomically covered.

## Single ownership

Foundation owns the reusable purpose contract and producer guard.
VC Integrations & Security owns actual preparation/grant projection, new-binding storage/consent integration, consuming branch, current operation enforcement, live tests and deployment.
App/Passport owns preparation records, screens and workflow semantics.
Shine AI owns its own admission and private handoff policy. No AI route or credential changed.

Reviewed current VC 7d9d5673ed6ab4bef87ba515873838944d1e9ee2: appointment-preparations.mjs blob d0b2cd2444172dec094047db793349c4557a8ae8 saves veteran-owned preparation records and explicitly distinguishes notes/documents text from booking/sharing. sharing-input.mjs blob 623da020659e5d1bf12301276b9545f0fb2de3c4 retains explicit exact-recipient confirmation. These consumer implementations are unchanged; no SQL, record or consent writes occur here.
Repository receipt is discoverable coordination, not acknowledgement by other active rooms.

## Verification and open gates

Command: node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
138 passed, 0 failed, including 13 new tests. Synthetic claims/session/resource/preparation/grant authority outputs only. Tests cover exact binding, cross-preparation reuse, broad/legacy bindings, foreign/missing/deleted context, malformed caller context, accessors, forged free text, canonical IDs, mutation across awaits, concurrency, outages, prior session denial and output minimisation.
Foundation CI includes the new suite; Foundation and Defence workflow success are required before merge. Existing generic grant consent and permission engine remain unchanged.

Open: persisted authoritative preparation/binding projection, explicit consent/storage integration, real-session/real-grant probes and exact deployed acceptance. No hosted/private-browser or production deployment proof is claimed.
Next: layer 09, grant expiry enforcement.
