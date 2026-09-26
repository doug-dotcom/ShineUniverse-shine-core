# Foundation Layer 13 — Third appendage: Shine Ski

**Status:** Live at identity-ready  
**Date:** 2026-09-26  
**Pilot app:** Shine Ski

Layer 13 is the first appendage onboarded using the reusable Layer 12 connection-spec and shared backend-client pattern.

## Why Ski is different

Shine Ski is intentionally local-first:

- favourites remain in browser storage;
- packing and learning progress remain in browser storage;
- GPS activities remain in browser storage;
- no account is required;
- the shared Ski/Dive Supabase project supplies catalogue data, not personal Ski data.

Foundation therefore does not invent an account or automatically assert that an anonymous browser belongs to an existing canonical Shine identity.

## Opt-in pseudonymous session

The Railway build exposes an explicit **Connect to Shine** action.

Only after that action does the Ski backend create a random 256-bit browser credential:

- stored in a Secure HttpOnly host-only `__Host-shine_ski_foundation` cookie;
- only its SHA-256 digest is stored in `public.ski_foundation_sessions`;
- the table contains no favourites, packing data, GPS data, email address or canonical Shine ID;
- Supabase RLS verifies possession through `x-shine-ski-token`;
- session creation is locally rate-limited to six new sessions per source per hour.

Loading Ski without opting in creates no Foundation session row.

## Foundation identity provider

- app: `shine.ski`
- provider: `supabase:ski-session`
- kind: `supabase-opaque-vault`
- verification resource: `ski_foundation_sessions`
- subject field: `session_hash`
- verification header: `x-shine-ski-token`

The provider is explicitly approved only for Shine Ski through the Foundation app/provider registry.

## No automatic canonical claim

A verified Ski browser session is **not** automatically linked to a canonical Shine ID.

At Layer 13 acceptance:

- canonical Ski identity bindings: **0**
- active Ski pilot grants: **0**
- observed Foundation ALLOW decisions: **0**
- observed Foundation DENY decisions: **0**
- connection state: **identity-ready**

A separate explicit claim/link flow is required before Foundation may bind the pseudonymous session to an existing Shine ID and issue a personal Vault grant.

A parallel pilot grant created during development was revoked append-only because it predated the explicit identity-claim boundary.

## Reusable Layer 12 client

Ski vendors the exact Foundation shared backend client and uses Gateway request v2.

The browser never receives:

- the Foundation app credential;
- the raw canonical identity;
- a Vault grant ID.

The pseudonymous user token is forwarded server-to-server only in `X-Shine-User-Token` and never enters the Gateway JSON envelope.

## Status and disconnect

The Ski UI exposes:

- **Connect to Shine** — explicit session opt-in;
- **Shine session ready** — pseudonymous session exists but is not claimed;
- **Foundation connected** — reserved for a future claimed/granted session;
- **Disconnect** — deletes only the caller's own session anchor under RLS and clears the Secure HttpOnly cookie.

Read-only status checks verify the Ski session anchor directly and do not generate repeated expected Foundation denial audits.

## Production acceptance

Railway production deployment:

- commit: `da63cda823fc231970d3b1520764e5b402e751af`
- deployment id: `8b63a0bc-47ff-4a5a-b011-17edc45812d1`
- status: **SUCCESS**
- Shine Defence: **PASS**
- test files: **168 / 168 PASS**
- tests: **887 / 887 PASS**
- Railway bundle budget: **PASS**
- layer evidence gate: **PASS**
- production process: **Shine Ski listening on port 8080**

The hosted Ski/Dive Supabase security advisor reports no security lints for `ski_foundation_sessions`, and the hosted Foundation security advisor reports zero security lints.

At acceptance there are **0 live Ski session anchors**, proving deployment itself did not silently enroll a browser.

## Result

Shine Ski is the third registered appendage and deliberately stops at **identity-ready**.

This establishes a third onboarding pattern:

1. Travel — existing user JWT;
2. Dive — existing private opaque vault mapped to canonical Shine ID;
3. Ski — explicit pseudonymous session, intentionally unclaimed.

The next architectural step is an explicit identity claim/merge flow that can prove both the pseudonymous session and an existing canonical identity before linking them.
