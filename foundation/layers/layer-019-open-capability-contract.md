# Foundation Layer 19 — Open capability contract

**Status:** LIVE — repository backfill of hosted Foundation  
**Scope:** public capability metadata + registered integration-client trust surface

Layer 19 records Foundation's open, companion-agnostic integration contract already live in `foundation-gateway` v69.

The layer lets any caller discover what specialist Shine apps declare they can do, while keeping identity, user consent, grants, Vault access and execution behind separate authenticated/authorised Foundation flows.

## Production migrations

- `20260927010852 foundation_open_capability_contract_v1`
- `20260927011117 foundation_integration_client_fk_index_v1`

The migration creates:

- `foundation.app_capabilities`, the portable specialist-app capability catalogue;
- `foundation.integration_clients`, the registered caller catalogue;
- append-only integration-client credentials and credential revocations;
- `foundation.effective_integration_client_credentials`;
- `foundation.list_discoverable_capabilities_v1(text)`;
- the integration-client credential FK index added by the follow-up advisor migration.

The initial catalogue declares:

- `travel.plan_trip`;
- `dive.destination_brief`;
- `ski.destination_brief`.

All three begin in `declared` state, so discovery reports `invocable: false`.

## Endpoint

`GET /v1/integration/capabilities`

Optional filter:

`GET /v1/integration/capabilities?appId=shine.travel`

The discovery endpoint is intentionally public. It returns metadata only and sets:

- `integrationProtocol: shine-foundation/open-integration-v1`;
- `companionAgnostic: true`;
- `executionRequiresAuthorization: true`.

## Authority boundary

Discovery is **not authorisation**.

Layer 19 does not link a user, prove user identity, issue a grant, expose Vault data, create a delegation, or execute a specialist capability. An `invocable` flag only reflects the catalogue's invocation state; it is not consent and it is not permission.

Registered integration clients are also not privileged exceptions. A client credential proves which integration client is calling later protected surfaces; user authority still comes from the relevant identity, link, consent and grant contracts.

Direct database access remains private to Foundation runtime/service roles. Public callers reach the curated discovery response through the Gateway, not the underlying tables or SQL function.

## Repository acceptance

Layer 19 is correctly represented when:

- the hosted discovery service is checked in exactly;
- the historical production migrations are recorded;
- runtime adapter, public HTTP route and Edge composition match hosted v69;
- clean Postgres rebuild verifies catalogue isolation, DB privileges and integration-client credential revocation state;
- Node/Deno/Postgres CI is green.

No production deployment is required because the capability is already live.
