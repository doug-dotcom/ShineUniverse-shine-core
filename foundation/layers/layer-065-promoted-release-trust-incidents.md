# Foundation Layer 65 — Promoted-release trust incidents

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** escalate persistent loss of consumer-visible promotion trust without granting automatic repair authority

Layer 64 answers:

> Is the promoted-release trust boundary still true now?

Layer 65 answers:

> If it is not, has that loss persisted long enough to become an operational incident, and has recovery been explicitly recorded?

## Independent incident domain

Layer 65 does not reuse the older release-projection incident state.

Its source is the Layer-64 trust summary:

- normal
- hold
- drift
- unknown

This keeps consumer trust distinct from deployment projection and runtime readiness.

## Severity

- **hold → critical**
- **drift → warning**
- **unknown → warning**
- **normal → non-incident**

A HOLD is critical-class because downstream consumers no longer have a promoted Foundation release.

## Persistence window

One bad sample does not immediately open an incident.

Lifecycle:

1. first bad sample → detected/watch;
2. same bad semantic evidence persists for 300 seconds → opened;
3. materially different unhealthy evidence while open → changed;
4. unchanged open evidence → no new event;
5. normal trust → recovered.

This keeps transient wobble visible without turning it into incident noise.

## Append-only evidence

Ledger:

`foundation.foundation_promoted_release_incident_events`

Current views:

- `current_foundation_promoted_release_incident_state`
- `current_foundation_promoted_release_incidents`
- `current_foundation_promoted_release_watches`

Every incident event records the semantic trust fingerprint, reason, optional Layer-64 observation reference, persistence clock and full trust snapshot.

## Hosted sentinel

Layer 64 observes trust at minutes ending:

`:00 / :05 / :10 / ... / :55`

Layer 65 evaluates incident state one minute later:

`:01 / :06 / :11 / ... / :56`

The observer and incident sentinel therefore remain separate controls.

## Authority boundary

The sentinel is service-role-only.

The transition helper is owner-private.

Service role has no direct INSERT privilege on the incident ledger.

Foundation runtime may read incident state and summaries but may not create incidents.

Layer 65 never:

- repairs source truth;
- rebinds a release;
- mints closure;
- changes readiness;
- performs rollback;
- performs automatic remediation.

## Acceptance coverage

CI proves:

- normal trust creates no incident;
- first HOLD sample creates a critical watch;
- persistent identical HOLD opens a critical incident at 300 seconds;
- unchanged open HOLD creates no duplicate noise;
- changed unhealthy evidence appends CHANGED;
- recovery clears active/watch state with an explicit RECOVERED event;
- UNKNOWN starts a warning watch;
- direct ledger insert is denied to service role;
- transition helper is not runtime/service callable;
- runtime has read-only incident visibility;
- incident history is append-only.

## Invariant

> Losing promoted-release trust is immediately safe because consumers fail closed. It becomes an operational incident only after persistence, and only explicit healthy evidence records recovery.
