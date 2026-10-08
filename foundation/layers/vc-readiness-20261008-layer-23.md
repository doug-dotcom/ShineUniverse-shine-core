# VC readiness — layer 23: private resource handle contract

8 October 2026, Brisbane. Baseline a1e22e303efe52d11e3db998ae2064e61847146d.
After merge: 23/40 source-verified producer layers; 17 remain (42.5%).

## Enables VC

createVeteranCarePrivateHandleService mints an opaque random UUID v4 reference after the layer-22 verified caller and fresh exact-record decision succeeds. The public handle contains only contract/version, random handle ID and deadline. Record identity, owner, grant and purpose remain in a server-private registry binding. Lifetime is at most five minutes and never beyond the permission deadline, including registry acknowledgement delay. An atomic insert-only acknowledgement is required; collisions, mismatched acknowledgement and failures withhold the handle.

Resolution requires a full new authenticated decision input. The existing caller/session/current grant/revision checks run before registry lookup. Every stored audience, caller, actor, owner, key/registration revision, exact record/version, capability, read operation/scope, purpose/preparation and grant must equal the fresh decision. New authenticated proof/request IDs are allowed; changed registration or grant needs a new handle. Unknown, malformed, expired and mismatched handles withhold metadata through one generic reason. Registry contents are captured without invoking accessors.

A successful resolution returns frozen server-private decision metadata, shortened to the handle deadline. executionPermitted and modelDisclosurePermitted remain false; requiresFreshExecutionCheck remains true. There are no record bytes, signed URLs, storage paths, fetch callbacks or model calls. A handle is a reference, not a bearer credential, and does not widen the current AI policy.

## Ownership and interface

Foundation owns this mint/resolve producer contract and reuses layers 21/22 without counting them again. VC Integrations owns the actual protected server registry, database/storage fetch and transport. AI owns recipient validation and model/context/tool/memory execution. Registry adapters insertPrivateHandle(row) and getPrivateHandle(handleId) must use a server-only, access-controlled, atomic insert-only registry; production identifiers use cryptographic randomUUID. Injectable ID/clock factories exist for server-controlled testing, never caller input. Registry failures leave any already inserted row to expire; cleanup and durable implementation remain consumer work.

mint accepts the exact layer-22 input. resolve accepts exactly {handleId,decisionInput}, with the same layer-22 authenticated request shape. Caller-supplied envelopes, grants, owner overrides and authority flags are rejected. Auth/request scalars are captured before asynchronous registry access. Metadata must remain inside trusted orchestration and must not be logged, sent to a browser or copied into model context.

This is point-in-time scope evidence, not transaction locking or authority to retrieve/disclose private content. A revocation during later asynchronous work still requires an execution/disclosure recheck at the real consumer boundary. Registry timeouts, durable cleanup, live consumer wiring, authenticated integration evidence and private AI policy approval remain open. No real registry, clinical fetch, database migration, AI policy, UI or deployment is claimed.

## Evidence

10 focused tests cover opaque metadata-only mint/resolve, credential requirement and extra-field refusal, revoked/stale grants, changed bindings, unknown/malformed rows, expiry/clock regression, insert collisions/acknowledgement errors, registry/caller failures, bounded configuration and distinct cryptographic default IDs.
285/285 local onboarding/runtime tests passed; diff check passed. The focused suite is included in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 24, L app binding.
