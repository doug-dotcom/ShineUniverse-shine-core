# VC readiness — layer 29: cancelled task authority

8 October 2026, Brisbane. Baseline 84d1455d08bfc47d08ffd5fb86a4615d6f2763a5.
After merge: 29/40 source-verified producer layers; 11 remain (27.5%).

## Enables VC

createVeteranCareTaskAuthorityGate wraps the existing selected-memory and verified-recipient pipeline in current task lifecycle checks. It verifies the VC session, then requires an independently current task projection matching task ID, VC app, authenticated owner, exact memory ID/version, appointment preparation/purpose and read operation. Only running tasks with a positive revision and unexpired deadline qualify. Queued, cancelled, superseded, completed, missing and mismatched tasks provide no authority.

Task authority is checked three times: before entering the recipient/retrieval pipeline, immediately before invoking the actual private read adapter, and after the audience-bound result is prepared. Every task field, revision and deadline must remain identical. Cancellation during recipient/permission lookup prevents the actual content read. Cancellation during the read or final preparation withholds the private result. A changed running revision, replacement or extended deadline cannot inherit old task authority. Retrying a cancelled task queries current state and performs no further read.

The gate reuses layer-28 recipient and memory consent enforcement; task state does not replace either. It bounds the final result and recipient deadline to task expiry and checks a monotonic final server clock. Success returns a frozen task reference/revision/deadline with task-bound-result and requiresFreshTaskCheck true. The result remains server-private; modelDisclosurePermitted is false and transportPerformed is false. No task is started, cancelled, completed, resumed, dispatched or written by this evaluator.

## Ownership and interface

Foundation owns the current lifecycle gate and exact scope joining. Layers 24–28 are reused without additional credit. VC/AI orchestration owners maintain real durable task state, lifecycle transitions and current projections; cancellation or supersession must durably change state/revision before an acknowledgement. L owns the selected read adapter. VC Integrations owns recipient authentication and final transport enforcement. AI owns tool/model dispatch and must apply equivalent current task checks at its actual execution boundary.

Input is exactly {taskId,authContext,companionAuthContext,request,recipientAuthContext}, using the existing exact layer-28 credential/read request shapes. Task ID and memory/preparation IDs must be UUIDs, memory version a positive integer, operation read. Caller status/revision/owner/task envelopes and write overrides are rejected. All request/credential scalars are captured before awaits.

getCurrentVCTask receives {taskId,foundationAppId,ownerShineId,memoryId,memoryVersion,preparationId,purpose,operation} and returns exactly those fields plus status,revision,validUntil. It must consult current durable authority, never echo a requested running state or use a queued snapshot/cache as proof. Plain task fields are captured without invoking accessors; exceptions and missing authority fail closed. No task/provider details or private dependency exception are returned on refusal.

Actual readPerformed tracking in this gate records whether the protected read adapter was invoked, including failed reads. A task cancelled at the immediate read boundary is denied with retrievalPerformed false even though an enclosing preparation callback was entered. This layer does not claim it can abort an already running database read; it suppresses release. Trusted callbacks must not disclose or perform writes/model calls before final checks, and cannot be sandboxed by this factory.

Checks hold no transaction lock across separate authorities. A cancellation after the last task read, or recipient/consent change during later asynchronous work, still requires fresh task/consent/recipient enforcement at the real execution/disclosure boundary. Transactional task leases, queue scheduling, abort propagation, bounded adapter timeouts, live task store/consumer wiring and authenticated evidence remain open. Existing AI tool scope metadata grants no execution by itself; no live AI dispatcher is modified. No deployed cancellation endpoint or cross-room acknowledgement is claimed.

## Evidence

10 focused tests cover exact immutable running-task result; cancelled/superseded/completed/queued/missing task refusal; task owner/app/memory/version/purpose/preparation/revision matching; cancellation before content lookup; cancellation during read; running revision/deadline replacement; cancelled-task retry without another read; task deadline/clock regression; outages/accessors; and caller override/mutation capture.
348/348 local onboarding/runtime tests passed; diff check passed. The suite is registered in Foundation CI; Foundation and independent Defence CI must pass before merge.

Next: layer 30, joined VC–AI–L proof.
