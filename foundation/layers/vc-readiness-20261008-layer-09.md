# VC readiness — layer 09: grant expiry enforcement

8 October 2026, Brisbane. Source baseline: be72be9afd09c231e22c4b8542f0aef3b854e5b9.
After successful merge: 9/40 source-verified Foundation producer layers; 31 remain (77.5%). Consumer/live acceptance is separate.

## Enables Veteran Care

createVeteranCareExpiringPermissionEvaluator composes the purpose-bound identity/resource/permission chain with a mandatory finite grant-window policy. It requires notBefore and expiresAt to exactly match a separately persisted reviewed consentWindow {startsAt,expiresAt}; start must precede expiry. Dates must be canonical UTC millisecond ISO strings, with real calendar validity. Missing/null/unlimited, malformed, noncanonical or changed grant windows cannot allow this path. No default duration is invented.

The approved interval includes its start and excludes its exact expiry. Grant time is evaluated after permission lookup and the selected deadline is checked again just before returning allow. Invalid or regressing completion clocks fail closed. Success includes permissionValidUntil equal to the approved deadline, with executionPerformed false.

Reconciliation: generic Foundation permission logic already rejects expired/not-yet-active/revoked grants, and layer 07 already evaluates time after lookup. Those outcomes are reused, not counted again. The new gap closed here is unlimited or consent-divergent grant windows plus a completion-bound deadline check. Existing generic engine stays unchanged.

## Exact contract and ownership

Producer: foundation/onboarding/veteran-care-grant-expiry-v1.mjs, version 1. Isolated branch foundation/vc-readiness-layer-09.
New named factory enforces the fixed policy; constructor options cannot replace it. Previous audience/resource/permission factories retain their narrower contracts and do not certify the new finite-window outcome.

Permission-context projection adds consentWindow {startsAt,expiresAt} for every candidate grant. It must be the immutable independently persisted reviewed approval snapshot, not copied from current mutable grant dates, UI controls or request input. Existing grant notBefore/expiresAt must match that snapshot exactly. Neither shortening nor extension is silently accepted; a changed interval requires the consumer's separately authorised consent workflow.
Timestamp projection must normalise authoritative dates to canonical UTC before passing the contract. This does not edit or overwrite stored dates or choose a duration.
Output permissionValidUntil is only the grant permission deadline, not a token/session validity guarantee, signed ticket, promise against later revocation or permission to execute. Consumers must recheck current identity/session/resource/preparation/grant/Defence state at sensitive execution and delivery. Already delivered bytes cannot be recalled.

Foundation owns the reusable window policy and server producer composition.
VC Integrations & Security owns actual consent snapshot/authoritative grant projection, consuming branch, consent workflow, sensitive-operation enforcement, live expiry probes and deployment.
App/Passport retains duration display and confirmation ownership. Shine AI retains service admission and private handoff checks. No VC/AI files, SQL, grant dates, credentials or record data changed.

## Coordination

Reviewed current VC 6a9d9164491414373aedf06299f18784d2cb40c1, docs/RECORD-SHARING.md blob 9949fd36d8865e389d30b285d4f00b45195bfa88. Its server snapshots, non-extension, fresh-confirmation and live-clock sharing policy remain owned by Integrations & Security. This Foundation producer policy does not reimplement those VC SQL/browser outcomes. Signed-link residual validity and downloaded-copy limitations remain separate consumer realities.
Repository receipt is discoverable handover, not acknowledgement by another active room.

## Verification and open gates

Command: node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
151 passed, 0 failed, including 13 new window tests. After the final nonnegative-clock and constructor-override tightening, the 42 focused expiry/permission/purpose tests passed again.
Synthetic claims/session/resource/preparation/grant snapshots only. Tests cover inclusive start/exclusive end, missing/unlimited dates, divergence from approved interval, invalid/noncanonical/calendar dates, exact snapshot data, guarded deadline output, old unbounded grants, expiry during lookup and before return, clock regression/failure, forged caller dates, inactive history and fixed-policy constructor enforcement.
Foundation CI includes the new suite; Foundation and Defence workflow success are required before merge.

Open: real persisted consent-snapshot projection, consumer wiring, actual current shared-service grant expiry tests, operation/delivery checks and exact deployed acceptance. No hosted/private-browser or production deployment proof is claimed.
Next: layer 10, identity and access proof.
