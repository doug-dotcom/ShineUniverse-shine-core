# Foundation Layer 7 — Hosted Foundation goes live

**Status:** Complete  
**Date:** 2026-09-26  
**Scope:** dedicated Supabase project + live Edge Function

Layer 7 moves Foundation from deployment-ready source into its own hosted Supabase project.

## Dedicated project

- Project name: **Shine Foundation**
- Project ref: `sjpxqeyewahraxvidvcc`
- Region: `ap-southeast-2` (Sydney)
- Status at deployment: `ACTIVE_HEALTHY`

Foundation is not hosted inside Dive, Money, RC or another appendage project.

## Live database

The hosted project has applied:

1. `foundation_persistence_v1`
2. `foundation_runtime_v1`
3. `foundation_live_advisor_hardening_v1`
4. `foundation_gateway_role_assumption_v1`

The `foundation` schema contains the Core/ID/Vault persistence, grant/revocation/audit model, app credentials and runtime policies.

Every Foundation table has RLS enabled.

## Runtime role

The hosted `foundation_gateway` role is:

- `NOLOGIN`;
- `NOBYPASSRLS`;
- granted only the Foundation runtime privileges it needs.

Supabase Edge Functions provide `SUPABASE_DB_URL` automatically. The live Gateway opens that platform connection, but every Foundation query runs inside a transaction with:

```sql
SET LOCAL ROLE foundation_gateway;
```

The platform connection user was explicitly granted permission to assume this NOLOGIN role.

## Live Edge Function

- Function: `foundation-gateway`
- Version: `1`
- Status: `ACTIVE`
- Platform JWT verification: **enabled**

The deployed function requires both:

- a valid user JWT; and
- `X-Shine-App-Token` for the calling Shine backend.

## Hosted advisor result

After live hardening:

- Supabase security advisor: **0 lints**
- Unindexed-FK findings: resolved
- Remaining performance notices: fresh/unused indexes and default Auth connection allocation only

The trigger functions have fixed `search_path` values.

## Verification boundary

The deployment is verified through Supabase's control plane as ACTIVE, and the hosted database/runtime role assumptions are live-tested.

A direct HTTP `/health` request could not be issued from the assistant shell because that sandbox could not resolve the Supabase hostname. No successful health-response claim is made from that shell test.

The next end-to-end milestone is to provision a real Shine app registration + app credential + Shine ID binding + Vault grant and make the first authorised appendage request through the live Gateway.
