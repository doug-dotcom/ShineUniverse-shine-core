# Foundation Layer 16 — Explicit disconnect and grant revocation

**Status:** LIVE — repository reconciled with hosted Foundation  
**Scope:** Shine Vault user-withdrawal boundary

Layer 16 is the inverse of Layer 15 consent: a user can explicitly withdraw one app grant.

During repository reconciliation on 27 Sep 2026, the dedicated Shine Foundation project was found to already contain the richer production implementation:

- hosted function: `foundation-gateway` **v69 ACTIVE**;
- route: `POST /v1/grants/revoke`;
- historical database migration: `20260926143428 foundation_grant_revocation_flow_v1`;
- advisor-index migration: `20260926143628 foundation_grant_revocation_advisor_indexes_v1`.

The Core repository had lagged the hosted bundle. This layer backfills the production contract rather than replacing the live Gateway with the older repo snapshot.

## Rule

Consent can be withdrawn.

Revocation requires:

1. the calling Shine backend proves its server-only app credential;
2. the user proves the active canonical Shine identity already bound for that app;
3. the request explicitly sets `revoke: true`;
4. the request is fresh;
5. Foundation performs one atomic append-only revocation decision.

Revocation deliberately has **no Shine Defence approval dependency**. Defence may veto new access; it cannot prevent a user withdrawing access already granted.

## Production request

`POST /v1/grants/revoke`

Envelope:

- `grantRevocation: "shine-foundation/grant-revocation-v1"`
- `schemaVersion: "1.0.0"`
- `requestId`
- `appId`
- `grantId`
- `revoke: true`
- `requestedAt`

Raw app and user credentials remain in transport headers.

## Persistence and replay safety

`foundation.revoke_access_grant_v1` accepts an event ID, revocation ID, request ID, target grant ID, verified owner Shine ID, app ID and occurrence time.

The function:

- records every decision in append-only `foundation.grant_revocation_events`;
- treats `request_id` as the replay key;
- returns the original decision for a byte-equivalent logical replay;
- raises `grant-revocation-replay-conflict` if the same request ID is reused for another grant, owner or app;
- locks the target grant before changing revocation state;
- inserts at most one physical row in `foundation.grant_revocations`;
- returns `already-revoked` for a later request against an already withdrawn grant.

The existing revocation trigger emits the app revocation outbox event and `effective_access_grants` immediately reports the grant as revoked.

## Response boundary

The public response returns request ID, status and bounded reason code. Internal event IDs, canonical Shine ID and revocation ID are not returned.

## Repository acceptance

Layer 16 is represented correctly when:

- the gateway service uses the production `grant-revocation-v1` contract;
- the runtime adapter calls the seven-argument production database function;
- request replay and later-request idempotency are tested;
- append-only event history and outbox propagation are tested;
- Deno/Node/Postgres CI is green.

No production migration or Gateway deployment is required by this backfill: those production components were already live before the repository reconciliation.
