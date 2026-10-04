# Layer 213 — Decision reasons and provenance

Completed 4 October 2026. Gateway dependency exceptions now attempt a denied audit record before returning unavailable. Audit context names the failed stage: caller verification, identity verification, manifest lookup, dependency admission, resource/grant lookup or Defence evaluation. Existing external reason codes remain. Only verified identity is recorded; pre-verification failures use null, even for v1 requests claiming an identity. Existing admission evidence is retained where available. Raw exception text and credentials are excluded.

Verification: 59 local Gateway/runtime tests pass. Added regressions cover all six failure stages, reason consistency, verified/null identity, secret exclusion and audit-store failure. Updated previous no-audit expectation to the intended denied audit behaviour. If auditing fails, response remains unavailable with audit-write-failed; durable recording is not claimed in that case.

Source complete; deployment pending. No schema or historical audit changes. Existing successful decision grant/Defence/admission provenance remains unchanged.
