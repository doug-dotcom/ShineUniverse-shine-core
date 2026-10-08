# VC readiness — layer 11: revocation propagation entry

8 October 2026, Brisbane. Source baseline ef08621c4edf3a71e94103e6baae8427d128a7c5.
After successful merge: 11/40 source-verified Foundation producer layers; 29 remain (72.5%). Consumer/live acceptance is separate.

## Enables Veteran Care

createVeteranCareRevocationService binds explicit withdrawal of one VC selected-record grant to the current dedicated-project identity/session, exact grant owner/app and registered scope/purpose. It invokes existing Foundation grant revocation semantics with server-generated request/event/revocation identifiers and time. An expired or previously revoked target does not need an active read grant to be withdrawn. AI/Defence availability cannot veto withdrawal.

Request: {authContext,request:{grantId,revoke:true}}. The request is exact plain data; no owner, app, date or event identity is accepted from it.
Mandatory trusted adapters: getGrantDescriptor({appId,ownerShineId,grantId}); revokeAccessGrant({eventId,revocationId,requestId,grantId,ownerShineId,appId,occurredAt}). Existing dedicated session and identity authorities are also mandatory.
Descriptor must match exact owner/grant/app, <VC slug>.record.read and <VC slug>.appointment-preparation. The write must re-enforce ownership/app at mutation time; a metadata read is not a lock or final authorisation.

## Persistence and propagation contract

The write adapter must confirm the exact grantId and requestId plus outcome revoked/already-revoked, bounded reason_code and outboxRecorded true, based on durable authoritative evidence. This is an additive consumer projection requirement; the old generic SQL return alone does not certify outboxRecorded. Do not fabricate it from UI, attempted writes or a generic HTTP success.
Reuse existing revoke_access_grant_v1 and its append-only grant_revocations/outbox mechanism. Adapter confirmation must establish the matching durable withdrawal and outbox event; already-revoked must establish the existing event. No new SQL or alternate revocation ledger is introduced.

Success contract shine-foundation/veteran-care-revocation-response-v1 reports requestId, status revoked/already-revoked, reasonCode vc-grant-withdrawal-recorded, propagationStatus outbox-recorded and consumerEnforcementVerified false. No internal owner, grant or revocation identifier is returned.
Failed/uncertain writes report not-verified and never claim a rollback or successful withdrawal. A commit may have occurred before a timeout; consumer reconciliation remains required. Caller request-ID retries are not introduced here (row 31).
Outbox-recorded is producer evidence only: not feed delivery, acknowledgement, cache eviction, in-flight cancellation or recall of delivered bytes. Those remain separate rows/consumer outcomes.

## Reconciliation and owners

Generic withdrawal, atomic outbox creation, app-scoped feed and acknowledgement existed before today. They are reused, not counted again. The actual new outcome is VC identity/session-bound owner withdrawal with exact correlation and a required durable propagation confirmation before success.
Foundation owns this reusable server producer wrapper, under foundation/onboarding/veteran-care-revocation-v1.mjs. Branch foundation/vc-readiness-layer-11. Only additive onboarding files, fresh-main workflow and this receipt change.
VC Integrations & Security owns descriptor projection, transactional write/outbox confirmation, consumer branch, real credentials and session checks at sensitive mutation, local VC-sharing withdrawal, feed consumption and live acceptance. VC sharing grants are distinct from Foundation grants: revoking one does not silently revoke the other.
Shine AI owns its consumption/enforcement and caller/model controls. No private AI retrieval or acknowledgement is authorised by this producer receipt.

Reviewed VC 35a7593993e44bcb6d4fdd6ca52f89707ccfa3e6, docs/RECORD-SHARING.md; existing VC owner revocation, retained originals and signed-link/download limitations remain VC-owned. Read Foundation generic revocation/feed modules, grant-revocation-v1.sql, persistence-v1.sql and historical layer-017 receipt. Historical live claims are not freshly verified today. No database/Auth/Storage or VC/AI source changed. Repository handover is discoverable coordination, not another room's acknowledgement.

## Verification and open gates

14 new focused tests passed; full local onboarding/runtime suite 165/165 passed; joined synthetic access journey 16/16 still passed.
Tests cover exact mutation arguments, current session/audience refusal, cross-owner/app/grant/scope/purpose rejection, explicit exact request, caller override rejection, expired/idempotent targets, no inferred acknowledgement, wrong/missing persistence correlation, unknown commit, metadata outage, bad server IDs/clocks, input mutation and concurrent invocation isolation.
Synthetic authorities only. Existing generic service is imported unchanged. CI includes new tests; Foundation and Defence success required before merge.
Open: real descriptor and durable outbox confirmation projection, consumer wiring, hosted synthetic withdrawal/feed delivery, operation enforcement and deployment. No authenticated shared-service or live propagation proof claimed.
Next: layer 12, revocation acknowledgement.
