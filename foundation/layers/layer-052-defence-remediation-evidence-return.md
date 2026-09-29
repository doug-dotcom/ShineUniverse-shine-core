# Foundation Layer 52 — Defence remediation evidence return

**Status:** LIVE — release binding intentionally withheld by readiness gate

Layer 52 closes the owner-to-Foundation half of the dependency-remediation evidence loop.

Layers 48–50 established:

1. Foundation routes a current dependency-remediation proposal to its owner.
2. Only the addressed owner may acknowledge the handoff.
3. Defence has a least-privilege inbox for discovering pending work.

The missing boundary was the return path: an accepted owner had no authenticated, integrity-bound channel for returning investigation evidence to Foundation.

Layer 52 adds that channel.

## Evidence-return ledger

The append-only ledger is:

`foundation.readiness_dependency_remediation_evidence_returns`

Every row binds the returned evidence to the exact:

- handoff ID;
- accepted response ID;
- proposal ID;
- readiness incident event ID;
- handoff SHA-256;
- response SHA-256;
- proposal SHA-256;
- semantic condition fingerprint;
- dependency routing fingerprint;
- owner component;
- dependency service.

One handoff may have exactly one authoritative evidence return.

A repeated submission returns the existing packet rather than replacing it.

## Writer identity

Only:

`shine_defence_runtime`

may call:

`foundation.return_readiness_dependency_remediation_evidence_v1(...)`

The following cannot submit Defence evidence:

- `service_role`;
- `foundation_runtime`;
- Foundation Gateway;
- anonymous or authenticated application users.

Defence also receives **no direct INSERT or SELECT access** to the evidence ledger.

The function is therefore the sole Defence write path.

## Preconditions

Evidence may be returned only when:

- the handoff exists;
- it is addressed to `foundation.defence` / `universe`;
- the handoff is current;
- handoff integrity is verified;
- the owner response is current and `accepted`;
- owner-response integrity is verified;
- the response explicitly acknowledges ownership.

A stale handoff or non-accepted response makes evidence return not applicable.

## Bounded evidence shape

The owner supplies:

- owner-reported outcome:
  - `resolved`
  - `improved`
  - `unchanged`
  - `worsened`
  - `inconclusive`
- summary;
- bounded array of observed facts;
- bounded array of evidence references;
- optional recommended next step.

The owner-reported outcome is evidence only.

It does **not** become Foundation's readiness truth.

## Independent verification boundary

Every return packet explicitly states:

- `requiresIndependentRetest: true`
- `readinessChanged: false`
- `approvalGranted: false`
- `executionAuthorityGranted: false`
- `executesAction: false`

Even an owner-reported outcome of `resolved` therefore cannot recover Foundation by itself.

A separate Foundation semantic retest remains required.

## Status reader

The status reader is:

`foundation.get_readiness_dependency_remediation_evidence_return_status_v1(uuid)`

It reports:

- `pending` after an accepted current handoff with no evidence yet;
- `current` for an integrity-verified current evidence return;
- `stale` if the underlying handoff or acceptance becomes stale;
- `invalid` if the stored evidence hash no longer matches;
- `not-accepted` if the handoff has not been accepted.

The original append-only evidence is preserved even when its status becomes stale.

## CI proof

Full Foundation workflow:

`36512141629`

passed end-to-end.

CI proves:

- only `shine_defence_runtime` may submit;
- `service_role` cannot submit;
- `foundation_runtime` cannot submit;
- Defence cannot directly INSERT into the ledger;
- Defence cannot directly SELECT the ledger;
- a current accepted handoff can return evidence;
- the return is integrity hashed;
- replay preserves the first authoritative packet;
- evidence return does not change readiness;
- evidence return grants no approval or execution authority;
- stale handoff state makes returned evidence stale;
- all downstream Shine Defence acceptance tests remain green.

## Production deployment

The Layer-52 schema and functions are live.

Production privilege verification shows:

- Defence can execute the evidence-return function: **yes**
- service role can submit: **no**
- Foundation runtime can submit: **no**
- Defence direct ledger INSERT: **no**
- Defence direct ledger SELECT: **no**

Production ledger rows:

**0**

That is correct.

After Layer 51, the current incident is a Gateway runtime-health problem rather than a dependency problem, so there is no current accepted dependency-remediation handoff against which Defence could truthfully return evidence.

The previous handoff:

`4c2d0de7-98b8-4a52-b20b-7901ae3b0b3c`

is stale, and the Layer-52 status reader correctly reports its evidence-return state as stale.

No production evidence packet was fabricated merely to demonstrate the feature.

## Current readiness

At Layer-52 verification, Foundation remains:

- readiness: **not-ready**
- reason: `runtime-unhealthy`
- dependency impact: **operational**
- dependency scopes: **0**
- Gateway runtime: **v90**
- health reason: `critical-p95-latency`

The independent runtime-health issue is unchanged by Layer 52.

## Release identity

Layer 52 attempted the normal immutable release bind.

The binder rejected it with:

`release-identity-readiness-not-bindable`

because current readiness remains `not-ready`.

No bypass or ledger mutation was used.

The authoritative bound release remains:

`foundation:layer-49:1a8148a8`

Gateway remains:

**v90**

## Advisors

Post-deployment:

- no new Layer-52-specific security finding;
- both new evidence-return indexes appear as expected unused-index INFO because the production ledger has zero rows;
- pre-existing project-wide advisor notices are unchanged and unrelated to Layer 52.

## Invariant

> The owner may return evidence, but the owner may not declare Foundation recovered. Evidence is immutable input to an independent readiness retest, never authority to change readiness or execute remediation.
