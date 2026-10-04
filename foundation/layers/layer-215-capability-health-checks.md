# Layer 215 — Capability health checks

Completed 4 October 2026. Live capability_adapter_health view inspected read-only: defined health states are available and quarantined; the view bases quarantine on recent failures. Runtime no-row fallback now reports unknown instead of available. Invocation requires available health; missing/malformed/unknown states fail before ticket issuance and endpoint dispatch. Quarantine behaviour remains intact.

Verification: 40 local runtime and operational-status tests pass. Regressions cover missing health row, null/malformed/unrecognised states, quarantine, zero tickets/network calls while health blocks, and valid available-health dispatch. Existing CI runs the suite.

Source complete; deployment pending. Available is the existing circuit-breaker state, not proof of recent successful health evidence. Freshness handling is reserved for Layer 216. No health events or database views changed.
