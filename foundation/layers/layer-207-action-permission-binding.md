# Layer 207 — Action permission binding

Completed 4 October 2026. The existing ticket issuer binds permission to a concierge action step and capability. The invocation runtime now checks that the issued ticket response matches the exact request step and capability before sending the ticket or input to an app endpoint. A mismatched or missing binding fails with capability-ticket-action-mismatch and makes no app call. Read/advisory-only invocation restrictions remain in place.

Verification: 38 local runtime and ticket redemption tests pass. New invocation regression covers substituted and missing step/capability fields, zero endpoint calls for rejected tickets, and successful dispatch with an exactly matching ticket. The runtime suite is already in Foundation CI.

Source complete; deployment and live invocation verification pending. This validates ticket response binding, not action payload immutability or ticket reuse, which require separate controls. No permission grants changed.
