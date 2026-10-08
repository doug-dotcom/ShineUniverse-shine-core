# VC readiness layer 32 — resume recheck

Baseline: 66ddb7f79ad68778525d01fb39bb34c47c0f98ab (layer 31 merged).
After merge: 32/40 complete; 8 remaining (20%).

## Behaviour

createVeteranCareResumeRecheckGate accepts only a checkpoint ID and fresh VC, Companion and recipient credentials. A protected current checkpoint supplies the operation/task/selected-memory/version/preparation identity. Stored progress is never permission. The gate requires an existing matching layer-31 retry identity and runs the actual current session, Companion user/link, selected-memory consent, task and recipient pipeline again. Missing retry identities are refused rather than reconstructed from a checkpoint.

Checkpoint ownership/app, resumable status, selected-memory-read stage, positive revision, exact resource identity and expiry are checked initially, immediately before the private read and after the resulting authority checks. Every checkpoint field must still match. Changed, cancelled, expired or superseded progress prevents a read or withholds an already prepared result. The output deadline is bounded by checkpoint and downstream authority deadlines. Invalid/regressing clocks, adapter failures and malformed/accessor-bearing inputs fail closed without returning private exception details.

Success returns resume-rechecked-result with frozen checkpoint metadata, checkpointAuthorityReused false and requiresFreshResumeCheck true. Private text remains confined to the verified VC trusted server; model disclosure and external transport remain closed. No stored credentials, content, permission envelope or caller-supplied selection can define a resume.

## Ownership and interfaces

Foundation owns exact checkpoint validation and current authority composition. VC Integrations owns getCurrentResumeCheckpoint({checkpointId,foundationAppId,ownerShineId}) and its protected durable storage. Its row contains exactly {checkpointId,foundationAppId,ownerShineId,operationId,taskId,memoryId,memoryVersion,preparationId,stage,status,revision,validUntil}. A current resumable row is progress metadata only; it must contain no credentials, grants, private text or cached results.

getExistingRetryIdentity({operationId,foundationAppId,actorShineId}) returns exactly {operationId,fingerprint,binding} from the original immutable retry registry. Foundation validates its fingerprint and complete binding against the freshly verified actor and checkpoint selection. This adapter is lookup-only; it must not insert or replace an absent identity.

Orchestration owns pause/resume transitions and checkpoint lifecycle. The existing task must already be running; this layer does not change task state, write checkpoints, acquire leases or provide exactly-once execution. Concurrent matching resumes may each perform a fresh read. Checks are point-in-time and hold no distributed transaction lock. A later disclosure requires another current authority check. L owns actual selected-read enforcement. Live checkpoint/retry storage, task scheduling, protected consumer wiring and authenticated resume evidence remain open. No database or deployed endpoint is changed.

## Evidence

10 focused synthetic adapter tests cover valid current resume; missing/corrupt/completed/superseded checkpoint; wrong owner/app or changed selection; absent/forged retry row; cancellation, withdrawn consent and wrong Companion user; checkpoint change before read; checkpoint change after read with result suppression; expiry/deadline/regressing clock; strict input capture/accessor refusal; and adapter outage redaction.

371/371 local onboarding/runtime tests passed, including the joined synthetic AI/L proof. Diff check passed. The new test is registered in Foundation CI; Foundation and independent Defence checks must pass before merge. These are source-level synthetic checks, not live integration evidence.

Next: layer 33, checkpoint failure.
