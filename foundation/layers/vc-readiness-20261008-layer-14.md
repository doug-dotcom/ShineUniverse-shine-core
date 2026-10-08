# VC readiness — layer 14: in-flight permission recheck

8 October 2026, Brisbane. Baseline 69d7ff34b205b55661786de575ffdcf9b317f029.
After successful merge: 14/40 source-verified Foundation producer layers; 26 remain (65%). Live consumer acceptance is separate.

## Enables Veteran Care

createVeteranCareGuardedRead brackets trusted server-private preparation with two independent full createVeteranCareFreshPermissionEvaluator evaluations. A request permitted at admission loses its prepared result if current identity/session/resource/preparation/grant/Defence/expiry/revision checks subsequently refuse or become unavailable.
Even a second allow must retain the initial exact app/owner/capability/read scope/resource/version/purpose/preparation/grant and approved deadline. A replacement valid grant cannot silently authorise previously prepared work. Server-generated request IDs may differ between checks; they do not expand scope.
Final release clock rejects expiry and invalid/regressing time before returning. An already elapsed grant deadline stops preparation.

Input is captured plain exact {authContext:{appToken,jwt},request:{capabilityId,input:{recordId,recordVersion}},purposeContext:{preparationId}}. Caller mutation during awaits cannot change target or credentials. These server credentials are never passed to prepareResult.
Mandatory prepareResult({request,grantId}) receives verified frozen scope and remains trusted server-private work. It must not disclose bytes, issue usable signed links, call an external model/recipient or otherwise release data before the final gate. It must prepare only the exact authorised read result, not perform writes. The wrapper cannot undo effects of a misbehaving adapter.

Successful contract shine-foundation/veteran-care-guarded-read-result-v1 returns status release-ready, preparationPerformed true, resultReturned true and the prepared result. This is a server return boundary, not proof of HTTP delivery, AI invocation or hosted execution.
Refused/unavailable outcomes contain no result, and distinguish whether private preparation was attempted. They do not falsely report that prepared work never occurred. No retry, portable permission ticket or remote cancellation is introduced.

## Limits and ownership

Rechecks are point-in-time. This function does not implement a database transaction lock against a change after the last authoritative read. Consumers must bind actual sensitive fetch/disclosure to current authority at their execution/transport boundary and repeat checks after any further asynchronous delay. Streams require checks during delivery; previously delivered bytes cannot be recalled.
Foundation owns reusable orchestration under foundation/onboarding/veteran-care-guarded-read-v1.mjs. Branch foundation/vc-readiness-layer-14.
VC Integrations & Security owns actual private fetch/preparation, authoritative projections, transactional operation/disclosure enforcement, consuming branch and live checks. App/UI ownership remains untouched.
Shine AI owns actual model calls, context/memory consumers and cancellation. Private preparation here cannot be used as an external AI handoff; later authorised handoff rows remain separate.

Existing admission, expiry and revision checks are reused, not counted again. The new outcome is an enforceable withheld-result path after a second complete evaluation around asynchronous private work.
Current VC tree 71b47940df269d091f2be979c5761fcecd61428e; no VC/AI, SQL, credentials, Auth/Storage or deployment change. Previously read single-owner interface applies. Repository receipt is discoverable handover, not another chat's acknowledgement.

## Evidence and open gates

12 new focused tests passed; final full local onboarding/runtime suite 204/204 passed. Existing joined synthetic access journey 16/16 passed before final clock tightening; final CI also runs that unchanged journey.
Coverage: stable two-evaluation return, initial refusal/no preparation, revocation and stale cached context during work, session deactivation, changed resource/preparation, replacement valid grant, authority outage, exact expiry at final boundary, invalid/regressing clocks, failed preparation, captured caller mutation and accessor rejection.
Only synthetic private result and authorities. Foundation and independent Defence CI required before merge.
Open: real consumer private-read integration, operation/transport atomicity, hosted in-flight withdrawal and exact deployed acceptance. No production disclosure or live enforcement proof claimed.
Next: layer 15, delegated-access contract.
