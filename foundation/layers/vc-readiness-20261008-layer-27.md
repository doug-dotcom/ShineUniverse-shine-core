# VC readiness — layer 27: AI tool authority

8 October 2026, Brisbane. Baseline 4e927e9fc5bfdcf78eb848409df6c9bd16954938.
After merge: 27/40 source-verified producer layers; 13 remain (32.5%).

## Enables VC

createVeteranCareAIToolAuthorityEvaluator constrains a proposed AI tool call to veteran-care.selected_record_read with exactly recordId and recordVersion arguments. Unknown tools, writes, memory search, wildcard resource IDs, owner overrides and arbitrary argument fields are refused before policy lookup. One UUID tool call ID, the exact record selection and caller credential/proof scalars are captured before asynchronous work.

The evaluator builds the existing verified AI caller/exact fresh grant decision, then requires a current independent AI tool policy matching Foundation app, AI caller, service audience, tool/capability, read operation/scope and appointment purpose. The policy must be explicitly active, positively revisioned and bounded by a deadline. Default missing/disabled policy denies; a record grant does not enable a tool by itself.

An independent trusted AI proposal resolver must verify that the proposed call ID, record/version, appointment preparation, actor, caller/key and signed caller proof reference match the authenticated AI request. Model text, a JSON proposal, a proof reference or caller-asserted verified flag is never sufficient. The adapter is authority because it must independently perform that verification, not echo its query.

After policy/proposal checks, the evaluator rebuilds the fresh caller/grant decision and compares every original authority field except the newly generated request ID. It rereads current AI tool policy and rejects any change, then checks final expiry and clock monotonicity. Policy expiry can shorten the record grant deadline. Revocation, key/actor/grant/scope changes, policy withdrawal/revision change and authority outages withhold the entire envelope.

Success returns frozen server-private tool-scope-approved metadata, naming the exact proposed call and current tool policy revision. executionPermitted, toolInvoked and modelDisclosurePermitted remain false, and requiresFreshExecutionCheck remains true. This is an authority check for orchestrators, not tool execution or approval to send private clinical content to a model. No tool callback, tool result, clinical bytes or generated action is produced.

## Ownership and interface

Foundation owns scope joining and metadata. Layers 21/22 are reused without new credit. AI owns its current tool policy, independently authenticated signed proposal correlation, actual tool dispatcher and model/context authority. VC Integrations owns real consumer wiring and final protected read/disclosure enforcement. Neither AI policy nor another room's runtime is modified.

Input is exactly {authContext:{appToken,jwt},aiCallerProof:{proofRef},purposeContext:{preparationId},toolCall:{toolCallId,toolId,arguments:{recordId,recordVersion}}}. Tool ID is fixed to the selected record read capability; one proposed call is checked per invocation. No supplied permission envelope or execution flag is accepted.

getCurrentAIToolPolicy receives {foundationAppId,aiCallerId,actorShineId,toolId}, and returns exactly {status,foundationAppId,aiCallerId,targetServiceAppId,toolId,capabilityId,scope,operation,purpose,policyRevision,validUntil}. resolveVerifiedAIToolProposal receives that query plus callerProofRef,keyId,toolCallId,recordId,recordVersion,preparationId and returns exactly those fields plus verified true after independent authentication/correlation. Its lookup must be idempotent for already verified proof records; it must not create trust merely from a supplied opaque reference. Required adapters have no permissive fallback.

Metadata stays in trusted server orchestration, not browser/log/model payloads or transferable tickets. This point-in-time contract holds no transaction lock; actual tool execution and disclosure need fresh authority at their boundary. Current narrow AI policy is not expanded by this producer. Production policy/proposal adapters, consumer dispatcher wiring, task lifecycle/replay enforcement and authenticated live evidence remain open. Task cancellation is layer 29; no task authority is implied here. No consumer acknowledgement, deployment or live tool execution is claimed.

## Evidence

10 focused tests cover exact immutable tool metadata without invocation; unknown/write/search/override refusal before policy lookup; caller/consent failures; current policy identity/scope/revision; exact proposal correlation; in-flight grant withdrawal; policy withdrawal/revision/deadline change; bounded expiry; dependency exceptions/accessor refusal; and input mutation capture.
327/327 local onboarding/runtime tests passed; diff check passed. The suite is registered in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 28, result audience.
