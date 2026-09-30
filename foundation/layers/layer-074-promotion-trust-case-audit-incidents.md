# Foundation Layer 74 — Promotion-trust case-audit incidents

**Status:** LIVE — CI green, hosted structural-audit sentinel active and healthy production baseline verified  
**Scope:** escalate persistent structural audit failures without auto-repairing the case chain

Layer 73 continuously records whether the complete promotion-trust case chain is structurally sound.

Layer 74 answers:

> If the case-audit observer is unhealthy, has that condition persisted long enough to deserve an operational incident?

## Independent incident domain

Source states:

- normal
- gap
- invalid
- drift
- unknown

This incident domain is distinct from:

- promoted-release trust incidents;
- release-projection incidents;
- readiness incidents;
- runtime-health incidents.

## Severity

- **gap → critical**
- **invalid → critical**
- **drift → warning**
- **unknown → warning**
- **normal → non-incident**

A gap/invalid state is critical-class because the governance chain itself is structurally incomplete or inconsistent.

Drift/unknown remain warning-class because they may represent observer freshness or timing rather than a broken case.

## Persistence

The first unhealthy sample creates a watch.

The same semantic evidence must persist for **300 seconds** before the incident opens.

Lifecycle:

1. unhealthy sample → detected/watch;
2. same condition persists 300s → opened;
3. materially different unhealthy evidence → changed;
4. unchanged open evidence → no duplicate event;
5. normal evidence → recovered.

## Append-only evidence

Ledger:

`foundation.foundation_promoted_release_case_audit_incident_events`

Current views:

- `current_foundation_promoted_release_case_audit_incident_state`
- `current_foundation_promoted_release_case_audit_incidents`
- `current_foundation_promoted_release_case_audit_watches`

Every event binds the Layer-73 semantic observer evidence and optional observation ID.

## Hosted cadence

Layer 73 records the full case audit at minutes ending:

`:04 / :09 / :14 / ... / :59`

Layer 74 evaluates persistence one minute later:

`:00 / :05 / :10 / ... / :55`

The Layer-64 promoted-release observer also runs at that minute, but the two controls are independent.

## Authority boundary

Sentinel:

`service_role`

Read:

- `foundation_runtime`
- `service_role`

Gateway inherits the read-only summary through its existing `foundation_runtime` membership.

Denied:

- Shine Core owner
- Shine Defence runtime
- browser roles

The service role cannot directly insert incident rows.

The transition helper remains owner-private.

Layer 74 never repairs or rewrites the case chain.

## Acceptance coverage

Full Foundation CI run `36694446563` completed successfully. Foundation contracts passed and persistence completed **205/205**, including Layer-74 apply/tests and all downstream Shine Defence checks.

CI proves:

- NORMAL creates no event;
- first GAP creates a critical watch;
- persistent identical GAP opens a critical incident after 300 seconds;
- unchanged open GAP creates no duplicate noise;
- GAP → INVALID appends CHANGED while preserving the original detection clock;
- NORMAL records explicit recovery;
- UNKNOWN starts a warning watch;
- incident history is append-only;
- service role can run only the bounded sentinel;
- Foundation runtime/Gateway read-only role graph remains intact.

## Production proof

Layer 74 is deployed in the Shine Foundation Supabase project through:

- `foundation_layer_074_promoted_release_case_audit_incident_lifecycle`
- `foundation_layer_074_promoted_release_case_audit_incident_hosted`

Hosted sentinel:

`shine-foundation-promoted-release-case-audit-incident-5m`

Schedule:

`0,5,10,15,20,25,30,35,40,45,50,55 * * * *`

A production sentinel run against the current healthy Layer-73 baseline produced:

- case-audit state: **normal**
- reason: `promotion-case-audit-current`
- observation fresh: **true**
- observation matches live: **true**
- event created: **false**
- watch count: **0**
- active incident count: **0**
- automatic repair: **false**
- mutates authoritative truth: **false**
- mutates incident history: **false**

Current Layer-74 summary:

- incident state: **normal**
- watches: **0**
- active incidents: **0**
- current event: **none**
- recommended action: **none**

Production privilege proof:

- Foundation runtime can read incident ledger: **yes**
- Foundation runtime can read summary: **yes**
- Foundation runtime can run sentinel: **no**
- service role can run sentinel: **yes**
- service role direct incident INSERT: **no**
- Gateway can read summary through existing `foundation_runtime` membership: **yes**
- Shine Core owner can read summary: **no**
- Shine Defence runtime can read summary: **no**
- anonymous/authenticated roles can read summary: **no**

Supabase advisors show no Layer-74-specific security finding and no Layer-74 unindexed foreign-key finding.

The Layer-74 incident→observation index currently appears as `unused_index` INFO because production has zero case-audit incident events. It is retained for the FK/query path once a real incident occurs.

## Invariant

> Structural failure may deserve escalation. Escalation never becomes permission to repair the evidence it is judging.
