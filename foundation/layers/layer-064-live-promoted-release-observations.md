# Foundation Layer 64 — Live promoted-release observations

**Status:** IMPLEMENTED — CI and production promotion pending  
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

## Invariant

> CI proves the promotion contract. Layer 64 proves whether that same consumer trust is still true now, and says so durably without gaining authority to fix it.
