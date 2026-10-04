# Layer 204 — Consistent user identity

Completed 4 October 2026. Both supported user credential modes already verify through an app-approved provider and map a verified provider subject to an active canonical Shine identity. Gateway access and audit use the verified identity; conflicting caller claims are denied.

Closed two adapter gaps: mixed JWT and opaque credentials now return unverified before database or network access; JWT provider lookup requires exactly one registered match, consistent with opaque-provider selection, instead of silently choosing the first.

Verification: 51 runtime and Gateway core tests passed locally. Added tests for zero external calls on ambiguous credentials/provider matches and the same canonical identity across linked JWT and opaque accounts. Provider verification and mapping tests use controlled fixtures, not real user credentials.

Source saved only; deployment and live cross-app verification pending. No identity bindings changed, no accounts linked automatically, and no production rollout claimed.
