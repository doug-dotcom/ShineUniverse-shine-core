# VC readiness — layer 31: retry identity

8 October 2026, Brisbane. Baseline 03532c3668ba0b44e2e1856e0aa637757bb5a6c2.
After merge: 31/40 source-verified producer layers; 9 remain (22.5%).

## Enables VC

createVeteranCareRetryIdentityGate binds one supplied UUID operation ID to immutable selected-read identity: VC app, verified actor, L client, task, memory ID/version, preparation, read operation/scope, appointment purpose and internal server audience. It verifies the VC session before accessing the retry registry. A canonical SHA-256 fingerprint represents those ordered scalar fields. Neither credentials, content nor prior permission decisions are included.

The trusted registry must atomically insert this identity once or return the original immutable row for an existing operation ID. The evaluator compares the exact returned ID, fingerprint and every binding field. Reusing an ID for another owner, task, memory version or preparation is refused before private retrieval. Missing, conflicting, malformed or unavailable registry authority has no fallback.

A matching identity still executes the actual layer-29 task/recipient/memory pipeline from current credentials. It checks the verified owner again immediately before the private read. No previous success, cached grant, stored result or retry acknowledgement supplies permission. Cancelled tasks and withdrawn memory consent defeat subsequent retries without another private read. Credential refresh can preserve operation identity while current session, L user/link, consent, task and recipient verification run again.

Success returns retry-bound-result with frozen operation ID, fingerprint, identityReused, authorityRechecked true and resultReused false, alongside the existing private task-bound result. Matching retries may read fresh content; they are not cached result replays. Model disclosure and external transport remain closed.

## Ownership and interface

Foundation owns retry scope identity and exact acknowledgement validation. Existing session/task/recipient/memory guards are reused without additional credit. VC Integrations owns a protected durable atomic insert-only retry registry and real consumer wiring. Orchestration owns stable operation IDs across delivery retries and lifecycle cancellation. L owns selected read/database enforcement; AI owns actual tool/model invocation. This layer handles internal selected-memory reads, not business mutations or model calls.

Input is exactly {operationId,taskId,authContext,companionAuthContext,request,recipientAuthContext}, using the exact prior read/credential shapes. Caller fingerprint, replay flags, owner overrides and writes are refused. Scope and credentials are captured before awaits. Registry bindRetryIdentity receives exactly {operationId,fingerprint,binding} and returns exactly {status:'bound'|'existing',operationId,fingerprint,binding}. Binding fields must equal the requested independently verified scalar identity, not an arbitrary caller assertion. Conflicts must preserve the original binding rather than update it.

The registry stores scope metadata only: no raw credentials, private text, signed URLs, cached results or grants. It must protect identity/resource metadata from browser/log/model exposure. Fingerprints are equality checks, not secrets or bearer credentials. No expiry cleanup or production registry implementation is supplied here. A denied request may already have reserved its authenticated operation identity; that reservation grants no read authority. Revisions/grants/credential values are deliberately excluded from stable retry identity because every invocation rechecks them instead. The destination class is fixed; each actual recipient service/user must authenticate afresh.

Concurrent exact retries can share an identity and independently read after current checks. This contract does not deduplicate execution, provide an operation lease, return exactly-once results or guarantee single delivery. Side-effecting consumer operations require their own atomic execution ledger/lease and provider idempotency; this read-only layer must not be reused as that guarantee. Point-in-time checks hold no distributed transaction lock, and later disclosure still requires fresh authority.

Production retry registry, protected consumer routing, transport deadlines, actual task lifecycle and authenticated live retry evidence remain open. No database, deployed retry endpoint, AI tool dispatcher, UI or cross-room acknowledgement is changed.

## Evidence

10 focused tests cover stable exact identity with fresh checks; changed task/memory/version/preparation; cross-owner reuse; credential refresh without storing credentials/content; cancellation/consent withdrawal after binding; registry failure/mismatched ID/fingerprint/binding; fresh result rather than replay; authority/write/accessor refusal; mutation capture; and concurrent exact retries sharing one registry row while checking independently.
361/361 local onboarding/runtime tests passed, including the existing 25-assertion joined proof/witness tests; diff check passed. The suite is registered in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 32, resume recheck.
