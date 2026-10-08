# VC readiness — layer 21: Shine AI caller binding

8 October 2026, Brisbane. Baseline 9ea5cbf0d49b5bac0d221b52dc4d57a0d006431a.
After merge: 21/40 source-verified producer layers; 19 remain (47.5%).

## Enables VC

createVeteranCareAICallerBinder maps the exact Foundation identity shine.veteran-care to AI's existing dedicated caller shine-veteran-care and target service shine.ai. Existing Foundation dedicated-project identity/audience/current-session verification is reused. Current server registration must name that exact pair, active state, positive revision and dedicated key ID. No email matching or borrowed Fish/Wellness caller.

An opaque proofRef is resolved by a mandatory independent trusted authority. It must return verified signed caller evidence correlated to this exact Foundation actor/app, AI caller, registered key and proof handle. Handle or caller-supplied identity alone never suffices. Output is frozen binding metadata with executionPermitted false; no secret/JWT/private record, model call, signed request or permission ticket is produced.

Inputs and registration fields are captured before asynchronous work to prevent caller/shared-object mutation from changing the binding. Missing, mismatched or unavailable authority withholds the binding.

## Producer/consumer interface and ownership

Foundation owns the reusable binder in foundation/onboarding/. getAICallerRegistration({foundationAppId,actorShineId}) must read current authoritative registration. resolveVerifiedAICallerProof({foundationAppId,actorShineId,proofRef,aiCallerId,keyId}) must independently verify/resolve the actual AI signed caller and correlate its server request to the supplied Foundation principal; it must never trust a browser-provided handle as evidence. The adapter owns key validity, signed-request freshness/replay state and request correlation. No such real adapter is claimed implemented here.

Shine AI owns signing/authentication/policy/model execution and its official client. VC Integrations & Security owns issuance, server-side credential lifecycle/storage and consumer transport. Adj owns actual caller construction and DVA conversation. No HMAC implementation, AI policy/profile activation, credentials, VC/AI repository, private memory scope or provider route is created here.

Current AI policy source inspected: app/security/policy.py blob 06c4995f102e9640163e8c0090bfc0c4ffcd712e. It uses shine-veteran-care and requires a dedicated keyring principal; overview execution depends on intentional bootstrap/policy activation. Read dedicated-credential, overview contract and execution-wiring handovers. Earlier caller-readiness inventory is historical; newer policy source governs this mapping. No profile fingerprints are invented or copied into Foundation authority.

This is point-in-time metadata binding. Consumers must revalidate registration/key/session/freshness at actual execution, and AI independently authenticates its signed request. The binder does not declare AI execution authorised, impersonate a veteran in the AI request, establish private retrieval authority or open a closed AI profile. Hosted signed caller acceptance and actual adapter integration remain open. Receipt is discoverable handover, not another room's acknowledgement.

## Evidence

7 focused tests cover exact pair, borrowed caller/wrong service/revoked registration, mismatched actor/key/handle, absent proof/outage, inactive session, caller/registration mutation and accessor rejection.
269/269 local onboarding/runtime tests passed; diff check passed. CI includes the new suite. Foundation and independent Defence CI required before merge.

Next: layer 22, permission decision envelope.
