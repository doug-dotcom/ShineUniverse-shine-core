# Shine Foundation

Shine Foundation is the shared infrastructure layer that turns independent Shine applications into the connected Shine Universe.

Foundation is composed of three tightly coupled systems:

- **Shine Core** — app registry, shared service contracts, permission orchestration, event routing and app-to-app coordination.
- **Shine ID** — the canonical Shine identity and authenticated-session boundary.
- **Shine Vault** — protected user resources, explicit grants, consent state and auditable access.

Shine AI and Shine Defence remain independent Universe systems that Foundation integrates with. Foundation does not absorb them.

## Foundation principle

> Connected by choice, independent by design.

A Shine application must continue to provide its primary purpose without Foundation being available. Foundation may add identity, convenience, personalisation, cross-app coordination and shared intelligence, but it must not become a single point of failure for an application's core function.

The supported operating modes are:

1. **Standalone** — the app performs its primary function without Foundation.
2. **Connected** — the app uses Shine ID, Core and/or Vault services.
3. **Universe-enhanced** — the app can participate in authorised cross-app experiences coordinated through Core.

## Access model

Foundation uses a deny-by-default, least-privilege access flow:

1. Shine ID verifies the user identity and session.
2. Shine Core verifies the requesting app and requested scope.
3. Shine Vault evaluates whether the user has granted that app access to the specific resource/category.
4. Shine Defence may apply additional security and policy checks.
5. Foundation returns an explicit allow/deny decision.
6. The decision is auditable.

An app is never granted access to a user's entire Vault merely because the app belongs to the Shine Universe.

## Canonical contract

The machine-readable contract is:

- `contracts/foundation-v1.json`

Architectural decisions are recorded under:

- `adr/`


## Canonical object models

Foundation Layer 2 defines the first three machine-readable objects shared across the Universe:

- `schemas/app-manifest-v1.schema.json` — app identity, purpose, operating modes and requested scopes.
- `schemas/shine-identity-v1.schema.json` — canonical `shineId`, account lifecycle and auth-provider mappings.
- `schemas/vault-resource-v1.schema.json` — protected-resource ownership, classification, provenance and integrity envelope.

`object-registry-v1.json` pins these schemas to exact Git blob identities. CI runs `integration-kit/verify-object-registry-v1.mjs` and rejects silent schema drift.

The Layer 2 build record is `layers/layer-002-canonical-object-models.md`.


## Permission and grant engine

Foundation Layer 3 defines the access path joining Core, ID, Vault and Defence.

- `schemas/permission-request-v1.schema.json` — scoped app request.
- `schemas/access-grant-v1.schema.json` — explicit user/resource grant.
- `schemas/access-decision-v1.schema.json` — allow/deny result and reason.
- `schemas/grant-revocation-v1.schema.json` — grant termination event.
- `schemas/access-audit-event-v1.schema.json` — auditable decision record.
- `integration-kit/permission-engine-v1.mjs` — deterministic reference evaluator.

An allow requires a verified Shine ID, a registered app manifest declaring the requested scope/purpose, a matching active grant, a matching owned resource and no Shine Defence veto.

The Layer 3 build record is `layers/layer-003-permission-grant-engine.md`.


## Durable Foundation state

Foundation Layer 4 adds a deployment-ready PostgreSQL persistence model at `postgres/persistence-v1.sql`.

The private `foundation` schema stores app registrations, Shine identities, Vault resource metadata, immutable grant issuance, immutable revocations, a monotonic revocation outbox and an append-only allow/deny audit ledger.

Revocation is event-sourced rather than undone by editing a grant. `effective_access_grants` derives the current state from issuance + time window + revocation history.

GitHub CI validates the model against PostgreSQL 17, including RLS, private-role boundaries, active/revoked state derivation, duplicate-revocation rejection, exactly-once outbox emission and append-only history.

The Layer 4 build record is `layers/layer-004-persistence-and-revocation.md`.


## Foundation Gateway

Foundation Layer 5 adds the first callable Universe boundary.

`gateway/gateway-core-v1.mjs` evaluates one scoped access request through verified Shine ID, the Core app manifest, Vault metadata/effective grants, Shine Defence and the Foundation permission engine, then persists the audit record before returning a minimal decision.

`gateway/http-handler-v1.mjs` exposes the reference HTTP surface:

- `GET /health`
- `POST /v1/access/evaluate`

The Gateway short-circuits trust boundaries in order: an identity mismatch does not touch Core/Vault, and an undeclared app scope does not touch Vault/grants.

The public wire contracts are pinned in `object-registry-v1.json` and described by `gateway/openapi-v1.json`.

The Layer 5 build record is `layers/layer-005-foundation-gateway.md`.
