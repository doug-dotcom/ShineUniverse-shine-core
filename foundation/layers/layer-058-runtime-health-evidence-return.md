# Foundation Layer 58 — Runtime-health investigation evidence return

**Status:** LIVE — real owner evidence returned and canonical release bound

Layer 58 closes the evidence-return seam in the Foundation Gateway runtime-health investigation workflow.

Layer 56 generated a cause-specific runtime-health investigation proposal.
Layer 57 delivered it to an isolated Shine-core owner capability and recorded explicit investigation ownership.
Layer 58 gives that accepted owner one bounded, immutable channel to return investigation findings to Foundation.

The owner evidence remains a claim and an input. It is not canonical Foundation health or readiness truth.

## Evidence-return authority

Writer:

`shine_core_control_plane`

Return function:

`foundation.return_readiness_runtime_health_investigation_evidence_v1(...)`

Status function:

`foundation.get_readiness_runtime_health_investigation_evidence_return_status_v1(...)`

Append-only ledger:

`foundation.readiness_runtime_health_investigation_evidence_returns`

The following cannot author a Shine-core runtime-health evidence return:

- `foundation_gateway`
- `foundation_runtime`
- `service_role`
- `shine_defence_runtime`
- anonymous clients
- authenticated clients

The owner also has no direct SELECT or INSERT privilege on the evidence ledger.

## Admission requirements

Evidence may be returned only when:

- the Layer-56 proposal exists;
- the proposal is current and integrity verified;
- the proposal is addressed to `shine-core` for `foundation.gateway`;
- Layer 57 contains a current, integrity-verified `accepted` owner response;
- the response is cryptographically bound to the same proposal and condition fingerprint.

One authoritative evidence packet is accepted per proposal.

A later replay returns the first immutable packet rather than replacing it.

## Owner evidence schema

Owner-reported outcomes:

- `resolved`
- `improved`
- `unchanged`
- `worsened`
- `inconclusive`

Owner-reported health states:

- `healthy`
- `degraded`
- `unhealthy`
- `unknown`

Bounded evidence fields include:

- summary: 1–2000 characters;
- observed facts: 1–50 strings, maximum 500 characters each;
- evidence references: 1–32 strings, maximum 1000 characters each;
- recommended next step: maximum 1000 characters;
- returned timestamp: bounded to the control-plane clock window.

## Canonical-truth boundary

Every Layer-58 evidence packet explicitly records:

- `ownerEvidenceIsCanonicalHealth: false`
- `ownerHealthClaimOnly: true`
- `requiresIndependentRetest: true`
- `readinessChangedByOwnerEvidence: false`
- `healthChangedByOwnerEvidence: false`
- `incidentClosurePerformed: false`
- `runtimeMutationAuthorityGranted: false`
- `healthPolicyMutationAuthorityGranted: false`
- `releaseRebindAuthorityGranted: false`
- `safeModeBypassAuthorityGranted: false`
- `approvalGranted: false`
- `executionAuthorityGranted: false`
- `executesRemediation: false`

Even an owner report of `resolved / healthy` cannot declare Foundation recovered.

## CI and production-schema verification

The first production-schema dry run exposed a contract mismatch before deployment.

Layer 58 originally expected Layer 57's response-status API to expose a `responseSha256` field.

Layer 57 intentionally did not expose that field.

Rather than widen the Layer-57 status contract, Layer 58 was corrected to verify the immutable accepted response directly:

- load the exact response row;
- hash the immutable response JSON;
- verify the stored response SHA-256;
- verify proposal ID;
- verify response ID;
- verify proposal SHA;
- verify condition fingerprint.

Commit:

`b7d3d64efe773e013cac474edda3e08ea9be1807`

A second dry run found the same invalid assumption inside Layer 58's status verifier.

That verifier was corrected to independently load and re-hash the immutable response row rather than trusting a non-existent status field.

Commit:

`e1c4b9a29710e2ceec63bbb291a0b6bc84a22da5`

After those corrections, the fully rolled-back production-schema dry run passed.

Functional Foundation CI:

`36534251454`

passed end-to-end, including:

- Layer-58 schema apply;
- Layer-58 evidence-return acceptance tests;
- immutable replay tests;
- stale-source tests;
- full downstream Shine Defence acceptance chain.

## Production privilege proof

Production verifies:

- Layer-58 ledger exists: **yes**
- return function exists: **yes**
- status function exists: **yes**
- Shine-core control plane can return evidence: **yes**
- Gateway can return owner evidence: **no**
- Foundation runtime can return owner evidence: **no**
- service role can author owner evidence: **no**
- Defence can author Shine-core evidence: **no**
- owner direct ledger SELECT: **no**
- owner direct ledger INSERT: **no**

## Real production evidence return

Layer 58 did not manufacture a placeholder packet.

The live investigation was based on:

- canonical synthetic health evidence;
- individual `pg_net` probe-result timing;
- Supabase Foundation Gateway Edge execution logs;
- current deployment/publication identity.

