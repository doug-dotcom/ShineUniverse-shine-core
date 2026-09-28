# Foundation Layer 46 — Semantic readiness retest cycles

**Status:** LIVE

Layer 46 fixes a subtle persistence problem: fresh telemetry can change while the underlying operational degradation remains identical.

## Two fingerprints

### Raw evidence fingerprint

Tracks the exact evidence set.

It may change when health windows, Defence observations or other telemetry refresh.

### Semantic condition fingerprint

Tracks only the operational condition:

- readiness state;
- reason codes;
- degraded scopes;
- guarded scopes;
- blocked scopes;
- privileged operations mode;
- worker operations mode.

Only a semantic condition change may reset/change the readiness lifecycle.

## Production proof

The original Layer-44 watch began at 12:07:14 UTC.

Fresh evidence later changed the raw readiness evidence while the same six degraded scopes remained:

- context operations
- control operations
- credential operations
- identity operations
- permission operations
- protected operations

Layer 46 preserved semantic continuity.

At the retest, the condition had persisted **899 seconds**, exceeding the 300-second threshold.

The retest therefore produced `opened`.

During the append-only-safe production migration, that first retest cycle was recorded before the authoritative incident event was linked. Layer 46 added an explicit reconciliation path that repaired this solely by appending the missing incident event.

No historical watch row was edited.

No historical retest row was edited.

Authoritative state is now:

- readiness incident state: incident
- active incidents: 1
- watch count: 0
- severity: warning
- persistence: 899 seconds
- containment active: true

## Containment remains bounded

Even with the incident open:

- canonical truth mutation: prohibited
- release rebind by readiness policy: prohibited
- automatic dependency repair: prohibited
- containment is limited to existing degraded scopes

## CI

Foundation run `36422165959` passed Layer 46 and the complete downstream chain.

## Advisors

- Layer-46 security findings: 0
- only unused-index INFO exists for the new retest ledger because production currently contains one retest cycle

## Invariant

> Telemetry freshness must not erase incident persistence. Track fresh evidence and persistent meaning separately.
