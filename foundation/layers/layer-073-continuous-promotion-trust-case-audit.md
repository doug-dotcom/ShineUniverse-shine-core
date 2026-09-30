# Foundation Layer 73 — Continuous promotion-trust case audit

**Status:** LIVE — CI green, five-minute case-audit observer active and production heartbeat verified  
**Scope:** turn the Layer-72 on-demand case audit into durable five-minute operational evidence

Layer 72 answers:

> Is the complete promotion-trust case chain structurally coherent right now?

Layer 73 adds:

> When was that last observed, has the meaning changed, and does the latest durable observation still match live truth?

## Append-only audit observations

Ledger:

`foundation.foundation_promoted_release_case_audit_observations`

Every observation records:

- Layer-72 overall audit state;
- structural-integrity result;
- incident state;
- active incident event;
- active incident handoff state;
- case counts;
- invalid/pending/terminal/historical counts;
- semantic fingerprint;
- whether semantics changed from the previous heartbeat;
- complete bounded Layer-72 audit snapshot;
- observation time.

## Semantic fingerprint

The fingerprint intentionally removes values that change merely because time passed:

- `evaluatedAt`
- `activeIncidentEventAgeSeconds`
- volatile `incidentSummary`

The case-chain content, stages, hashes, bindings, counts and structural state remain fingerprint inputs.

Therefore a five-minute heartbeat over an unchanged case remains unchanged, while a real stage/binding/integrity transition changes the fingerprint.

## Freshness-aware summary

Reader:

`foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(...)`

States:

- **normal** — fresh durable observation matches live Layer-72 truth and live audit is structurally valid;
- **gap** — fresh/matching Layer-72 audit reports an overdue structural gap;
- **invalid** — fresh/matching audit reports broken case integrity/binding;
- **drift** — durable observation is fresh but no longer matches live Layer-72 truth;
- **unknown** — no observation exists or latest evidence is stale.

Layer 73 never converts gap/invalid into a repair action.

## Hosted cadence

Promotion-trust sequencing now reads:

- `:00` — promoted-release observation;
- `:01` — promotion-trust incident evaluation;
- `:02` — control-plane incident reconciliation;
- `:03` — Shine Core owner-handoff materialisation;
- `:04` — complete promotion-trust case-audit observation.

Layer 73 therefore observes the chain after owner-work materialisation has had its normal opportunity to run.

The Layer-60 promotion-closure job also uses the `:04` phase, but the two domains have no ordering dependency.

## Authority boundary

Recorder:

`service_role`

Reader:

- `foundation_runtime`
- `service_role`

Gateway inherits the read-only reader through its existing `foundation_runtime` membership; Layer 73 grants it no direct write capability.

Denied:

- Shine Core owner;
- Shine Defence runtime;
- browser roles.

The service role has no direct INSERT on the observation ledger.

## Acceptance coverage

Full Foundation CI run `36692428928` completed successfully. Foundation contracts passed and persistence completed **203/203** with the Layer-73 apply/tests green and all downstream Shine Defence checks remaining green.

CI proves:

- first idle observation is a semantic change;
- second unchanged idle observation is a heartbeat;
- timestamp/age-only movement does not change the fingerprint;
- live Layer-72 change before the next heartbeat appears as drift;
- recorded structural gap appears as gap;
- recorded corrupt case history appears as invalid;
- stale observation becomes unknown;
- direct ledger mutation is append-only rejected;
- recorder/read privileges follow the existing Foundation runtime role graph.

## Production proof

Layer 73 is deployed in the Shine Foundation Supabase project through:

- `foundation_layer_073_promoted_release_case_audit_observation`
- `foundation_layer_073_promoted_release_case_audit_observation_hosted`

The hosted job is active:

`shine-foundation-promoted-release-case-audit-observation-5m`

Schedule:

`4,9,14,19,24,29,34,39,44,49,54,59 * * * *`

Current production observer state:

- summary state: **normal**
- reason: `promotion-case-audit-current`
- live audit state: **idle**
- structural integrity pass: **true**
- incident state: **normal**
- active incident handoff state: **not-required**
- cases: **0**
- invalid cases: **0**
- observation fresh: **true**
- observation matches live: **true**
- recommended action: **none**

Current semantic fingerprint:

`f93cdd15fb315d5f730cc28a0744f60ee16e834060a91b9ecde1b2f949722df0`

A subsequent explicit production heartbeat produced:

- status: `recorded-heartbeat`
- audit state: **idle**
- structural integrity pass: **true**
- changed from previous: **false**
- semantic fingerprint unchanged

That proves timestamp movement alone does not create false semantic churn.

Production privilege proof:

- Foundation runtime can read ledger: **yes**
- Foundation runtime can read summary: **yes**
- Foundation runtime can record: **no**
- service role can record: **yes**
- service role direct ledger INSERT: **no**
- Gateway can read summary through existing `foundation_runtime` membership: **yes**
- Shine Core owner can read summary: **no**
- Shine Defence runtime can read summary: **no**
- anonymous/authenticated roles can read summary: **no**

Supabase advisors show no Layer-73-specific security finding and no Layer-73 unindexed foreign-key finding. Existing estate-wide advisor notices remain unrelated to this observer.

## Invariant

> A case audit that is not being observed can become stale evidence. Layer 73 makes both the case state and the freshness of that knowledge explicit.
