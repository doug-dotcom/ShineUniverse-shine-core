# VC readiness — layer 06: exact resource scoping

8 October 2026, Brisbane. Source baseline: 29c24056d99e409329802bd9cf28411e7731164d.
After successful merge: 6/40 source-verified Foundation producer layers; 34 remain (85%). VC consumer/live acceptance remains separate.

## Enables Veteran Care

Foundation supplies createVeteranCareResourceScopeBuilder, version 1. A selected-record read is converted into an immutable exact request after the dedicated project, app caller, identity, audience and current-session checks. The veteran is derived from verified Shine ID; caller fields cannot substitute an owner, app, scope, purpose, operation or request ID. One record/version is checked against authoritative metadata for matching owner, resource ID/version and VC record category.

Reuses layer 02's exact input validator; does not count ID syntax validation again. New behaviour binds the selection to server identity and authoritative metadata, then produces the exact shared-service request. UUIDs are canonicalised to lowercase, preserving selection. Wrong/missing metadata uses one bounded denial to avoid distinguishing missing versus other-owner records. Dependency failures withhold scope.

Only selected_record_read is supported. The fixed read/scope/purpose tuple comes from layer 02; this layer does not evaluate a sharing grant or broaden Adj's general-guidance capability. scope-ready explicitly reports authorizationApplied false and executionPermitted false. No record content, credential or metadata extras propagate into output.

## Producer/consumer handover

Foundation producer: foundation/onboarding/veteran-care-resource-scope-v1.mjs. Isolated branch foundation/vc-readiness-layer-06.
Input request: exactly {capabilityId,input:{recordId,recordVersion}}, alongside authContext. Server generates requestId.
Trusted getResourceDescriptor input: {appId,ownerShineId,recordId,recordVersion}. Result: {resourceId,resourceVersion,ownerShineId,category}, or null. It must project persisted authoritative metadata and canonical owner mapping; never take browser-supplied metadata as authority. It must not retrieve record content.

Output request fields: contract, schemaVersion, requestId, appId, shineId, capabilityId, operation, scope, purpose, resourceId, resourceVersion, resourceCategory.
Version 1 contract: shine-foundation/veteran-care-resource-request-v1.
This describes an exact permission request, not an executable ticket or grant. Consumer must still check current explicit permissions, grant lifecycle, resource/version and authority at execution/delivery; scope can become stale after metadata lookup. This initial path is the verified veteran's own selected record. Practitioner/shared-recipient scope is not inferred from it.

VC Integrations & Security owns actual metadata projection, dedicated-project/record access, grant checks, consuming branch, live enforcement and deployment. App/Passport owns record workflows and screens. No VC SQL, schema, browser module or record-sharing implementation changed.
Shine AI owns its service admission and private handoff enforcement. No model, retrieval route or AI credential is introduced.

## Coordination evidence

Reviewed VC current main b432f057dc87e4dc6cfedad91c64cee8d78ce5c9 and VC-L09-PRACTITIONER-ENFORCEMENT-20261008.md, blob c61e178c2113f85fbd3d82d3e0f8c961b80e5012. Its practitioner database verification and real-session/admin boundary gates remain owned by Integrations & Security; this producer request builder does not close them. Foundation remains the shared gateway authority owner. Repository receipt is discoverable handover, not acknowledgement by another room.

## Verification and open gates

Command: node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
109 passed, 0 failed, including 13 new tests. Synthetic identity, claims, sessions and metadata only. New tests cover exact scoped output, forged request authority, unsupported operations, malformed selectors, accessors/inherited properties, wrong owner/ID/version/category, session/caller denial before metadata, UUID canonicalisation, output minimisation, mutation during lookup, bounded errors and concurrent selections.
Foundation CI includes the new suite. Foundation and Defence workflows must pass before merge.

No hosted metadata lookup, real record retrieval, actual grant evaluation, private browser acceptance or production deployment is claimed. Consumer projection/wiring and exact live acceptance remain open.

Next: layer 07, deny-by-default permissions.
