# VC readiness — layer 12: revocation acknowledgement status

8 October 2026, Brisbane. Source baseline 037c4dc110739d24ab3cbf7ec3ef9aeeb4f8c45f.
After successful merge: 12/40 source-verified Foundation producer layers; 28 remain (70%). Live consumer acceptance is separate.

## Enables Veteran Care

createVeteranCareRevocationStatusReader provides an owner-scoped, read-only status for one exact Foundation VC selected-record grant. It composes current dedicated-project identity/session checks with authoritative withdrawal, served-delivery and acknowledgement evidence. It distinguishes not-recorded, withdrawal-recorded, delivered and acknowledged without granting access or performing acknowledgement writes.

Request {authContext,request:{grantId}} is exact plain data. Owner/app come from current verified authority, never browser input. No private identifiers or sequence/checkpoint values are returned in the status response.
Output contract shine-foundation/veteran-care-revocation-status-v1 reports derived status, reasonCode vc-revocation-status-verified, acknowledgementVerified only for a correlated durable acknowledgement, and consumerEnforcementVerified always false. Denied/unavailable outcomes withhold positive verification.

## Exact trusted projection contract

Mandatory getGrantRevocationEvidence({appId,ownerShineId,grantId}) must return a complete coherent authoritative read, not UI state, feed fetch success or generic checkpoint metadata.
Common fields: complete true, matching grantId/appId/ownerShineId, scope <VC slug>.record.read and purpose <VC slug>.appointment-preparation.
withdrawal is {status:'not-recorded'} only when absence has been authoritatively established; delivery and acknowledgement must then be explicit null. Otherwise withdrawal is {status:'recorded',sequenceNo:positive safe integer} for that exact grant's outbox event.
delivery is explicit null if not yet served; otherwise {deliveryId,appId,afterSequence,sequenceNos}. Its strictly increasing 1–100 safe positive sequences must be after afterSequence, app-scoped and contain the exact withdrawal event. Sparse global sequences are valid.
acknowledgement is explicit null if not yet recorded; otherwise {deliveryId,appId,requestId,outcome,sequenceNo,checkpointSequence}. It must match the served receipt/app, target that batch's terminal sequence, have outcome advanced/already-acked and a durable checkpoint at or beyond that terminal. Missing, incomplete or contradictory evidence cannot become a positive acknowledgement.
Projection must join existing grant/outbox/delivery/ack records consistently and retain existing SQL coverage and app-isolation checks. This wrapper checks correlation; it does not independently reconstruct all historical app-specific pending events or replace SQL coverage validation.

## Meaning and reconciliation

Existing Foundation feed/delivery receipts and ack_app_revocations_v2 already enforce recorded batch coverage/checkpoints. They are reused and unchanged. The new outcome is a VC identity-bound per-grant read that requires correlated evidence before exposing an acknowledgement status.
An app acknowledgement is a recorded consumer assertion, not independent cache eviction, execution cancellation, Storage link invalidation or deletion of downloaded copies. The output intentionally cannot certify those outcomes. not-recorded never implies a valid grant or permission to access.
No new audit ledger, acknowledgement mutation, runtime permission envelope, UI or deployment is introduced.

## Ownership and coordination

Foundation owns the reusable read projection validator under foundation/onboarding/veteran-care-revocation-status-v1.mjs. Branch foundation/vc-readiness-layer-12. Fresh-main workflow only adds its test suite.
VC Integrations & Security owns coherent persisted evidence projection, consuming branch, exact Auth/runtime wiring, local VC-sharing state, feed consumption and actual enforcement/hosted acceptance. Foundation grants remain distinct from local VC sharing grants.
Shine AI owns its consumer acknowledgement and enforcement, caller/replay/model/context controls. No AI acknowledgement is inferred here.
VC current tree d1ff324e7010c60c7d3ef90a3287dfe2baec985a; room-interface contract blob f7c9593f09a6a8eb7c531c942bf27f63d6dd85d4 is unchanged from the previously read single-owner contract. AI tree e38b95769442bca90315e2719e6b7f5288aeec74 is unchanged from prior review. Read current generic revocation-ack module and revocation-delivery-receipts SQL. No VC/AI, generic gateway/SQL, credentials or database/Auth/Storage writes. Repository receipt is discoverable handover, not cross-chat acknowledgement.

## Verification and open gates

14 focused new tests passed; 179/179 full local onboarding/runtime checks passed; the 16-scenario joined synthetic access journey still passed.
Coverage: four lifecycle states, exact owner/app/grant/scope/purpose, active-session/audience refusal, complete evidence, exact plain requests, ordered sparse batch coverage, missing/reordered/cross-app receipts, wrong ack correlation/checkpoints, already-acked later checkpoint, forged consumer flags, outages, caller mutation and accessor rejection.
Synthetic authorities only. CI adds the suite alongside existing checks; Foundation and independent Defence success required before merge.
Open: real coherent persisted projection, hosted per-grant status journey, consumer enforcement probes and deployment. No fresh live acknowledgement or cross-service enforcement proof claimed.
Next: layer 13, stale-grant cache rejection.
