# Foundation Layer 18 — App operational status

**Status:** LIVE — repository backfill of hosted Foundation  
**Scope:** read-only unified runtime status

Layer 18 joins Foundation's existing app connection state with revocation-delivery freshness into one app-authenticated operational status.

The capability is already live in hosted `foundation-gateway` v69. Core is recording the production design rather than deploying a replacement.

## Production migrations

- `20260926235144 foundation_app_operational_status_v1`
- `20260926235208 foundation_connection_status_runtime_select_v1`
- `20260926235253 foundation_app_operational_status_function_v1`

The first implementation used a security-invoker view. Production then replaced it with the final security-definer `get_app_operational_status_v1` function and removed the temporary runtime SELECT grant on `app_connection_status`.

## Endpoint

`GET /v1/status?appId=<app>`

The caller proves that app's server credential. Foundation returns the database-derived status only for that verified app.

## Output

The status contains:

- registry state and standalone-primary-purpose flag;
- connection state and connection evidence counts;
- revocation checkpoint/latest sequence/pending count and freshness;
- `operationalState`;
- `operationalHealth`.

With no pending revocations, operational state follows the existing connection state and health is `healthy`.

A fresh pending revocation becomes `revocation-pending` / `attention`.

A stale revocation is labelled according to the configured `staleAction`:
`observe`, `degrade-connected`, or `deny-connected`.

## Authority boundary

This is a **status layer**.

An observe-only stale policy changes status, not access. The function does not create or revoke grants, alter a checkpoint, expand capability, or independently enforce a denial. Enforcement requires a separate explicit layer.

## Repository acceptance

Layer 18 is correctly represented when the hosted service and function are checked in, the runtime adapter and app-only HTTP route match v69, clean and pending-revocation states are tested, and Node/Deno/Postgres CI is green.

No production deployment is required because the capability is already live.
