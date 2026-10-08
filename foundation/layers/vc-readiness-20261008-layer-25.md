# VC readiness — layer 25: memory scope enforcement

8 October 2026, Brisbane. Baseline 57750fc4973acb286b2da0d45741edf3217ca2be.
After merge: 25/40 source-verified producer layers; 15 remain (37.5%).

## Enables VC

createVeteranCareMemoryScopeEvaluator requires a fresh layer-24 same-user L link and a separate exact memory grant. It accepts a single UUID memory ID, positive integer version, read operation and UUID appointment preparation. It rejects writes, broad search, wildcard IDs and caller-selected owner/scope. The memory descriptor must match that ID/version, the authenticated owner and category veteran-care.context; the preparation must belong to that owner and veteran-care.appointment-preparation purpose.

A complete consent projection must have a nonnegative revision and at most 100 plain grants. Grants are captured before awaiting independent current revision authority. Exactly one active grant must match the VC app, companion client, owner, approved link ID/revision, memory ID/version, read operation, veteran-care.memory.read scope, purpose and preparation. Missing, stale, duplicate or withdrawn consent denies. A record grant never substitutes for memory consent. Immutable consent start/expiry must equal grant start/expiry; the approved deadline is shortened to the L link expiry.

The service rebinds the current L app/user/link after memory lookup and rejects any link/identity/revision/deadline change. It checks current memory permission revision again after that rebind, then checks the final server clock and consent window. Expiry, clock regression and exceptions withhold the envelope. Input target and credential fields are captured before waits, and registry/consent fields are read without invoking accessors.

Success returns frozen server-private metadata for that selected memory only. executionPermitted, modelDisclosurePermitted and memoryWritePermitted remain false; requiresFreshExecutionCheck is true. This is a permission scope decision, not retrieval or consent to copy memories into AI context. No content, memory search, SQL query, write, model call or private resource handle is produced. Read-only retrieval is layer 26.

## Ownership and interface

Foundation owns the scope evaluator and exact grant/revision contract; existing L binding is reused rather than credited again. L owns memory descriptors, independent user verification, protected memory storage and retrieval enforcement. VC Integrations owns actual consumer transport/current authority projections and deployment. AI owns any disclosure/model-context authorisation. This change does not add or deploy a memory database schema or extend another app's permissions.

Input is exactly {authContext:{appToken,jwt},companionAuthContext:{clientToken,userToken},request:{operation:'read',memoryId,memoryVersion,preparationId}}. Trusted adapters getMemoryDescriptor, getPreparationContext and getMemoryPermissionContext receive the exact app/client/owner/link/request/scope/purpose query. Descriptor is exactly {memoryId,memoryVersion,ownerShineId,category,status}; preparation is exactly {status,preparationId,ownerShineId,purpose}; permission context is exactly {complete,revision,grants}. getCurrentMemoryPermissionRevision receives {foundationAppId,clientId,ownerShineId} and returns those plus revision. Revisions must cover every consent change, without relying on an acknowledgement or caller timestamp.

Each grant contains exactly grantId,status,foundationAppId,clientId,ownerShineId,linkId,linkRevision,memoryId,memoryVersion,scope,operation,purpose,preparationId,notBefore,expiresAt,consentStartsAt,consentExpiresAt. Consent must come from trusted current authority, never an input envelope. Binding, memory IDs and scope evidence must remain inside trusted server orchestration and never be copied to browser/log/model payloads.

Point-in-time checks do not hold a transaction lock. Real retrieval/disclosure must freshly enforce scope at its execution boundary, including changes after this return. Real L memory consent projections, protected retrieval wiring, bounded adapter timeouts and authenticated live evidence remain open. No consumer acknowledgement, deployed memory access or live app behaviour is claimed.

## Evidence

12 focused tests cover selected immutable scope metadata; separate consent requirement; write/search/override/accessor refusal; descriptor owner/version/category; preparation ownership/purpose; every exact grant dimension; incomplete/stale/duplicate grants; withdrawn/changed link during evaluation; immutable deadlines/final expiry; consent snapshot capture and dependency outages; final revision withdrawal; and request mutation capture.
307/307 local onboarding/runtime tests passed; diff check passed. The suite is registered in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 26, read-only retrieval.