Proposal:

`019c701d-28b3-4b6f-a994-830a621ed30f`

Accepted Layer-57 response:

`e68085b2-7a0d-4773-8423-7164895578ce`

Evidence return:

`137119c6-5b5b-4881-b709-85e8e86e681f`

Evidence-return SHA-256:

`f0c3c1c79688fb647a78c6dfcbd5e295bf70d2fff3a684cb8265fd0ea0095315`

Owner report:

- outcome: **improved**
- health: **degraded**

Status:

- state: **current**
- integrity verified: **true**
- independent retest required: **true**

## Investigation findings

Foundation's canonical runtime-health p95 is derived from the synthetic public `/health` probes stored in:

`foundation.service_health_probe_results`

It is not the p95 of normal application traffic.

The collector aggregates probe `roundtrip_ms` over the health-policy evaluation window.

### Synthetic probe behaviour

Recent valid probe round trips varied dramatically.

Examples included approximately:

- **22.7 ms**
- **23.6 ms**
- **26.0 ms**
- **27.7 ms**
- **3.38 s**
- **3.49 s**
- **4.86 s**
- **5.92 s**
- **6.87 s**
- **10.02 s**
- **10.13 s**

The sampled probes:

- returned HTTP 200;
- reported `contract_ok=true`;
- did not time out;
- recorded no runtime error.

### Matching Edge execution

Matching Supabase Foundation Gateway `/health` Edge execution logs for runtime v90 in `ap-southeast-2` showed the health handler itself remaining fast.

Observed execution times were approximately:

**89–422 ms**

Examples:

- the synthetic sample with a **10.125 s** round trip had an Edge execution time of approximately **104 ms**;
- the synthetic sample with a **3.383 s** round trip had an Edge execution time of approximately **137 ms**.

The evidence therefore indicates that the dominant synthetic-probe delay occurs outside the health-handler computation path — in the request/transport/queue path before or around Edge execution.

That is an evidence-based attribution, not a claim that one exact external subsystem has yet been proven as the sole root cause.

## Normal application traffic — diagnostic context only

Normal Gateway route latency is useful supporting context but does not drive Foundation's canonical health p95.

A Supabase Edge-log aggregation over runtime v90 showed examples such as:

- Concierge retry claim, `ap-south-1`: p95 approximately **11.227 s**, no 5xx;
- revocation feed, `us-west-1`: p95 approximately **4.948 s**, no 5xx;
- revocation status, `us-west-1`: p95 approximately **4.046 s**, no 5xx;
- public `/health`, `ap-southeast-2`: p95 approximately **337 ms** over the compared Edge-execution window.

This reinforces that route/geographic latency deserves separate investigation, but it must not be confused with the synthetic health-policy measurement.

## Current canonical health

At the final Layer-58 binding check, current health evidence was:

`health-probe-window:foundation.gateway:production:90:1622`

Measurements:

- runtime: **v90**
- health: **degraded**
- reason: `elevated-p95-latency`
- average synthetic round trip: **2919.166 ms**
- p95 synthetic round trip: **6343.597 ms**
- request count: **12**
- HTTP 5xx: **0**
- runtime errors: **0**

Policy:

- warning p95: **5000 ms**
- critical p95: **10000 ms**

Foundation readiness therefore remains:

- state: **degraded**
- safe mode: **degraded**
- privileged operations: **degraded**
- worker operations: **degraded**
- dependency impact: **operational**
- dependency affected scopes: **0**

This is improvement from the earlier critical state, not full recovery.

## Release identity

Because current readiness remains legitimately `degraded`, the normal immutable release binder is permitted to bind.

Layer 58 used the normal binder with no bypass.

New canonical release:

`foundation:layer-58:1a8148a8`

Binding ID:

`187d5232-83b5-4c2f-acc6-62da7a9a9515`

Bound readiness:

`degraded`

Readiness fingerprint:

`fc3a81c0bb3aacae8959e1238bc646b4`

Gateway remains:

**v90**

Deployment source remains:

`github://doug-dotcom/ShineUniverse-shine-core/commit/1a8148a8eb748a19ac03107d9e9ec7313297384b`

Artifact SHA-256 remains:

`3294e28293df667224ed9ab2551e2e5a6a88bab6f6805791bec14e7d22512692`

Publication assurance remains:

`github-oidc`

## Advisors

Post-deployment security advisors show no Layer-58-specific security finding.

Existing project-wide notices remain:

- internal RLS-enabled tables with no policy;
- `pg_net` installed in the public schema.

Performance advisors show no Layer-58 unindexed foreign-key finding.

The two new evidence-return indexes appear as expected unused-index INFO while the production ledger contains only one evidence packet.

## Invariant

> Shine-core may report what its investigation found. Foundation may use that report as evidence to measure again. The owner report itself can never become canonical health, readiness, recovery or repair authority.
