# VC readiness — layer 17: content-free audit event contract

8 October 2026, Brisbane. Baseline b535afdffb2dbfddc9e4a114f2de64ee447d2c43.
After merge: 17/40 source-verified producer layers; 23 remain (57.5%).

## Enables VC

createVeteranCareAuditedPermissionEvaluator wraps the existing fresh permission evaluator with a minimal, frozen permission-observation event and an acknowledged server audit sink. Permission allowed, permission denied and authority unavailable have bounded categories. The sink receives only the versioned event type, generated event ID, configured app ID, server time, observation stage/outcome and explicit executionPerformed false/disclosureVerified false.

No input/result/request/context spreading into logs. No record, preparation, grant, actor/owner identifiers, credentials, free-text reason/error, clinical content or arbitrary caller metadata is copied. Server event ID is generated independently of user tokens and private record identifiers. It can correlate a protected consumer transaction through auditEventId; any identity/resource association must remain in an independently access-controlled consumer record, not be added to this event.

The sink must acknowledge status recorded and the exact event ID. An outage, queued/absent/wrong-event/accessor acknowledgement, invalid ID or invalid server clock withholds the allowed request/grant and returns bounded unavailable with auditRecorded false. Successful recording attaches auditRecorded true and auditEventId to the server permission result. No queue/fallback or persistence claim without acknowledgement.

## Ownership and limits

Foundation owns the reusable producer contract and acknowledgement gate. The existing generic gateway audit is retained, not rewritten or counted again; this new VC permission path supplies an explicit privacy-minimal event projection and acknowledged sink boundary.

VC Integrations & Security owns the authoritative durable sink adapter, retention/access policies, protected transaction correlation and consumer integration. A sink must return recorded only after durable persistence. Unit acknowledgement does not prove production persistence. No SQL, VC, Auth/Storage, model, UI or deployed runtime change.

This is a point-in-time permission observation, not an audit of transport delivery, record read, clinician verification or payment. The asynchronous audit write adds a delay; the consumer must freshly recheck permission/session/revocation/expiry at execution/disclosure afterwards. This permission result is never a portable ticket. The existing guarded-read route is not switched to this wrapper, and its private-preparation release contract is untouched.

## Evidence

6 focused tests cover minimal allow-event projection, denied/unavailable categories, content/credential exclusion, sink outage and wrong/queued/accessor acknowledgements, invalid IDs/clocks and waiting for acknowledgement.
246/246 local onboarding/runtime tests passed; diff check passed. CI runs the new suite. Foundation and independent Defence CI required before merge.
Open: real durable audit adapter, protected transaction correlation, consuming enforcement and live authenticated persistence/retrieval evidence.

Next: layer 18, safe denial reason contract.
