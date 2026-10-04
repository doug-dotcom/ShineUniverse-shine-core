# Layer 214 — Request/action audit linkage

Completed 4 October 2026. Execution already forwards parent concierge request ID to invocation context, uses the action step ID as invocation request ID, and persists checkpoint request/step/capability IDs. Added regression proves these links agree. Resume now rejects a completed checkpoint explicitly naming a capability different from the current planned action, rather than reusing its result by step ID alone.

Verification: 31 local concierge/Gateway tests pass, including linkage and zero invocation on mismatched checkpoint capability. Existing CI executes these suites.

Source complete; deployment pending. Legacy checkpoints omitting capabilityId retain existing behaviour; database request/owner/client scoping remains authoritative. This is not a new action audit schema or full live execution-history certification. No history rewritten.
