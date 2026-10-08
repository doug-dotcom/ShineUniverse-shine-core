# VC readiness — layer 07: deny-by-default permissions

8 October 2026, Brisbane. Source baseline: f05c0138526f56075df8190bbbf7860dd5b748a9.
After successful merge: 7/40 source-verified Foundation producer layers; 33 remain (82.5%). Consumer/live acceptance is separate.

## Enables Veteran Care

createVeteranCarePermissionEvaluator composes the session-bound identity and exact-resource builder with a mandatory trusted permission-context lookup. It allows a permission decision only when the registered app manifest declares the request, exactly one effective exact-record/version grant matches the verified owner/app/scope/purpose, and Defence explicitly reports allow. No data operation or ticket is executed.

Reconciliation: the existing generic permission engine already handles identity, manifest, scope/purpose/resource matching, revocation, inactive, future and expired grants. That engine is reused unchanged; those old outcomes are not counted as new. Its default permits an unevaluated Defence state and chooses the first effective grant. This additive VC path closes those missing outcomes with explicit Defence allow, duplicate-ID rejection and refusal of multiple effective grants independent of order. Category-only and mixed selectors cannot substitute for this exact-version path.

Missing/malformed contexts, missing grants, unsupported Defence states and ambiguous grants fail closed with bounded deny responses. Adapter exceptions and invalid clocks produce unavailable plus decision deny. The engine evaluates grant time using the server clock after permission lookup. Distinct revoked historical grants do not compete with one effective current grant.

## Exact producer/consumer contract

Foundation producer: foundation/onboarding/veteran-care-permission-v1.mjs, version 1, isolated branch foundation/vc-readiness-layer-07.
getPermissionContext input: {request}, containing the immutable server-derived layer-06 request.
Trusted output: {complete:true,appManifest,grants,defenceDecision}. Missing/false completeness is refused; true is the server adapter's explicit assurance of a complete candidate set. Grants are a complete candidate set, at most 100 data entries, with unique UUID grant IDs, UUID ownerShineId, appId, scope, purpose, status, resourceSelector and applicable generic time/revocation fields. Exact selectors are {resourceId,resourceVersion}. Missing entries, incomplete/truncated sets or guessed defaults must not be returned as current authority.
The adapter must retrieve current Foundation-owned grant/manifest state and a current Defence decision for that exact request. Browser grant arrays, caller assertions, cached UI status and conversation consent are excluded.

Success: status permission-allowed, decision allow, grantId, exact request, authorizationApplied true and executionPerformed false.
This is a point-in-time server permission evaluation, not a signed/portable credential, capability registration, ticket or invocation. Session/resource checks occur before permission lookup; the consumer must recheck relevant identity, version and grant/Defence state at the sensitive execution/delivery boundary. Revocation occurring after a check is not atomically covered here.

Foundation owns this producer guard and shared permission contract. VC Integrations & Security owns actual server projection, consuming branch, live grant/Defence adapters, operation enforcement and deployment. App/Passport retains consent screens and workflow ownership. No VC files, SQL, grant mutation, credentials or real records changed.
Shine AI retains independent service admission, replay controls and private handoff checks. This decision does not bypass them.

## Coordination and verification

Latest VC practitioner ownership/evidence reviewed during layer 06 at b432f057dc87e4dc6cfedad91c64cee8d78ce5c9, blob c61e178c2113f85fbd3d82d3e0f8c961b80e5012. Existing VC practitioner SQL checks are not repeated or claimed here. Repository receipt is discoverable handover, not acknowledgement by other active rooms.

Command: node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
125 passed, 0 failed, including 16 new tests. Synthetic identity, session, metadata and permission/Defence authority outputs only. New tests cover one exact effective match, malformed/missing data, non-allow Defence states, order-independent ambiguity, duplicate IDs, inactive history, wrong tuple, broad/wrong-version selectors, existing temporal denial, forged caller policy, pre-permission session denial, outages/clock failure, grant expiry during lookup, per-request rechecking and concurrency.
New suite is included in Foundation CI. Foundation and Defence success are required before merge. Generic engine source stays unchanged.

Open: actual current permission/Defence projection, real grant/session execution probes, consuming wire-up and exact deployed acceptance. Local mocks do not establish hosted enforcement.
Next: layer 08, purpose-bound grant contract.
