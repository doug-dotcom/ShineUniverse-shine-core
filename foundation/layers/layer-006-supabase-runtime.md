# Foundation Layer 6 — Supabase runtime and app attestation

**Status:** Complete (deployment-ready; not hosted yet)  
**Scope:** Supabase runtime wiring

Layer 6 turns the Foundation Gateway into a deployable Supabase Edge Function runtime without placing Foundation inside an existing Shine app project.

## Runtime trust chain

The runtime verifies two independent principals:

1. **calling Shine app** — server-to-server app credential outside the JSON envelope;
2. **Shine user** — Supabase Auth JWT re-verified in code and mapped to canonical `shineId`.

Only after both pass does Foundation consult the app manifest, Vault metadata, grants and Shine Defence.

## App attestation

Raw app secrets are never stored. `foundation.app_credentials` stores SHA-256 hashes only. Revocation is separate and monotonic through `app_credential_revocations`.

App credentials are backend secrets. Browser/mobile clients must not embed them.

## Least-privilege database runtime

`postgres/runtime-v1.sql` creates:

- `foundation_runtime` — NOLOGIN privilege group;
- `foundation_gateway` — login role inheriting only runtime privileges;
- explicit RLS policies for runtime reads and audit inserts.

The Edge Function is designed to connect as `foundation_gateway`, not as the database owner.

## Auditing untrusted claims

Audit `app_id` and `shine_id` values are evidence of what a caller claimed. Layer 6 therefore removes their authority-table foreign keys so unknown callers can be denied and recorded rather than causing the audit itself to fail.

## Runtime package

`runtime/supabase-runtime-adapters-v1.mjs` implements app attestation, Supabase JWT verification with `getClaims()`, canonical identity binding, Core/Vault/grant lookups, Defence integration and idempotent audit writes.

`runtime/edge-function/index.ts` is the deployable `foundation-gateway` entrypoint.

## Hosting status

No dedicated Shine Foundation Supabase project currently exists. Layer 6 deliberately does not deploy into Dive, Money, RC or another app project, and it does not create a new paid project without explicit project/cost confirmation.
