# Foundation Layer 9 — Live Shine Defence status feed

**Status:** Complete  
**Scope:** public read-only release trust metadata

Layer 9 gives standalone Shine apps a live Foundation source for current Defence badge status without embedding a self-invalidating receipt into the app repository.

## Endpoint

`GET /v1/defence/status/{appId}?releaseSha=<40hex>&profileBlobSha=<40hex>`

The Supabase function-prefixed path is also accepted.

## Why this exists

A certification receipt binds an exact app commit. Committing that receipt back into the same app changes the app commit and immediately makes the receipt historical. A central status service breaks that loop.

The service evaluates the app's supplied commit/profile identity against Core's reviewed ecosystem ledger and current append-only revocation ledger.

## Public boundary

This route is deliberately unauthenticated because it exposes only published Defence governance metadata:

- app id;
- reviewed commit/profile identities;
- reviewed profile version;
- certified policy ids;
- current status;
- public revocation reason when applicable.

It never exposes Shine ID, Vault resources, grants, credentials, audit rows or private app data.

Responses are `no-store`.

## States

- `reviewed_release`
- `revoked_release`
- `unreviewed_revision`
- `profile_drift`
- `uncertified`

Only `reviewed_release` has `badgeCurrent:true`.

## Verification

Node tests cover all release states, revocation precedence, malformed requests, public unauthenticated access, no-store responses and the existing authenticated access-evaluation boundary. Deno checks the production Edge Function imports the canonical Defence ledgers.
