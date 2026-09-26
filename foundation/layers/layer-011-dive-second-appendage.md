# Foundation Layer 11 — Second appendage: Shine Dive

**Status:** Foundation live; Dive production bridge deploying  
**Date:** 2026-09-26  
**Pilot app:** Shine Dive

Layer 11 proves that Foundation onboarding works for an appendage that does **not** use a normal account JWT.

## Existing Dive identity model

Shine Dive already protects its online companion with a random 256-bit browser vault credential:

- raw token lives only in a Secure HttpOnly `__Host-` cookie;
- only the SHA-256 digest is stored in Dive Supabase;
- Dive's existing RLS policy hashes `x-shine-vault-token` and exposes only the matching private companion row;
- no email login is required.

Foundation preserves that model rather than replacing it.

## Opaque-session federation

Foundation identity federation v2 adds the app-approved provider kind:

`supabase-opaque-vault`

For Dive:

- provider: `supabase:dive-vault`;
- verification resource: `dive_companions`;
- subject field: `vault_hash`;
- verification header: `x-shine-vault-token`.

The Dive backend forwards the existing vault token to Foundation only in the private `X-Shine-User-Token` header.

Foundation:

1. authenticates the Dive backend with its server-only Shine app credential;
2. hashes the opaque user token;
3. verifies token possession against Dive's existing RLS-protected Supabase row;
4. maps the verified vault hash to canonical Shine ID;
5. continues through Core manifest, Vault grant, Defence and audit.

The raw vault token never enters the Gateway JSON envelope or the audit ledger.

## One Shine ID

The existing Dive vault is bound to the **same canonical Shine ID** already used by the owner's Shine Travel account.

Dive therefore becomes another authenticated doorway to the same person, not a second person inside Foundation.

## Pilot permission

- app: `shine.dive`
- scope: `vault.foundation.pilot.read`
- purpose: `dive.foundation-pilot`
- resource category: `foundation.pilot`

Dive reuses the owner's existing generic Foundation pilot resource and receives its own app-specific grant.

## Connection registry

Hosted Foundation currently derives:

- active credentials: **1**
- approved identity providers: **1**
- active grants: **1**
- observed production ALLOWs: **0**
- connection state: **grant-ready**

The state will automatically become `live-observed` after the first real signed-in / vault-authenticated Dive ALLOW.

## Dive runtime

The Dive Railway branch adds:

- `foundation-server.mjs` — server-only Gateway client;
- `GET /api/foundation/pilot`;
- backend forwarding of the HttpOnly vault token;
- a small Foundation status in the existing Saved Privately Online panel;
- optional/unavailable behaviour when Foundation cannot be reached;
- regression tests proving credentials are header-only and absent from Gateway JSON.

Standalone Dive logbook, planning, backup and recovery remain independent of Foundation.

## Hosted Foundation

- Gateway: **v7 ACTIVE**
- platform JWT precheck: disabled in favour of custom app + user-session verification
- security advisor: **0 lints**
- Foundation registry/contracts/runtime/persistence CI: **PASS**

## Acceptance boundary

Foundation and the Dive identity/grant registration are live.

At the time this layer was first recorded, Railway was serialising several Dive branch deployments. No production `dive.foundation-pilot` ALLOW had yet been observed, so this layer does not claim the real-user handshake until the final Dive build reaches production and a vault-authenticated browser opens the online companion.
