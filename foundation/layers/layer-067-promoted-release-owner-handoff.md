# Foundation Layer 67 — Promoted-release owner handoff

**Status:** IMPLEMENTED — CI and production verification pending  
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

## Invariant

> An incident can create work ownership. It cannot create approval, execution authority or permission to bypass the controls that already govern release truth.
