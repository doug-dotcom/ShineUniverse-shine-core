# Shine Foundation

Shine Foundation is the shared infrastructure layer that turns independent Shine applications into the connected Shine Universe.

Foundation is composed of three tightly coupled systems:

- **Shine Core** — app registry, shared service contracts, permission orchestration, event routing and app-to-app coordination.
- **Shine ID** — the canonical Shine identity and authenticated-session boundary.
- **Shine Vault** — protected user resources, explicit grants, consent state and auditable access.

Shine AI and Shine Defence remain independent Universe systems that Foundation integrates with. Foundation does not absorb them.

## Foundation principle

> Connected by choice, independent by design.

A Shine application must continue to provide its primary purpose without Foundation being available.

The supported operating modes are:

1. **Standalone** — the app performs its primary function without Foundation.
2. **Connected** — the app uses Shine ID, Core and/or Vault services.
3. **Universe-enhanced** — the app participates in authorised cross-app experiences coordinated through Core.

## Access model

Foundation uses a deny-by-default, least-privilege flow:

1. Foundation authenticates the **calling Shine app backend**.
2. Shine ID verifies the **user identity and session**.
3. Shine Core verifies the app manifest and exact requested scope/purpose.
4. Shine Vault evaluates the matching protected resource and grant.
5. Shine Defence may veto the request.
6. Foundation writes the audit evidence.
7. Only then does the Gateway return allow/deny.

An app is never granted access to a user's entire Vault merely because it belongs to Shine.

## Canonical contracts

- `contracts/foundation-v1.json` — Universe contract.
- `schemas/` — pinned Core / ID / Vault / permission / Gateway objects.
- `object-registry-v1.json` — exact Git identities for canonical schemas.
- `adr/` — accepted architectural decisions.

## Build layers

- **Layer 1** — Universe contract.
- **Layer 2** — Core / ID / Vault canonical objects.
- **Layer 3** — permission and grant engine.
- **Layer 4** — durable grants, audit ledger and revocation propagation.
- **Layer 5** — Foundation Gateway.
- **Layer 6** — Supabase runtime, app attestation and deployable Edge Function.

## Durable state

`postgres/persistence-v1.sql` creates the private Foundation state model.

`postgres/runtime-v1.sql` adds app credentials, their revocation model, a dedicated least-privilege `foundation_gateway` database login and the RLS policies it needs.

Audit caller claims are deliberately not foreign-keyed to authority tables: unknown apps and bogus identities must still be deny-able and auditable.

## Foundation Gateway

`gateway/gateway-core-v1.mjs` is the shared access boundary.

`gateway/http-handler-v1.mjs` exposes:

- `GET /health`
- `POST /v1/access/evaluate`

Connected app backends send both a user bearer JWT and `X-Shine-App-Token`. Browser/mobile clients must never embed app credentials.

## Supabase runtime

`runtime/supabase-runtime-adapters-v1.mjs` implements the real Supabase/Auth/Postgres adapters.

`runtime/edge-function/index.ts` is the deployable `foundation-gateway` Edge Function. The deployment contract is `runtime/deployment-v1.json`.

The runtime uses pinned dependencies and a serverless transaction-pooler database connection with prepared statements disabled.

## Current hosting status

**Shine Foundation is live in its own dedicated Supabase project.**

- Project ref: `sjpxqeyewahraxvidvcc`
- Region: `ap-southeast-2`
- Live function: `foundation-gateway` v1
- Platform JWT verification: enabled
- Hosted Supabase security advisor: 0 lints

The Edge Function uses Supabase's built-in database connection but scopes every Foundation query with `SET LOCAL ROLE foundation_gateway`, where `foundation_gateway` is NOLOGIN and does not bypass RLS.

See `layers/layer-007-hosted-foundation.md` and `runtime/hosted-deployment-v1.json` for the live deployment record.
