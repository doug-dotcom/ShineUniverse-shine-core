# Layer 219 — recovery validation

Source complete; deployment pending.

Concierge execution now stops with concierge-resume-state-unavailable if checkpoint lookup throws. It no longer treats that outage as an empty history and risks repeating completed work.

Validation: ten orchestration/Wellness tests passed. A stateful adapter fixture proves outage causes zero invocation, restored lookup permits completion, and a fresh service instance reuses the stored checkpoint without a second invocation. This is a source-level recovery test, not a live database restart or deployment test. Existing successful empty-history behaviour remains unchanged.
