# Layer 216 — stale capability health evidence

Source complete; deployment pending.

Runtime health reads now include last_event_at and expose evidence_freshness (fresh, stale, unknown), evidence_age_ms and the five-minute evidence_max_age_ms. Evidence is stale at the exact five-minute boundary. Missing, malformed or future timestamps are unknown. Last outcome remains explicit: fresh failure is not successful health.

Circuit-breaker availability remains separate. Existing read/advisory invocation gates and ticket checks remain in place; this layer does not require prior fresh success, which would prevent first invocation and recovery after inactivity. Consumers must inspect freshness and outcome before claiming recent successful health. No SQL schema or live grant changes.

Validation: 39 runtime adapter tests passed, including freshness boundaries, unknown evidence and available-but-stale failure reporting. No deployment or live adapter probe performed.
