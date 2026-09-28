# Foundation Layer 49 — Owner handoff acknowledgement

**Status:** LIVE

Layer 49 separates **handoff delivery** from **owner acceptance**.

A Layer-48 handoff is not considered acknowledged merely because Foundation generated it. The addressed dependency owner must explicitly respond through its own database role.

## Responder identity

The production responder is:

`shine_defence_runtime`

Only that role may call:

`foundation.respond_readiness_dependency_remediation_handoff_v1(...)`

The following cannot acknowledge a Defence handoff:

- `service_role`
- `foundation_runtime`
- Foundation Gateway
- direct table insert by Defence runtime

The acknowledgement function is therefore the only write path.

## Response states

One handoff may receive exactly one response:

- `accepted`
- `rejected`
- `clarification-requested`

The response is append-only and single-use.

A later attempt returns the existing authoritative response rather than replacing it.

## Binding

Every response is integrity-bound to the exact:

- handoff ID;
- handoff SHA-256;
- proposal ID;
- proposal SHA-256;
- readiness incident event;
- semantic condition fingerprint;
- dependency routing fingerprint;
- owner component;
- dependency service.

A response automatically becomes stale if the underlying handoff becomes stale.

## No authority transfer

Acknowledgement never means approval to change anything.

Every response explicitly carries:

- approval granted: **false**
- execution authority granted: **false**
- executes action: **false**

An accepted response means only:

> the addressed owner accepts responsibility for investigation and evidence return for this exact handoff.

## Live freshness proof

Before production acknowledgement, Foundation ran a fresh Layer-46 readiness retest.

New health evidence added:

`runtime-degraded`

to the existing:

`dependency-degraded`

condition because Gateway p95 latency became elevated while the six dependency scopes remained degraded.

That fresh semantic condition caused the active readiness incident to append a `changed` event.

The previous Layer-47 proposal and Layer-48 handoff immediately became stale.

Old handoff:

`41a52b8e-2929-4a5d-98a8-098f670c5c60`

State:

**STALE**

Foundation then generated a fresh proposal:

`39c87b6a-9929-4bd3-b1ad-1b307ce9584e`

Condition fingerprint:

`e1660cefe946208018a2bb3ed3b04998`

and a fresh handoff:

`4c2d0de7-98b8-4a52-b20b-7901ae3b0b3c`

Owner:

- component: `universe`
- dependency service: `foundation.defence`

Scopes:

- context-operations
- control-operations
- credential-operations
- identity-operations
- permission-operations
- protected-operations

Fresh handoff state:

**CURRENT**

Integrity:

**VERIFIED**

## Production acknowledgement state

The available Supabase admin connector cannot authenticate as or assume `shine_defence_runtime`.

An attempt to impersonate that role was rejected by PostgreSQL.

Foundation deliberately did **not** grant admin/service membership in Defence merely to make the acknowledgement appear complete.

Current owner response state is therefore:

**PENDING**

This is the correct state until an authenticated Defence runtime invokes the response function.

## Production release

Layer 49 release:

`foundation:layer-49:1a8148a8`

Gateway remains:

**v90**

Release identity:

**PASS**

Release projection:

**ALIGNED**

Readiness:

**DEGRADED**

Active readiness incident:

**1 warning**

Current reasons:

- runtime-degraded
- dependency-degraded

Current handoff response:

**PENDING**

## CI

Full Foundation run:

`36428250870`

passed end-to-end.

CI proves:

- service role cannot acknowledge;
- Foundation runtime cannot acknowledge;
- Defence runtime can acknowledge;
- acceptance is append-only and single-use;
- accepted acknowledgement grants no execution authority;
- repeated response preserves the first authoritative response;
- stale handoff makes an existing acknowledgement stale.

## Advisors

Post-deployment:

- Layer-49 security findings: **0**
- no unindexed Layer-49 foreign keys
- response indexes are currently unused INFO because production has no owner response row yet

## Invariant

> Foundation may route work to an owner, but only the owner may acknowledge it. Lack of an authenticated owner response remains visible as pending rather than being forged by an administrator.
