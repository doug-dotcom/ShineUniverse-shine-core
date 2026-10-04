# Layer 220 — fresh recovery authorisation

Source complete; deployment pending.

Execution now requires gate.status to be explicitly allowed. Unknown or missing gate status returns concierge-execution-gate-invalid before audit, checkpoint access or invocation. Existing blocked responses remain blocked. Every request already re-verifies the client and current identity or delegation before the execution gate; recovery cannot bypass these checks using a checkpoint.

Validation: eleven orchestration/Wellness tests passed. Six denial cases (unverified client, identity, delegation, blocked gate, unknown gate and missing status) prove zero checkpoint access or invocation and no saved results returned. No live revocation or deployment performed.
