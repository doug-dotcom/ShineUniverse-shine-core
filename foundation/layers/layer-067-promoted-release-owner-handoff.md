# Foundation Layer 67 — Promoted-release owner handoff

**Status:** LIVE — CI green, production owner-work materialiser active and healthy baseline verified  
**Scope:** convert persistent promotion-trust incidents into immutable Shine Core work ownership without creating execution authority

Layer 65 creates a persistent incident.

Layer 66 decides which response actions are allowed.

Layer 67 turns that approved response context into owned work.

## Why a separate handoff

The existing Layers 48–50 handoff path is intentionally readiness/dependency-specific and routes dependency scopes to their registered owners.

Promotion trust is a different domain.

Layer 67 therefore reuses the same architectural principles without pretending a promotion-trust incident is a dependency-remediation proposal.

## Owner route

The canonical service is:

`foundation.gateway`

Its owner is resolved from:

`foundation.service_registry`

Production currently resolves to:

`shine-core`

The owner component is not hard-coded as authority. If the service registry owner changes, an old handoff becomes stale.

## Handoff creation

Generator:

`foundation.generate_foundation_promoted_release_owner_handoff_v1(...)`

A handoff is generated only when:

- Layer 65 reports an active **warning** or **critical** incident;
- the current incident event is **opened** or **changed**;
- the current event exists in the append-only Layer-65 incident ledger;
- its evidence fingerprint matches the summary;
- Layer 66 cause and response plan agree with the incident;
- Layer 66 still declares `authorityExpansion: false`;
- Layer 66 still declares `automaticRepairAllowed: false`;
- `foundation.gateway` has an active registered owner.

Healthy or watching states create no owner handoff.

## Semantic response-plan binding

The handoff does not hash volatile `evaluatedAt` timestamps.

It binds a semantic SHA-256 over:

- incident/trust state;
- cause class;
- source domain;
- next evidence action;
- authority-expansion flag;
- automatic-repair flag;
- Layer-38 release-truth authority;
- each action key, action class, decision, required control and mutation flags.

The same plan evaluated one minute later therefore remains the same plan.

A real decision/control change produces a new fingerprint and makes the old handoff stale.

## Requested work versus authority

The handoff carries only Layer-66 actions whose decision is:

- `admit`; or
- `approval-required`.

That does **not** convert approval-required work into approved work.

Every packet explicitly says:

- `approvalGranted: false`
- `executionAuthorityGranted: false`
- `executesAction: false`

The packet also prohibits:

- automatic authoritative repair;
- bypassing Layer 38;
- suppressing/deleting incident history;
- claiming runtime readiness from promotion trust.

## Staleness

A handoff is current only while all of these remain true:

- incident is still warning/critical;
- the same incident event is current;
- the semantic Layer-66 plan is unchanged;
- the owner service is active;
- the registered owner component is unchanged;
- the handoff SHA-256 verifies.

Recovery immediately makes old work stale.

## Hosted ownership materialisation

Layer 65 incident sentinel runs at minutes ending `:01/:06/.../:56`.

Layer 37 projection incident reconciliation runs at `:02/:07/.../:57`.

Layer 67 materialises owner work at:

`:03/:08/.../:58`

This keeps observation, incident evaluation and ownership as separate controls.

## Acceptance coverage

Initial full Foundation CI run `36678295779` completed successfully and proved the Layer-67 handoff lifecycle across the full Foundation/Defence persistence chain.

The first production advisor sweep then found one Layer-67 INFO issue: `owner_service_id` had no dedicated covering index. The missing index was added immediately and the full Foundation run `36678585689` completed successfully with the handoff migration, FK index and Layer-67 tests all green.

CI proves:

- healthy state creates no handoff;
- semantic plan fingerprint ignores `evaluatedAt`;
- critical current incident generates one Shine Core handoff;
- requested actions include admitted and approval-required work but exclude denied work;
- replay is idempotent;
- current packet verifies integrity and owner routing;
- recovery stales the old packet;
- recovered state exposes zero current work;
- service role cannot directly insert;
- Foundation runtime cannot generate handoffs;
- Foundation runtime can read current owner work;
- browser roles cannot;
- handoff history is append-only.
- the owner-service foreign key has a dedicated covering index;

## Production proof

Layer 67 is deployed in the Shine Foundation Supabase project.

Current production is healthy, so the generator correctly returns:

- status: **not-applicable**
- reason: `promoted-release-incident-not-active`
- approval granted: **false**
- execution authority granted: **false**
- executes action: **false**

Current owner-work summary:

- incident state: **normal**
- trust state: **normal**
- active promotion-trust incidents: **0**
- current owner handoffs: **0**
- owner service: `foundation.gateway`
- owner component: `shine-core`

Hosted materialiser:

`shine-foundation-promoted-release-owner-handoff-5m`

is active at:

`3,8,13,18,23,28,33,38,43,48,53,58 * * * *`

Production privilege proof:

- Foundation runtime ledger read: **yes**
- Foundation runtime status read: **yes**
- Foundation runtime summary read: **yes**
- Foundation runtime handoff generation: **no**
- service role generation: **yes**
- service role direct ledger INSERT: **no**
- anonymous/authenticated summary read: **no**

Advisor hardening:

- the Layer-67 unindexed foreign-key finding for `owner_service_id` was removed by the dedicated covering index;
- no Layer-67-specific security finding is present;
- the three Layer-67 indexes currently appear under `unused_index` INFO because the healthy production baseline has created zero handoff rows. They are retained for the incident, owner-routing and environment/time query paths when owner work exists.

## Invariant

> An incident can create work ownership. It cannot create approval, execution authority or permission to bypass the controls that already govern release truth.
