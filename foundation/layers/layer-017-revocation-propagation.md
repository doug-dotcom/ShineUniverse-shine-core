# Foundation Layer 17 — Revocation propagation, receipts and freshness

**Status:** LIVE — repository backfill of hosted Foundation
**Scope:** app-scoped revocation delivery after user consent withdrawal

Layer 16 makes revocation durable. Layer 17 closes the distribution loop so an app can prove it has consumed that revocation.

The hosted Shine Foundation project already has this capability live in `foundation-gateway` v69. Core is being reconciled to the production source of truth.

## Production migrations

- `20260926143912 foundation_app_revocation_feed_v1`
- `20260926145550 foundation_revocation_ack_checkpoint_v1`
- `20260926221323 foundation_revocation_delivery_receipts_v1`
- `20260926221929 foundation_revocation_freshness_policy_v1`

## App feed

`GET /v1/revocations?appId=<app>&after=<cursor>&limit=<1..100>`

The caller proves the app credential only. Foundation filters the global revocation outbox through the original access grant, so each app receives only its own revocations.

The caller cannot request a cursor ahead of its acknowledged checkpoint.

When events are served, Foundation writes an append-only delivery receipt containing the exact ordered sequence numbers returned. The receipt ID is required for acknowledgement.

## Acknowledgement

`POST /v1/revocations/ack`

The app submits:

- request ID;
- delivery receipt ID;
- app ID;
- terminal sequence number;
- request time.

`ack_app_revocations_v2` advances the app checkpoint only when the referenced delivery exists, belongs to that app, ends at that exact sequence, and covers every app-specific pending event between the old checkpoint and the requested terminal cursor.

Request-ID replay is idempotent. Checkpoint regression and cross-app acknowledgement are denied.

## Freshness

`GET /v1/revocations/status?appId=<app>`

Foundation derives:

- acknowledged checkpoint;
- latest app-specific revocation sequence;
- pending event count;
- oldest pending time;
- pending age;
- maximum allowed pending age;
- freshness state: `current`, `pending`, or `stale`;
- configured stale action and recommended action.

Default policy is 900 seconds and observe-only. Per-app policy may select `observe`, `degrade-connected`, or `deny-connected`.

## Boundary

This layer reports and transports revocations. It does not recreate consent, expand permissions, or mark a revocation processed merely because it was served.

Delivery and acknowledgement evidence are append-only.

## Repository acceptance

Layer 17 is correctly represented when:

- live feed/ack/health gateway services are checked in;
- the repo runtime adapter uses the live production functions;
- HTTP routes use app-only authentication;
- delivery receipt coverage, checkpoint progression and app isolation are tested;
- Node, Deno and Postgres CI are green.

No production deployment is required: the hosted capability already exists in Gateway v69.
