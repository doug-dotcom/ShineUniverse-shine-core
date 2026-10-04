# Layer 217 — unavailable invocation dependencies

Source complete; deployment pending.

Capability invocation now converts registry SQL outages into capability-adapter-registry-unavailable and health-read exceptions into capability-adapter-health-unavailable. Both return status failed before ticket issuance or endpoint calls. Raw exception details are not exposed. Existing ticket and endpoint failure handling remains intact. No automatic retries or live data changes.

Validation: 40 runtime adapter tests passed, including thrown registry and health dependencies with zero downstream calls. No live outage injection or deployment performed.
