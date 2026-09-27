# Foundation Layer 16 — Explicit disconnect and grant revocation

**Status:** Built for review  
**Scope:** Shine Vault user-withdrawal boundary

Layer 16 completes the inverse of Layer 15 consent.

A user who explicitly granted one app access can explicitly withdraw that grant. Revocation is append-only, immediately removes the grant from the effective-access view and emits the existing revocation outbox event.

## Rule

Consent can be withdrawn.

Revocation requires:

1. the calling Shine backend proves its server-only app credential;
2. the user proves the already-bound active canonical Shine identity for that app;
3. the requested grant belongs to that identity and app;
4. the request is fresh;
5. Foundation performs one atomic append-only revocation.

The endpoint does **not** require Shine Defence approval. Defence may veto new access, but it cannot block a user from withdrawing existing access.

## Request

`POST /v1/grants/revoke`

The JSON envelope contains only request ID, app ID, grant ID and request time. Raw app/user credentials remain in transport headers.

## Persistence

`foundation.revoke_access_grant_v1` locks the target grant, re-checks owner and app binding, and inserts exactly one `user-revoked` event into the existing `grant_revocations` ledger.

Repeated revocation is idempotent and returns `already-revoked`.

The existing `grant_revocation_outbox` trigger emits `shine-foundation/grant-revocation-v1`, and `effective_access_grants` immediately reports the grant as `revoked`.

## Privacy boundary

A missing grant, a grant owned by a different Shine identity, and a grant belonging to another app all return the same `grant-not-found` denial from the database function. The response does not expose Shine ID, grant metadata or revocation IDs.

## Acceptance

Layer 16 is complete only when:

- gateway service tests pass;
- HTTP route tests pass;
- runtime adapter tests pass;
- PostgreSQL revoke/idempotency/outbox tests pass;
- the Foundation workflow is green.

No real user grant is revoked by CI acceptance.
