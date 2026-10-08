# VC readiness layer 35 — capability health

Baseline: c20637a3b73068fd090cd1e713608f1d7b0ba9fe (layer 34 merged).
After merge: 35/40 complete; 5 remaining (12.5%).

## Behaviour

createVeteranCareCapabilityHealthGate adds a conservative VC selected-memory-read availability gate to the actual layer-34 credential-reference and layer-32 resume pipeline. It reuses Foundation's existing classifyCapabilityHealthEvidence five-minute freshness rule rather than replacing runtime circuit-breaker logic. A successful health observation is necessary here, but supplies no permission.

The fixed route dependencies are vc-session, companion-link, selected-memory-read, task-authority, resume-checkpoint, retry-identity, credential-reference and result-recipient. Every dependency needs an available circuit status, successful last outcome, valid evidence ID and explicitly live or synthetic evidence mode. Missing, quarantined, failed, malformed, future or stale evidence blocks the route. The exact five-minute boundary is stale. Freshness is recomputed locally from the observation timestamp, not accepted from a caller's green flag.

The first complete health sweep follows fresh VC session verification and precedes credential resolution. Further complete sweeps occur immediately before actual private retrieval and after the authority pipeline. Failure before retrieval prevents adapter invocation; failure after retrieval withholds prepared content. Each sweep checks its whole evidence window again after collection, and invalid/regressing clocks fail closed. Current successful evidence may advance between sweeps; the final result deadline is bounded by all final dependency evidence expiries and downstream authority deadlines.

Success returns capability-health-checked-result with frozen per-dependency evidence metadata, authorityProvided false and requiresFreshCapabilityHealthCheck true. Evidence modes remain individually explicit; a mixed or synthetic sweep is never presented as a wholly live verification. The existing independent session, Companion user/link, selected consent, retry identity, checkpoint, task and recipient checks still run. Model disclosure and transport remain closed.

## Ownership and interfaces

Foundation owns route dependency coverage, timestamp freshness composition and result suppression. getCurrentVCCapabilityHealth receives exactly {foundationAppId:'shine.veteran-care',capabilityId:'veteran-care.selected_memory_read',dependencyId}. Its exact row adds {healthStatus,lastOutcome,lastEventAt,evidenceRef,evidenceMode}. It is a protected collector adapter, not a caller-provided health assertion. healthStatus must be available, lastOutcome success, lastEventAt a valid non-future timestamp, evidenceRef an opaque UUID and evidenceMode live or synthetic.

The capability ID here identifies this internal selected-memory-read health route. It does not register a new public capability, mint dispatch tickets or extend AI tools. VC Integrations/Security owns collector wiring, authentic evidence provenance, component-specific read-only probe definitions, protected health storage and availability/circuit translation. This adapter can translate existing Foundation circuit evidence, but host pings and bare circuit availability cannot stand in for dependency success. Each probe must verify its named dependency without retrieving/disclosing clinical text, writing business state or recording credentials. Evidence ID metadata must remain protected from public/browser/model disclosure.

Existing Foundation layers 215/216 retain their generic first-invocation/recovery behaviour. This VC consumer deliberately requires fresh prior successful evidence. A separately scheduled read-only collector must establish and refresh evidence after deployment or inactivity; gated business reads cannot bootstrap their own proof. No collector, scheduler, database view or runtime health policy is modified here. Checkpoint-write durability remains the layer-33 save gate's responsibility and is not asserted by this read-route probe.

Health is point-in-time availability, not consent or a guarantee against later failure. No distributed health/authority lock is held; a later disclosure requires fresh checks. Actual probes, live evidence provenance, operational collector cadence and protected consumer wiring remain open. No live health probe or deployment is claimed.

## Evidence

12 focused synthetic adapter tests cover all dependency sweeps and output modes; each individually missing dependency; quarantine/failure/staleness/future/malformed evidence; binding/accessor refusal; healthy infrastructure with denied authority; deterioration before read; deterioration after read; exact freshness boundary and deadline; whole-sweep expiry/regressing clocks; advancing observations and explicit mixed modes; caller green flags/write overrides and input capture; and outage redaction.

407/407 local onboarding/runtime tests passed, including the existing generic health tests and joined synthetic AI/L proof. Diff check passed. Registered in Foundation CI; Foundation and independent Defence checks must pass before merge. A test fixture carrying evidenceMode live checks mode preservation only; it is not an actual live observation.

Next: layer 36, recovery inventory.
