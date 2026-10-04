# Layer 218 — safe automatic retries

Source complete; deployment pending.

Concierge queues automatic retries only for adapter quarantine, registry unavailability and health unavailability: confirmed failures before endpoint dispatch. Endpoint exceptions, rejected responses, invalid payloads and generic invocation failures now follow the existing terminal failure path rather than automatic retry, because remote execution may have occurred. These require outcome reconciliation before another attempt. Existing queue scheduling, checkpoints and fresh execution gates remain intact.

Validation: nine orchestration/Wellness tests passed. The new service-level test covers eight failure reasons and confirms exactly one invocation, with retry queuing only for the three pre-dispatch reasons. No live retries or deployment performed.
