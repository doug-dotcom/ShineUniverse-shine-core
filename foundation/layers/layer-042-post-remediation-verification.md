# Foundation Layer 42 — Post-remediation verification and controlled closure

**Status:** LIVE

Layer 42 separates **mutation success** from **remediation success**.

A Layer-41 execution may successfully change canonical state, but that alone cannot close a Foundation incident. A separately held verifier must obtain a fresh Layer-36 release-projection observation and prove the invariant is actually restored.

## Separate verifier authority

Role:

`foundation_remediation_verifier`

It is NOLOGIN / NOINHERIT and is not inherited by service, approver, admission-executor or mutator roles.

Only the verifier may execute:

`foundation.verify_scoped_remediation_v1(...)`

The verifier cannot directly insert verification evidence and cannot mutate canonical truth.

## Independent evidence

Verification calls:

`foundation.record_foundation_release_projection_observation_v1(...)`

after the Layer-41 execution.

It does not trust the executor's after-snapshot as closure evidence.

## Outcomes

### verified

Fresh projection is `aligned` or `degraded`.

Layer 42 then delegates recovery to the existing Layer-37 lifecycle:

`foundation.transition_foundation_control_plane_incident_v1(...)`

A `recovered` incident event is appended.

### unresolved

Fresh projection remains `fail` or `unknown`.

The verification event records the fresh evidence, but incident closure is not permitted.

### denied

Verification is denied when the referenced execution was not successful or when a later active incident event means the old execution no longer owns the current incident evidence.

## Evidence ledger

Append-only ledger:

`foundation.remediation_verification_events`

It binds verification to execution, admission, approval receipt, incident, action, fresh projection observation and optional recovery transition.

Each verification document has a SHA-256 integrity hash.

## Acceptance coverage

CI proves:

- successful SQL execution with a still-failing fresh projection becomes `unresolved`;
- unresolved verification leaves the incident `opened`;
- a fresh aligned projection becomes `verified`;
- verified remediation appends the existing Layer-37 `recovered` transition;
- failed execution cannot verify or close an incident;
- Layers 39-41 single-use approval/admission/execution constraints remain intact while testing Layer 42;
- service and mutator roles cannot verify;
- verification authority remains separately held.

Green integration run:

`36414487106`

## Production

Release:

`foundation:layer-42:1a8148a8`

Gateway remains runtime v90 with GitHub-OIDC deployment evidence.

Current production:

- release identity: PASS
- release projection: ALIGNED
- incident state: NORMAL
- active incidents: 0
- verification control health: PASS
- verification events: 0

Promotion itself created no remediation-verification evidence.

## Advisor hardening

Layer-42 security advisors are clean.

All verification-ledger foreign keys now have covering indexes. Remaining performance notices are only unused-index INFO because production has zero verification rows.

## Closure invariant

> A mutation may change truth, but only a fresh independent observation may prove that truth is healthy again.

Execution success does not close an incident.

Observed recovery does.
