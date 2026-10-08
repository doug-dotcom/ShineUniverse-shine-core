# VC readiness — layer 10: identity and access proof

8 October 2026, Brisbane. Foundation baseline 5e0ebce82aa78da32472e6aa76ad8e265624afec.
After successful merge: 10/40 source-verified Foundation producer/acceptance layers; 30 remain (75%). Live consumer acceptance is separate.

## Enables Veteran Care

The new executable offline journey traverses the actual composed identity, verified token audience/subject, current session, exact resource/version, preparation, permission and finite expiry guards. It emits a readable JSON receipt of synthetic permitted/refused requests, reason codes and authority stages visited. Any assertion failure terminates nonzero.

Run: node foundation/onboarding/verify-veteran-care-access-v1.mjs

This closes the original map's joined identity/access proof outcome. Earlier individual tests and generic rules are reused, not counted again. No runtime decision envelope, audit logger, service execution or model handoff is introduced.

## Verified synthetic outcomes

| Scenario | Decision | Last authority |
| --- | --- | --- |
| Exact record/version and preparation | Allow | Permission |
| Unverified caller | Deny | App |
| Wrong verified audience or subject | Deny | Claims |
| Inactive current session | Deny | Session |
| Another veteran resource or changed version | Deny | Resource |
| Another veteran preparation | Deny | Preparation |
| Missing grant or another preparation grant | Deny | Permission |
| Multiple effective grants | Deny | Permission |
| Exact expiry or extended mutable dates | Deny | Permission |
| Defence not allowed | Deny | Permission |
| Authority outage | Deny/unavailable | Permission |
| Permitted independent reset | Allow | Permission |

16 scenarios passed. The same evaluator is reused with independent synthetic snapshots. Allow assertions bind exact owner/resource/version/request/grant/deadline and applied authorisation. Denials assert no request, grant ID or deadline output. All outcomes assert executionPerformed false. The machine receipt exposes no tokens or clinical content.

## Contract, owners and coordination

Producer foundation/onboarding/verify-veteran-care-access-v1.mjs; evidence contract shine-foundation/veteran-care-synthetic-access-proof-v1; branch foundation/vc-readiness-layer-10. Fresh-main workflow adds only this journey to Foundation contracts.
Foundation owns reusable producer composition and offline proof.
VC Integrations & Security owns real caller/session/metadata/preparation/consent projections, hosted requests, operation-time enforcement, consuming branch and deployment.
Shine AI owns caller admission/replay, context/model execution and AI consumer acceptance. This proof grants no private AI retrieval.

Reviewed VC 5bcdb04b8ceffdc9181a03083591fbbf94c70909, docs/VC-ROOM-INTERFACE-CONTRACT-20261008.md and docs/VC-L09-PRACTITIONER-ENFORCEMENT-20261008.md. Its practitioner database transaction evidence remains VC-owned; no repeated SQL checks or live Auth promotion here. AI tree e38b95769442bca90315e2719e6b7f5288aeec74 is unchanged from prior review. No VC/AI files, SQL, Auth users, credentials, records or deployments changed. Repository receipt is discoverable handover, not another active chat's acknowledgement.

## Evidence and open gates

Local Node 24: 16/16 journey scenarios and 151/151 existing onboarding/runtime checks passed. All ten composed dependency blobs match current Foundation main exactly. CI Node 22 runs the journey plus full Foundation and independent Defence checks before merge.
Synthetic JWT is deliberately unsigned and accepted only by fixture authority. No network/production authority is configured. Machine evidence explicitly sets hostedAuthenticationVerified, sharedServiceExecutionVerified and productionDeploymentVerified false.
This proves composition against controlled server responses, not hosted signature verification, actual service execution, practitioner verification or deployed connectivity. Consumers must provide independently trusted current projections and recheck authority at execution/delivery. Existing vc-permission-missing for an expired grant is preserved; no new denial vocabulary.
Open: actual hosted synthetic accounts, real server projections, consumer wiring and exact deployed allow/deny probes.
Next: layer 11, revocation propagation.
