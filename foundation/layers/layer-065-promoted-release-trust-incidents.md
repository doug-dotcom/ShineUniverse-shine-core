# Foundation Layer 65 — Promoted-release trust incidents

**Status:** LIVE — CI green, production sentinel active and healthy baseline verified  
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

The first Layer-65 run exposed a test-only PostgreSQL naming collision: a local variable and the Layer-64 column were both named `observation_id`. The migration itself applied successfully. The test alias was corrected without changing lifecycle logic.

Corrected full Foundation CI run `36676325802` completed successfully. Both Foundation jobs passed, the Layer-65 lifecycle tests passed, and all downstream Shine Defence acceptance steps remained green.

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

## Production proof

Layer 65 is deployed in the Shine Foundation Supabase project.

The production sentinel was executed against the current healthy promoted-release baseline and correctly produced **no incident event**.

Current production summary:

- incident state: **normal**
- trust state: **normal**
- trust reason: `promoted-release-current`
- observation fresh: **true**
- observation matches live: **true**
- watch count: **0**
- active incident count: **0**
- current incident event: **none**
- recommended action: **none**
- automatic repair: **false**

Hosted job:

`shine-foundation-promoted-release-incident-5m`

is active on:

`1,6,11,16,21,26,31,36,41,46,51,56 * * * *`

Production privilege proof:

- Foundation runtime may read incident ledger: **yes**
- Foundation runtime may read summary: **yes**
- Foundation runtime may run sentinel: **no**
- service role may run sentinel: **yes**
- service role direct incident INSERT: **no**
- service role direct transition-helper execution: **no**
- anonymous/authenticated summary read: **no**

The Supabase security advisor reports no Layer-65-specific security finding.

The performance advisor reports one Layer-65 INFO finding: the incident→observation index has not yet been used. This is expected while the production incident ledger contains zero events; the index is retained for the FK/query path when incidents occur.

## Invariant

> Losing promoted-release trust is immediately safe because consumers fail closed. It becomes an operational incident only after persistence, and only explicit healthy evidence records recovery.
