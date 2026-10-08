# VC readiness — layer 15: delegated-access contract

8 October 2026, Brisbane. Baseline 4a11860 (merged layer 14).
After merge: 15/40 source-verified producer layers; 25 remain (62.5%).

## Enables VC

A server-only delegated scope builder verifies the actual carer/provider caller using the existing dedicated-project identity, audience and current session path. It retains actorShineId and ownerShineId separately; no caller-selected veteran identity replaces the authenticated actor. Self-access must use the existing self path.

The uncached getDelegationContext adapter must project current authoritative delegation and resource metadata together. A relationship label alone never suffices. The exact app, actor, owner, record/version, appointment preparation, read operation, scope and purpose must match an active delegation with a positive revision and future server-millisecond deadline. Current resource ownership/category/version must also match. Missing, revoked, expired, mismatched or unavailable authority withholds the scope.

Input selection and credentials are captured before asynchronous verification. Output is a frozen shine-foundation/veteran-care-delegated-scope-v1 metadata contract with executionPermitted false and authorizationApplied false. It deliberately omits the self-access shineId field. No record content, bearer credential, signed link, transferable permission ticket or clinical/provider verification is returned.

## Ownership and limits

Foundation owns the builder and contract. VC Integrations & Security owns authoritative delegation/resource projections, actual permission and Defence enforcement, atomic fetch/disclosure and consuming integration. Consumer must not relabel this contract as a self-access request. Scope-ready is not permission-allowed: fresh permission/Defence, expiry/revocation and transport-boundary checks remain mandatory before any disclosure. This contract does not create authority, edit consent, certify a clinician or verify DVA appointment/payment eligibility.

No VC app, database, Auth/Storage, model or deployed runtime changes. CI workflow adds the new test to the existing suite; no other room's implementation is counted. Repository receipt is a discoverable handover, not acknowledgement from another chat.

## Evidence

8 focused delegation tests passed, including both relationships, exact-field substitution refusals, wrong resource owner/version/category, revoked actor session, self-access refusal, forged extra fields/accessors, authority outage, clock regression, expiry during lookup, repeated revocation checks and mutation during await.
234/234 local onboarding/runtime tests passed. Existing synthetic access journey 16/16 passed. git diff --check passed.
Foundation and independent Defence CI must pass before merge. These are offline synthetic outcomes; consumer integration and live authenticated delegated disclosure are open.

Next: layer 16, read/write separation.
