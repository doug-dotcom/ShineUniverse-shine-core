# VC readiness — layer 20: joined revocation proof journey

8 October 2026, Brisbane. Baseline bcc92296fc92ee0f77d17ed09a4ef0b8d19d4f76.
After merge: 20/40 source-verified Foundation producer/acceptance layers; 20 remain (50%). This is halfway through the sprint, not halfway to clinical readiness.

## Enables VC

A reproducible offline acceptance runner joins the actual Foundation VC fresh-permission evaluator, revocation producer, generic app-scoped feed and acknowledgement services, and exact-grant revocation status reader against one isolated synthetic authority state. Two separate VC evaluator instances initially allow the same exact record/preparation grant.

The withdrawal adapter changes grant state, advances the authoritative revision and records a synthetic outbox entry. Consumer A retains its cached active snapshot and refuses it as stale. Consumer B freshly sees the revoked grant and refuses permission. Both remain blocked after feed delivery and correlated acknowledgement. A mismatched delivery acknowledgement is refused. Outbox persistence and acknowledgement never assert private consumer enforcement.

15 assertions form one joined stateful sequence rather than isolated retests. Structured readable receipt: foundation/layers/vc-readiness-20261008-layer-20-proof.json. Runner: node foundation/onboarding/verify-veteran-care-revocation-v1.mjs. Reused layer 11–13 implementations are not credited again; layer 20 is the planned joined acceptance outcome and reproducible regression proof.

## Ownership and limits

Foundation owns this producer/acceptance harness. Its two consumers are isolated instances of the VC evaluator in one process, not two deployed services/apps or real recipients. The one app-scoped feed is not relabelled as cross-app fan-out. All storage/transport authorities are in-memory synthetic adapters; the core services called by the proof are the real repository implementations.

No hosted authentication, durable database, private result preparation/disclosure, clinical records, remote revocation or real recipient loss of access is proven. No production configuration, VC app, SQL/Auth/Storage, credentials or deployment change. VC Integrations & Security retains actual consumer transport/enforcement and live acceptance. AI/L consumers remain future work.

## Evidence

15/15 joined proof assertions passed. 262/262 local onboarding/runtime tests passed, including two harness tests for the complete outcome and concurrent-run isolation. diff check passed. CI runs both the proof and its harness tests; Foundation and independent Defence CI required before merge.

Remaining live gate: authenticated real private-read admission, withdrawal, current-authority denial across actual consumers and transport-boundary verification. Application launch alone does not close it.

Next: layer 21, Shine AI caller binding.
