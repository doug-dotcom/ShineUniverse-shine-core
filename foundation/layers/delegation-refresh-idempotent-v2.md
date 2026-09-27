# Foundation — Idempotent delegation refresh v2

**Status:** Production live  
**Foundation Gateway:** v62  
**Database migration:** `foundation_delegation_refresh_idempotent_v2`  
**Primary client:** native Shine Companion (`shine.companion`)

## Problem closed

A rotating refresh credential is intentionally one-time. That is secure, but a network
failure after Foundation commits a rotation and before the client receives the response
can otherwise strand a correctly behaving client: retrying the old refresh would look
exactly like credential replay.

## v2 protocol

The client creates and durably stages its next delegation and refresh secrets before
calling Foundation. Only these values cross the Foundation boundary:

- an opaque rotation request id;
- opaque next session and refresh ids;
- SHA-256 of the staged next delegation token;
- SHA-256 of the staged next refresh token.

The old raw refresh credential is transported only in `X-Shine-Refresh-Token`.
The existing client credential remains in `X-Shine-Client-Token`.

Foundation never receives or returns the raw next credentials in v2.

## Idempotency and replay

`foundation.rotate_delegation_refresh_v2` locks the old raw refresh credential row
before evaluating state.

If the exact same rotation request id, old credential, next ids and next hashes are
presented again, Foundation returns the previously committed session/refresh metadata
with `replayed: true`. This is a safe lost-response retry.

If a consumed refresh is presented under a different request or different staged
credentials, it remains a security replay. Foundation records the denial and revokes
the still-active descendant refresh credentials and delegation sessions for that
approved link/client.

## Companion durability

Shine-L keeps raw authority on the client side in Supabase Vault. Its companion refresh
ledger stages candidate secrets and a one-at-a-time lease before the remote call.
A network failure leaves the exact pending rotation available for retry. Successful
Foundation metadata promotes the staged secrets to current authority. Hard replay or
credential failures quarantine the local connection instead of retrying indefinitely.

No new capability, user grant, purpose or resource permission is created by renewal.

## Production verification

Rollback-only production proofs verified:

1. first v2 rotation succeeds;
2. repeating the exact request returns the original committed ids as an idempotent retry;
3. a distinct reuse of the consumed credential returns `refresh-reuse-detected`;
4. the child refresh credential and delegated session are then ineffective;
5. all synthetic proof rows are rolled back.

Supabase security advisers report zero Foundation-project security lints after the
migration and Gateway deployment.

## Repository note

The checked-in Core runtime entrypoint predates several later hosted Foundation modules.
This change records and unit-tests the v2 service and production migration without
pulling unrelated hosted modules into the older runtime snapshot. The hosted v62
bundle is the deployment source of truth for the current Gateway composition.
