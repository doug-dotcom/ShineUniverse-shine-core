# Layer 209 — Consent withdrawal

Completed 4 October 2026. Existing withdrawal routes require explicit revoke=true, a fresh request, verified caller and verified owner; app grant withdrawal has no Defence dependency. Integration grant and link withdrawal now reject malformed adapter results with no reason, or a returned identifier different from the requested grant/link, before reporting success.

Verification: 22 local consent, revocation and revocation-feed tests pass. New tests cover both integration withdrawal routes, malformed/mismatched results, dependency failure, revoked/already-revoked outcomes, exact verified owner forwarding and no write for non-explicit withdrawal. Suite already runs in CI.

Source complete; deployment and live revocation propagation pending. No real grants or links revoked. Identifier checks verify adapter response consistency; database owner checks and durable propagation remain separate controls.
