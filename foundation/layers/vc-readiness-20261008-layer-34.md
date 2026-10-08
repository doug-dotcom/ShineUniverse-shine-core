# VC readiness layer 34 — credential references

Baseline: d22b436855e0c73bb3dcf3875ae2c1c712f119c4 (layer 33 merged).
After merge: 34/40 complete; 6 remaining (15%).

## Behaviour

createVeteranCareCredentialReferenceGate accepts exactly {checkpointId,credentialReferenceId,authContext}. Fresh VC authentication remains mandatory; a saved opaque reference replaces supplied Companion and recipient credentials, never the user's current session. Foundation verifies the actor before looking up protected reference metadata, then requires an exact active same-owner/app reference for veteran-care.resume and vc-trusted-server. Only its current revision may resolve internally.

The trusted resolver supplies fresh Companion client/user and VC recipient credentials into the actual layer-32 resume pipeline. All current session, Companion user/link, consent, existing retry, checkpoint, task and recipient verification still runs. No reference is a bearer token or grant. Reference fields are captured and checked again immediately before private retrieval and after the pipeline; rotation, revocation, changed binding or expiry prevents a read or withholds prepared content. Invalid/regressing clocks and adapter failures fail closed with generic reasons.

Successful credential-reference-result contains the existing private VC server result plus frozen reference ID/revision/deadline metadata, credentialsReturned false and requiresFreshCredentialResolution true. Recipient/checkpoint/reference deadlines are bounded by reference expiry and all downstream authority. No resolved tokens appear in result metadata, saved checkpoints or retry rows. Model disclosure and external transport remain closed. Each invocation resolves again; no secret, prior success or permission is cached.

## Ownership and interfaces

Foundation owns exact reference validation and fresh guard composition. VC Integrations/Security owns protected metadata storage, vault resolution, encrypted credential custody, rotation/revocation and real service authentication. getCurrentCredentialReference receives exactly {credentialReferenceId,foundationAppId,ownerShineId,purpose,audience} and returns exactly those fields plus {status,revision,validUntil}. A current reference is active with positive safe-integer revision and an unexpired deadline.

resolveCredentialReference receives that query plus current revision and returns exactly {credentialReferenceId,revision,companionAuthContext,recipientAuthContext}, using the prior exact token shapes. It must authorise the trusted calling service and actor-bound lookup, enforce revision, purpose and audience, and refuse revoked/unavailable credentials. Only opaque random reference IDs belong in saved orchestration metadata. Raw tokens belong in the protected vault and temporary server execution memory; they must never be logged or placed in browser/model output. The server auth context is transient, not stored with the reference. The resolver is a trusted capability and cannot be sandboxed by this JavaScript wrapper.

Downstream independent verifiers still authenticate resolved Companion/user/service tokens; vault ownership metadata alone is insufficient. A reference can support multiple same-user checkpoints only where each original retry binding and current checkpoint/task/consent independently permits the selected resource. Reference issuance, vault storage and scheduler persistence are not implemented here. Layers 32/33's exact checkpoint schema is unchanged and rejects raw credential fields; this layer adds a consumer wrapper rather than storing secrets in checkpoints.

Credential rotation requires the protected adapter to change revision or revoke the row; an in-flight old revision is withheld. Checks remain point-in-time without a distributed lock; later disclosure needs fresh authority. Production vault integration, encrypted custody, service permissions, live rotation evidence and consumer wiring remain open. No real credentials or live database are accessed.

## Evidence

12 focused synthetic adapter tests cover internal resolution/output redaction; missing/revoked/wrong-owner/app/purpose/audience metadata; malformed resolution and accessor refusal; all current session/Companion/recipient/task/consent dependencies; rotation/revocation before read; withdrawal after read; fresh resolution after rotation; expiry/deadline/regressing clocks; caller credential/authority/URL refusal; captured input; vault outage redaction; and resolved-secret mutation during downstream awaits.

395/395 local onboarding/runtime tests passed, including the joined synthetic AI/L proof. Diff check passed. The test is registered in Foundation CI; Foundation and independent Defence checks must pass before merge. This is source-level synthetic evidence, not certification of a deployed vault or live credential flow.

Next: layer 35, capability health.
