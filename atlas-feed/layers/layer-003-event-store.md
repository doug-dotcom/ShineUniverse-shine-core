# Atlas Feed — Layer 3: append-only event store and persistence receipts

## Goal

Turn an admitted Atlas signal into durable Universe evidence **exactly once**, without turning Atlas into the source app's system of record.

## Write path

`POST /v1/atlas-feed/publish` performs:

1. the existing Gateway Defence-backed operation policy;
2. Layer-2 publisher admission for the exact event;
3. canonical SHA-256 event and payload hashing;
4. append-only persistence in `foundation.atlas_feed_events`;
5. creation of one stable persistence receipt in `foundation.atlas_feed_persistence_receipts`.

No caller can bypass Layer 2 through the HTTP route.

## Idempotency

- Same request + same event → existing receipt.
- New request + same event id + same canonical event hash → existing receipt.
- Same request + different event → conflict.
- Same event id + different canonical event hash → conflict.
- Exactly one event row and one stable receipt may exist per event id.

The store uses transaction-scoped advisory locks for request and event identities so concurrent retries cannot create duplicate rows.

## Append-only boundary

Both event and receipt tables:

- have RLS enabled;
- grant no access to `anon` or `authenticated`;
- grant the Foundation Gateway **no direct table privileges**;
- expose writes only through the narrowly granted `foundation.persist_atlas_feed_event_v1` function;
- revoke that function from `PUBLIC`, `anon` and `authenticated`;
- reject `UPDATE` and `DELETE` through the shared append-only trigger.

The store is in the private `foundation` schema and is **not** added to Realtime publication. Explicit restrictive deny policies cover `anon` and `authenticated`, and all composite foreign keys have covering indexes.

## Stored evidence

Each event preserves:

- source app, live capability, credential and source release;
- topic and subject;
- occurrence/publication/freshness timing;
- audience/data class and bounded owner/grant context;
- provenance and evidence references;
- payload schema identity/version;
- payload plus payload SHA-256;
- canonical event SHA-256;
- exact Layer-2 admission snapshot;
- persistence time.

Each receipt binds the request id, event id, publisher/capability, hashes and persistence time and carries its own SHA-256.

## Still not claimed

Layer 3 does not define:

- consumer discovery;
- consumer read permission;
- subscriptions;
- Realtime/Broadcast;
- delivery guarantees;
- retention/deletion policy;
- replay cursors.

Expiry is stored as event metadata; it does not delete historical evidence.

## Next layer

Layer 4 should add the **consumer query boundary**: authorised, freshness-aware reads that enforce audience/owner/grant semantics without exposing the raw private event tables.
