# Layer 205 — Account separation

Completed 4 October 2026. Resource ID lookups now require and filter by the verified owner, matching category lookups. Missing owner context returns no resource without querying. Gateway rechecks returned resource ownership before sending metadata to Defence, guarding against faulty adapters. The existing permission engine separately checks resource and grant ownership.

Verification: 70 local runtime, Gateway and permission-engine tests passed. Added regressions prove owner-constrained SQL, no lookup without an owner, foreign metadata blocked before Defence, foreign grants denied, and successive users on one Gateway instance have independent resource/grant lookups and audit identities.

Source completion only. Tests use controlled fixtures; production deployment, live multi-account checks and database-wide RLS certification are not claimed. No user records, grants or identity bindings changed.
