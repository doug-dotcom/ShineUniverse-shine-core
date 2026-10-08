# VC readiness — layer 24: L app binding

8 October 2026, Brisbane. Baseline e5a9ba517d8a2d002e9d851b9e08dd2fcdd27d0c.
After merge: 24/40 source-verified producer layers; 16 remain (40%).

## Enables VC

createVeteranCareLAppBinder binds the canonical Foundation native L client identity shine.companion to a verified VC actor and the current approved VC/L link. It reuses the existing dedicated VC session verifier and Foundation verifyIntegrationClient adapter contract. The verified client must be shine.companion with first-party-companion kind. App credentials alone do not establish a user: an independent trusted L verifier must authenticate its user credential and map it to exactly the same ShineID as the VC session.

Only after both checks does the binder query the current link for {foundationAppId,clientId,actorShineId}. The returned link must be active, belong to that exact app/client/owner, have a UUID link ID, a positive integer revision and an unexpired deadline. The final clock check catches expiry during asynchronous lookups and clock regression. Each new bind consults current authority; no cached binding renews a revoked link.

The frozen server-private result includes the VC app, companion client, actor/owner, link ID/revision and approved deadline. It explicitly leaves executionPermitted, memoryReadPermitted and memoryWritePermitted false and requiresFreshExecutionCheck true. It contains no raw credentials, clinical content or memory queries. Identity/link binding is not memory consent and is not a portable bearer token.

## Ownership and interface

Foundation owns the exact identity/link contract and current approved link projection. L owns verification of its real authenticated user credential and authoritative ShineID mapping; verifyCompanionUser must independently verify the supplied user token, never echo caller-selected identity. VC Integrations owns transport, protected adapter wiring and deployment. Memory scope enforcement is next, separately from this identity layer. Existing VC session/client authentication is reused, not counted again.

Input is exactly {authContext:{appToken,jwt},companionAuthContext:{clientToken,userToken}}. Credentials are captured as frozen strings before awaits. No caller-supplied client, owner, link, memory scope or authority override is accepted. Required adapters are verifyIntegrationClient({authContext,claimedClientId}), verifyCompanionUser({authContext,clientId}) returning exactly {verified,clientId,shineId}, and getCurrentVCCompanionLink(query) returning exactly {foundationAppId,clientId,ownerShineId,linkId,status,revision,validUntil}. Missing/malformed/currently withdrawn authority fails closed, and exceptions return a fixed unavailable code without dependency details.

Canonical identity evidence: foundation/layers/delegation-refresh-idempotent-v2.md names native Shine Companion (shine.companion) and its L-side credential ownership; foundation/gateway/integration-client-status-v1.mjs defines the verified client adapter contract. No credentials are read or generated for deployment here.

Binding metadata must remain in trusted server orchestration and must be rechecked at execution after asynchronous delays. It is point-in-time evidence without transaction locks. No L memory database, credential mechanism, AI policy, app UI, real linked user or live route is changed. Real L verifier/current link adapters and authenticated live consumer evidence remain open. No cross-room acknowledgement claimed.

## Evidence

10 focused tests cover bounded immutable metadata, wrong app/kind, missing or mismatched user proof, revoked/missing/wrong-owner/app/client/malformed links, fresh revision/withdrawal, expiry and clock regression, dependency outages, owner/memory override and accessor rejection, credential mutation capture, and VC session failure before L lookup.
295/295 local onboarding/runtime tests passed; diff check passed. The suite is registered in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 25, memory scope enforcement.
