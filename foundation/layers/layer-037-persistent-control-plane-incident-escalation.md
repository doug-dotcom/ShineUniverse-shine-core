# Foundation Layer 37 — Persistent control-plane incident escalation

**Status:** LIVE  
**Scope:** escalate persistent release-projection FAIL/UNKNOWN states into structured append-only control-plane incidents

Layer 36 continuously reconciles the Universe registry, readiness-release ledger and immutable Foundation release binding.

Layer 37 turns persistent reconciliation exceptions into an incident lifecycle.

A single bad sample does not immediately become an incident. Foundation first creates a watch. If the same unhealthy evidence remains for a full five-minute persistence window, the watch is escalated to an active incident.

## Incident ledger

Layer 37 adds:

`foundation.foundation_control_plane_incident_events`

The ledger is append-only and records:

- incident key;
- environment;
- domain;
- lifecycle event type;
- source reconciliation state;
- severity;
- reason codes;
- reconciliation evidence fingerprint;
- source projection observation;
- detection start;
- persistence threshold;
- persistence duration;
- full reconciliation snapshot;
- occurrence/evidence metadata.

The current-state view is:

`foundation.current_foundation_control_plane_incident_state`

Active incidents are exposed through:

`foundation.current_foundation_control_plane_incidents`

Pre-escalation watches are exposed through:

`foundation.current_foundation_control_plane_watches`

## Lifecycle

The lifecycle is:

1. **detected**
2. **opened**
3. **changed**
4. **recovered**

### Detected

The first `FAIL` or `UNKNOWN` reconciliation sample starts a persistence watch.

No active incident exists yet.

### Opened

If materially identical unhealthy evidence persists for at least **300 seconds**, the watch becomes an active incident.

### Changed

If an already-active incident remains unhealthy but its meaningful reconciliation evidence changes, Foundation appends a `changed` event.

The incident stays open.

### Recovered

If the reconciliation state becomes `ALIGNED` or `DEGRADED`, any watch or active incident receives a `recovered` event.

The incident is no longer active.

## Severity

Layer 37 maps source states deliberately:

- `FAIL` → **critical**
- `UNKNOWN` → **warning**
- `ALIGNED` → non-incident
- `DEGRADED` → non-incident

A degraded projection may deserve remediation but is not treated as a control-plane identity incident.

## Persistence semantics

The persistence threshold is:

**300 seconds**

A materially different unhealthy fingerprint before the threshold resets the persistence watch.

That prevents unrelated transient failures from being stitched together into a false persistent incident.

Unchanged unhealthy evidence does not append duplicate incident rows while waiting for the threshold.

## Sentinel

The hosted sentinel is:

`foundation.run_foundation_control_plane_incident_sentinel_v1(text,timestamptz,integer)`

It:

1. runs the Layer-36 reconciliation recorder;
2. gets the authoritative current reconciliation snapshot and observation ID;
3. evaluates the Layer-37 persistence state machine;
4. appends an incident lifecycle event only when the lifecycle changes.

The low-level transition helper is owner-private.

Service role cannot call it directly and cannot insert directly into the incident ledger.

## Summary

Runtime-safe summary reader:

`foundation.get_foundation_control_plane_incident_summary_v1(text)`

Summary states:

- **normal**
- **watching**
- **warning**
- **critical**

It reports:

- active incident count;
- watch count;
- current projection state/fingerprint;
- current lifecycle event;
- severity;
- persistence duration;
- recommended action.

## Continuous schedule

Production pg_cron job:

`shine-foundation-control-plane-incident-5m`

Schedule:

`2,7,12,17,22,27,32,37,42,47,52,57 * * * *`

This follows Layer 36's reconciliation observer by one minute.

## Production release

Layer 37 release:

`foundation:layer-37:b7c5331f`

The runtime identity remains Gateway v85 because this layer changes Foundation database control-plane behaviour, not the deployed Gateway artefact.

Current immutable identity:

- runtime: **85**
- source: `b7c5331f93eff28a781f0794c89ccf50e90a4045`
- artefact: `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`
- deployment receipt: `bac106fe-57c4-4b38-b8bb-0acb5de11086`
- publication: `2649330b-6117-44a0-9614-aae8f6fb8478`
- assurance: **github-oidc**

## Live state

Current Layer-36 projection:

**ALIGNED**

Current Layer-37 incident summary:

**NORMAL**

- active incidents: **0**
- watches: **0**
- incident events: **0**

The first post-promotion sentinel run recorded the new aligned Layer-37 projection observation and correctly created no incident event.

## Acceptance coverage

Foundation CI proves:

- first FAIL creates a critical watch only;
- FAIL before threshold does not open an incident;
- persistent FAIL opens a critical incident;
- material unhealthy evidence changes append `changed`;
- ALIGNED recovers the incident;
- first UNKNOWN creates a warning watch;
- persistent UNKNOWN opens a warning incident;
- DEGRADED recovers UNKNOWN;
- the real sentinel translates live reconciliation state into lifecycle transitions;
- runtime can read the summary;
- runtime cannot run the sentinel;
- service role cannot call the owner-private transition helper;
- service role cannot bypass the sentinel with direct incident INSERT.

Full Foundation CI run:

`36406192649`

completed successfully.

## Advisor result

Post-deployment:

- no Layer-37 security findings;
- no missing-index or structural performance findings;
- the new projection-observation FK index is initially reported as unused, which is expected immediately after creation.

## Closure invariant

Foundation now treats release-projection inconsistency as an operational lifecycle rather than a boolean:

> **A transient exception is watched, a persistent exception is escalated, meaningful changes are preserved, and recovery is explicit.**

Healthy aligned operation remains quiet.
