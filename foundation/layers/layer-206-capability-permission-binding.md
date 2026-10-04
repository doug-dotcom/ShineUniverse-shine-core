# Layer 206 — Capability permission binding

Completed 4 October 2026. Existing capability consent names an exact capability and purpose; discovery exposes metadata without authorising invocation. Ticket redemption now also verifies that an allowed adapter response matches both the requested capability ID and step ID before returning permission context. Mismatched or missing bindings return unavailable with no owner/grant context. Denials remain denied.

Verification: eight local capability discovery/redemption tests pass, covering exact binding, a substituted capability, substituted step, missing response bindings and denied grants. New redemption suite added to Foundation CI.

Source completion only; deployment pending. This strengthens the JavaScript ticket service boundary, not a certification of every database grant function or connected app. No permission grants were issued or expanded.
