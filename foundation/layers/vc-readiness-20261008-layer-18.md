# VC readiness — layer 18: safe denial explanations

8 October 2026, Brisbane. Baseline aa7ddcefa38a904fd524cdb6c4c0d7291c78d52f.
After merge: 18/40 source-verified producer layers; 22 remain (55%).

## Enables VC

projectVeteranCareDenial builds a frozen, versioned public denial envelope from a trusted server refusal. Only fixed code/message/nextAction values are returned. Missing/wrong-owner resources, missing/ambiguous grants, expiry, stale snapshots, changed in-flight authority and unverified delegation share one access-not-confirmed response: no record-existence or other-veteran distinction is disclosed.

A known inactive session asks the user to sign in. A read-route operation refusal asks them to review the request. All unavailable authorities use one retry-later response without revealing the internal stage. Unknown/free-text reasons, clinical content, IDs, JWTs, stacks and arbitrary input fields are never forwarded. Accessor/inherited/malformed inputs fall back without reading getter values.

This is a denial-only serializer. Known success outcomes return null, meaning not a denial projection; null is never permission, a success payload, or permission to invoke a service. The consumer must check its authoritative outcome independently and handle success using its own authorised response path. No retry execution, automatic login, permission change or authority bypass is introduced.

## Ownership and limits

Foundation owns the public denial contract/projection. VC Integrations & Security owns server-route adoption and stripping raw outcomes before transport. App/UI owns rendering/actions, using the canonical envelope rather than copying backend details. No UI or VC shared file, SQL/Auth/Storage, model, production configuration or deployed runtime change.

This controls the projected response fields, not HTTP timing/status side channels, private diagnostic access, caller authentication or browser presentation. Live consumer routing and identity-safe end-to-end response proof remain open. The permission engine, audit and guarded-read enforcement remain unchanged.

## Evidence

6 focused tests cover non-enumerating access refusals, concrete session/read-only actions, bounded outages, malicious text/HTML/private fields, malformed/inherited/accessor inputs and success separation.
252/252 local onboarding/runtime tests passed; diff check passed. Foundation and independent Defence CI required before merge. New focused suite is added to CI.

Next: layer 19, permission-service outage handling.
