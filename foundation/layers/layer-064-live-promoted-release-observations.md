# Foundation Layer 64 — Live promoted-release observations

**Status:** LIVE — CI green, re-attestation continuity corrected, production observer active  
**Scope:** make consumer-visible promotion trust observable after CI

Layers 59–63 prove source truth, closure, promoted-release projection, contract pinning and producer/consumer parity.

One operational seam remained.

The Layer-37 control-plane incident sentinel watches release-projection FAIL/UNKNOWN states. By design, a degraded release projection is not an incident.

But the consumer-facing Layer-61 release can still move from promoted to hold while that older projection domain is merely degraded.

Layer 64 observes the consumer trust boundary directly.

## Append-only observation ledger

New ledger:

`foundation.foundation_promoted_release_observations`

Every hosted check writes one append-only heartbeat containing:

- promoted or hold state;
- availability;
- reason code;
- promotion-closure state;
- release ref when promoted;
- promoted-release SHA-256 when promoted;
- semantic fingerprint;
- whether the semantics changed from the previous heartbeat;
- complete Layer-61 snapshot;
- observed timestamp.

The semantic fingerprint deliberately ignores `evaluatedAt` so time passing alone is not treated as semantic drift.

## Freshness-aware summary

Reader:

`foundation.get_foundation_promoted_release_observation_summary_v1(...)`

Summary states:

- **normal** — a fresh observation matches live promoted state;
- **hold** — a fresh observation matches live hold state;
- **drift** — the latest observation is fresh but no longer matches live Layer-61 truth;
- **unknown** — no observation exists or the observation is stale.

The summary re-evaluates the live Layer-61 projection and compares it to the latest durable heartbeat.

This means a live trust change becomes visible even before the next hosted observation is written.

## Hosted cadence

Layer 60 records promotion closure at minutes ending 4/9/14/.../59.

Layer 64 observes the resulting consumer state one minute later:

`0,5,10,15,20,25,30,35,40,45,50,55 * * * *`

The default summary freshness window is ten minutes, allowing one missed five-minute heartbeat before freshness itself becomes unknown.

## Authority boundary

Layer 64 is evidence only.

It:

- does not repair registry state;
- does not create release bindings;
- does not mint promotion closure receipts;
- does not change readiness;
- does not auto-repair hold state.

`service_role` may invoke the recorder but has no direct INSERT privilege on the ledger.

Foundation runtime may read observations and summary but cannot record them.

## Acceptance coverage

Full corrected Foundation CI run `36666949891` completed successfully.

That run proved both the Layer-35 re-attestation continuity regression and the Layer-64 observation semantics in the same persistence chain. Every downstream Shine Defence acceptance step also remained green.

CI proves:

- first promoted observation is a semantic change;
- repeated promoted heartbeat retains the same fingerprint and is marked unchanged;
- fresh promoted observation + matching live state gives normal;
- live hold before next heartbeat is visible as drift;
- recorded hold gives hold;
- hold stores no promoted identity;
- stale observer evidence gives unknown;
- direct ledger mutation is append-only rejected;
- recorder/read privileges are least-privilege.

## Production discovery — re-attestation continuity

While Layer 64 was being verified, production moved from **promoted** to **hold**.

The observer work exposed a real older invariant conflict:

- Layer 33 explicitly permits a distinct trusted GitHub-OIDC run to re-attest the same immutable deployment receipt;
- the Foundation gateway deployment receipt, source commit, runtime version and artifact SHA had not changed;
- Layer 35 nevertheless required the current publication event ID to equal the publication event ID captured at bind time;
- a fresh trusted re-attestation therefore made release identity health fail and opened a real control-plane incident.

Layer 64 corrects that contradiction without weakening deployment identity.

The bind-time publication ID remains immutable historical provenance. A later publication event may satisfy current health only when it attests the exact same deployment receipt, source ref, runtime version, artifact SHA and publication assurance.

A changed deployment identity still fails closed.

The binder also replays the existing historical binding across equivalent re-attestation instead of attempting to rewrite provenance or raising a false release conflict.

## Production proof

The live failure discovered during Layer 64 was a real control-plane incident, not a synthetic test.

Before correction:

- control-plane incident state: **critical**
- incident event: `61ef5d92-5378-4d33-9ea7-29f4902a731f`
- projection state: **fail**
- reason: `release-identity-health-failed`
- bind-time publication ID: `e61ac83e-9a92-4185-88a8-9eea66ed8c2f`
- fresh publication ID: `b85352b5-cc49-43c5-a177-116e05302f6f`
- deployment receipt remained: `f79bde0b-588e-44a7-ac0f-d4f6e78bf986`
- runtime remained: `90`
- source remained: `1a8148a8eb748a19ac03107d9e9ec7313297384b`
- artifact remained: `3294e28293df667224ed9ab2551e2e5a6a88bab6f6805791bec14e7d22512692`

After the continuity correction:

- release identity health: **pass**
- matches current deployment: **true**
- matches current publication: **true**
- publication rotated since binding: **true**
- release projection: **aligned**
- canonical source truth: **pass**
- promotion closure: **closed**
- promoted release: **available**
- promoted release ref: `foundation:layer-58:1a8148a8`
- promoted release SHA-256: `ed4e6f4d7234161a6261fc98d58fd3bfd05ca35045fabfdc57dbf8c5ac51040f`

The existing control-plane sentinel then recorded a normal recovery event:

`79845c63-c300-4bb8-b544-e1cb44beb023`

Active release-projection incidents returned to **0**.

Layer 64 itself is deployed in production.

First observation:

- observation ID: `af340896-6a5a-48b3-836d-aa75d746d5b0`
- state: **promoted**
- changed from previous: **true**
- semantic fingerprint: `455ed6302781c52bf298e4a58bc22706c79cd1471a55a5d1b04c247120cff6df`

Immediate second observation:

- observation ID: `150ff573-0bbc-4511-96a1-7764beb2f620`
- state: **promoted**
- changed from previous: **false**
- semantic fingerprint unchanged

Production summary reports:

- state: **normal**
- observation fresh: **true**
- observation matches live: **true**
- recommended action: **none**
- automatic repair: **false**

Hosted job `shine-foundation-promoted-release-observation-5m` is active on the expected five-minute cadence.

Privilege proof:

- Foundation runtime ledger read: **yes**
- Foundation runtime summary read: **yes**
- Foundation runtime record: **no**
- service role recorder: **yes**
- service role direct ledger INSERT: **no**
- anonymous/authenticated summary read: **no**

Supabase advisor counts are unchanged from the previous Foundation layer and show no Layer-64-specific security or performance finding.

## Invariant

> CI proves the promotion contract. Layer 64 proves whether that same consumer trust is still true now, and says so durably without gaining authority to fix it.
