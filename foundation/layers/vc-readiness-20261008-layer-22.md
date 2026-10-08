# VC readiness — layer 22: permission decision envelope

8 October 2026, Brisbane. Baseline aacba7557af06e200d66de6227297d4fffa5f31e.
After merge: 22/40 source-verified producer layers; 18 remain (45%).

## Enables VC

createVeteranCareAIDecisionBuilder joins the existing exact AI caller binder and fresh selected-record permission evaluator. One captured authContext is used for both; the independently verified Foundation actor must equal the record permission owner. Caller identity is resolved before private permission lookup. Missing/unverified AI identity or missing/revoked/stale/wrong-purpose grants withhold the entire envelope.

The frozen server-private envelope names audience shine.ai, Foundation/AI caller identities, actor/owner, caller key/registration revision/proof reference, request ID, exact resource/version, read capability/scope, purpose/preparation, grant and approved deadline. No credentials, record content or arbitrary caller data are copied. Expiry is checked again at the final decision boundary.

Decision allow-selected-read means the underlying Foundation record read check succeeded at that point only. executionPermitted false, modelDisclosurePermitted false and requiresFreshExecutionCheck true explicitly prevent treating it as an AI execution grant. The envelope is not signed, transferable or a bearer ticket. AI must independently authenticate/authorise any real request. Current narrow Adj overview policy does not accept private records; this producer metadata does not extend it.

## Ownership and interface

Foundation owns decision metadata and the joined actor/scope checks. Existing caller, permission and grant implementations are reused, not credited again. AI owns consumer validation and model/context/tool/memory execution; VC Integrations owns authoritative projections, actual transport and sensitive fetch/disclosure enforcement. No AI/VC policy, private retrieval, model provider path, credentials, database, UI or runtime deployment changes.

Server input is exactly {authContext:{appToken,jwt},aiCallerProof:{proofRef},request:{capabilityId,input:{recordId,recordVersion}},purposeContext:{preparationId}}. No caller-supplied actor, grant, audience or permission override is accepted. All scalar target/credential/proof values are captured before awaits. The same layer-21 current registry and independently correlated signed-proof authority remain mandatory dependencies.

Envelope must stay in trusted server orchestration, not a browser/log/model payload. Recipient must freshly revalidate actor/session, key/registration, grant/revision/expiry and scope at execution/disclosure after any asynchronous delay. This is point-in-time evidence without transaction locks, not consent to disclose clinical content externally. Real paired AI consumer integration and authenticated live evidence remain open; no producer/consumer acknowledgement claimed.

## Evidence

6 focused tests cover bounded immutable decision metadata; caller refusal before permission lookup; missing/revoked/stale/wrong-purpose grants; changing verified actor between binding/evaluation; final expiry/clock failures; caller mutation, extra scope fields and accessors.
275/275 local onboarding/runtime tests passed; diff check passed. Foundation and independent Defence CI required before merge; focused suite included in CI.

Next: layer 23, private resource handle contract.
