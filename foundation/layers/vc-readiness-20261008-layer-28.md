# VC readiness — layer 28: result audience

8 October 2026, Brisbane. Baseline c57ccaaef529ee2a1a424903abcc6e6a800e7ad6.
After merge: 28/40 source-verified producer layers; 12 remain (30%).

## Enables VC

createVeteranCareResultAudienceGate adds independently authenticated recipient checks around layer-26 selected-memory retrieval. It verifies the VC session first, then requires a current service credential bound to vc-trusted-server, shine.veteran-care and that exact authenticated user. Recipient service principal, positive revision and unexpired deadline are captured before content retrieval. Caller-supplied audience, owner, result or recipient authority fields are rejected.

The internal retriever continues to enforce exact memory consent and repeat its permission checks before returning a prepared result. The audience gate requires that result owner to equal the verified recipient actor. It verifies the recipient again and rejects withdrawal or any actor/audience/principal/revision/deadline change. Because that verification can await external authority, it then performs another full memory scope evaluation and compares it with the actual read query captured locally for this invocation. A replacement grant, changed permission revision/link, revoked consent or expiry during recipient verification cannot inherit the initial read authority.

The final clock must be valid, monotonic and before both memory and recipient deadlines. The frozen audience-bound-result names recipient app, user, service principal, revision and bounded deadline. Private content is returned only to trusted calling orchestration; modelDisclosurePermitted and memoryWritePermitted remain false, transportPerformed is false and requiresFreshDisclosureCheck is true. The contract permits no model, browser, different app or different user audience. Result shape/scope validation does not certify the meaning of returned text.

## Ownership and interface

Foundation owns the exact audience matching and joined final gate. Existing session/memory scope/retrieval implementations are reused without new credit. VC Integrations owns real recipient authentication, current service registration and protected transport. L owns the read adapter and memory enforcement. AI owns any model disclosure authority; this change does not extend the current AI policy.

Input is exactly the layer-25 authContext,companionAuthContext,request plus recipientAuthContext:{serviceToken}. Credentials and selected scalars are captured before awaits. verifyResultRecipient receives {authContext:{serviceToken},audience:'vc-trusted-server',appId:'shine.veteran-care',actorShineId}. It must independently authenticate the service credential and its user-bound request, consult current service authority and return exactly {verified,audience,appId,actorShineId,servicePrincipalId,revision,validUntil}. Query values must not be echoed as proof; missing authority has no fallback. The service credential is never supplied to the memory read adapter or copied into the output.

A fresh recipient lookup occurs before retrieval and before the final memory check. Read query capture is local per invocation; concurrent requests cannot exchange scopes or content. The trusted read callback must perform no writes, model calls, usable-link issuance or external disclosure before the final gate; Foundation cannot sandbox or undo a violating callback. The gate does not itself send content anywhere.

Returned objects remain inside trusted server orchestration, not browser/log/model payloads. Recipient metadata is not a signed ticket or transferable credential. Checks are point-in-time and hold no transaction lock; real delivery after later asynchronous work needs fresh recipient/consent enforcement at its transport boundary. Real service verification, consumer route/transport, bounded adapter timeouts and authenticated live evidence remain open. No deployed recipient registration, real clinical read, UI, database, model policy or cross-room acknowledgement is claimed.

## Evidence

11 focused tests cover immutable verified recipient results; model/browser/other-app/other-user denial; caller override/accessor refusal; changed recipient during read; consent withdrawal during final recipient lookup; grant/revision replacement; recipient deadline/final expiry/clock regression; recipient outages/accessors; input mutation capture; missing session/consent; and concurrent independent selected results.
338/338 local onboarding/runtime tests passed; diff check passed. The suite is registered in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 29, cancelled task authority.
