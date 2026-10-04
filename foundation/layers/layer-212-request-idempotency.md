# Layer 212 — Repeated-request idempotency

Completed 4 October 2026. Existing audit insertion uses request_id conflict protection and checks permission/decision content before accepting a replay. Replay comparison now also checks Defence evidence and admission request context. Recursive sorted object keys allow semantically identical JSON with different key order; arrays retain order.

Verification: 57 local runtime/Gateway tests pass. New adapter regression confirms identical replay returns replayed=true and changed scope, owner, Defence evidence or admission context throws audit-replay-conflict. Gateway already suppresses an allow if audit persistence fails. Tests use controlled SQL fixtures; live concurrent duplicate-request execution is not claimed.

Source complete; deployment pending. A re-evaluation with changed evidence requires a new request ID. This change strengthens access-audit idempotency; it is not an exactly-once guarantee for every app action. No audit history overwritten.
