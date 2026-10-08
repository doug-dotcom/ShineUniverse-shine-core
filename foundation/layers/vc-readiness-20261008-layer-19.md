# VC readiness — layer 19: permission-service outage handling

8 October 2026, Brisbane. Baseline fbfad07487a96c435552e27cc15383ae9bd8f773.
After merge: 19/40 source-verified producer layers; 21 remain (52.5%).

## Enables VC

createVeteranCareBoundedPermissionEvaluator wraps current permission context and independent revision lookups with per-call deadlines. Default 5000 ms; server configuration accepts integer 1–30000 ms only. Current exact identity/session/resource/purpose/grant/Defence/expiry/revision evaluation is reused.

A never-settling authority lookup now returns the existing bounded unavailable denial, with no allowed request or grant and executionPerformed false. No cached allow, automatic retry or private execution fallback. Late success/rejection is consumed and cannot settle an already timed-out caller or become authority for a later request. Each lookup has its own controller/deadline; a concurrent healthy request remains independent. Subsequent requests freshly query recovered authority and still refuse a stale snapshot or withdrawn grant.

Trusted read-only adapters receive their existing query plus a second {signal} argument, aborted on timeout. They should propagate this AbortSignal to transport for resource cleanup. It is cooperative: ignoring abort does not prove remote work stopped, but its late answer remains unusable by this evaluator.

## Ownership and limits

Foundation owns reusable deadline control. VC Integrations & Security owns real permission/revision transport adapters, production timeout selection, rate/admission limits and consumer wiring. The added outcome is bounded handling of hangs; existing exception-based outage denial is reused, not counted again.

This bounds the two permission-authority awaits only, not identity/session/resource/preparation lookups, total request lifetime, audit writes, network transport delivery or synchronous blocking code. JavaScript event-loop delays can delay the timer. It performs no remote writes, private preparation or model calls and does not cancel other consumers. Denial remains recoverable by a new explicitly initiated request after recovery; no permission is restored merely because a service is healthy.

No VC, UI, SQL/Auth/Storage, credential, model or deployed runtime changes. Existing guarded-read and audited-permission factories are not silently rewired. Consumer must bind this evaluator where appropriate and preserve fresh disclosure checks; actual live outage enforcement remains open.

## Evidence

8 focused tests cover healthy authority, context/revision hangs, cooperative abort, no cached fallback, late success/rejection isolation, recovered fresh checks, exception privacy/no retry, concurrent independent calls and invalid configuration.
260/260 local onboarding/runtime tests passed; diff check passed. CI adds the new focused suite. Foundation and independent Defence CI required before merge.

Next: layer 20, joined synthetic revocation proof journey.
