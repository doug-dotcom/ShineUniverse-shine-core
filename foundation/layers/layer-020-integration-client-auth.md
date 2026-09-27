# Foundation Layer 20 — Integration client authentication

**Status:** LIVE — repository backfill of hosted Foundation  
**Scope:** registered integration-client credential verification + status

Layer 20 records the first protected surface of Foundation's open integration protocol already live in `foundation-gateway` v69.

Layer 19 made capability metadata public and established the integration-client credential store. Layer 20 proves which registered integration client is calling before any later user-link, consent, delegation or execution flow is allowed to trust that client identity.

## Production storage dependency

Layer 20 introduces **no new production migration**.

It depends on the Layer 19 production objects:

- `foundation.integration_clients`;
- `foundation.integration_client_credentials`;
- `foundation.integration_client_credential_revocations`;
- `foundation.effective_integration_client_credentials`.

The runtime hashes the supplied client token with SHA-256 and only accepts a credential whose effective status is `active`. Raw client tokens are not stored or returned.

## Endpoint

`GET /v1/integration/client/status?clientId=<client>`

Authentication:

- header: `x-shine-client-token`;
- the Edge handler rejects a missing token before the service runs;
- the service validates the requested client ID and compares it with the client proven by the credential.

A successful response returns only:

- the verified `clientId`;
- its `clientKind`;
- `authenticated: true`;
- the currently supported operation `capabilities.discover`.

## Authority boundary

**Client authentication is not user authorisation.**

A valid integration-client credential proves the identity of the calling integration client only. It does not:

- prove a Shine user's identity;
- link that client to a user;
- grant a capability;
- read Vault content;
- issue a delegation;
- invoke a specialist app;
- bypass later consent or permission checks.

A credential presented for a different `clientId` is explicitly denied as `integration-client-mismatch`.

Revoked, expired or disabled-client credentials disappear from the effective active credential view and therefore fail verification.

## Repository acceptance

Layer 20 is correctly represented when:

- the hosted `integration-client-status-v1.mjs` service is checked in exactly;
- the runtime adapter matches hosted credential verification;
- the HTTP route requires integration-client authentication;
- the Edge snapshot reads `x-shine-client-token` exactly as hosted v69 does;
- service, HTTP, runtime and Deno checks are green;
- the existing Layer 19 clean Postgres rebuild remains green.

No production deployment is required because this capability is already live.
