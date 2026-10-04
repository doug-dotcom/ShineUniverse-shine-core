# Layer 211 — Redeemed ticket reuse

Completed 4 October 2026. Read-only inspection of the live consume_capability_invocation_ticket_v2 function confirms a FOR UPDATE ticket row lock, durable consumed-event lookup, replay denial and consumed-event insertion before allowed response. No database mutation or schema change performed.

Redemption service now requires the returned ticket ID, as well as capability and step IDs, to equal the requested binding before reporting allowed. Missing/substituted ticket IDs fail closed.

Verification: 39 local runtime/redemption tests pass. A stateful adapter fixture confirms a fresh service instance forwards an already-consumed denial and exposes no permission context. This tests service behaviour; live concurrent/replay database execution has not been performed. Database source inspection is not concurrency test evidence.

Source complete; JavaScript deployment pending. No real ticket consumed. Replay authority remains in the durable database function; no process-local replay cache added.
