# Foundation Layer 14 — Explicit identity claim

**Status:** Complete in source; hosted activation pending  
**Scope:** pseudonymous appendage identity linking

Layer 14 adds the explicit claim boundary required by Shine Ski after Layer 13 deliberately stopped at an unclaimed pseudonymous session.

## Three proofs, one claim

A claim succeeds only when the same server request proves:

1. the calling Shine app through its server-only app credential;
2. possession of the appendage's existing opaque session credential;
3. an existing canonical Shine identity through a separately authenticated canonical JWT.

The request JSON contains no Shine ID, provider ID, provider subject, raw session credential or JWT.

`POST /v1/identity/claim` accepts only the v1 claim envelope:

- claim ID;
- request ID;
- app ID;
- request time.

Provider identities and subjects are derived from the verified transport credentials on the server.

## Claim-provider allow-list

`foundation.app_claim_identity_providers` is separate from ordinary app identity-provider registration.

An app may claim through a canonical identity provider only when that provider is explicitly approved as a claim target for that app.

## Atomic persistence

`foundation.complete_identity_claim_v1` is the only runtime write path.

The private-schema function verifies:

- the app is active;
- the source opaque provider is approved for the app;
- the target canonical provider is separately approved for claims;
- the exact target provider subject is already bound to the supplied active canonical Shine ID;
- the claim context is fresh;
- the source subject is unbound or already bound to that same Shine ID.

An existing source binding can never be reassigned to another Shine identity.

Claim outcomes are recorded in the append-only `foundation.identity_claim_events` ledger. Replaying the same request is idempotent only when its identity tuple matches the original request.

## Identity is not consent

A successful identity claim creates only the canonical identity binding.

It does **not** create a Vault grant. Access consent remains a separate operation and a newly claimed Ski session therefore remains `identity-ready` until an explicit grant exists.

## Transport boundary

The reusable server-side claim client sends:

- `X-Shine-App-Token` — app proof;
- `X-Shine-User-Token` — pseudonymous source-session proof;
- `Authorization: Bearer ...` — canonical identity proof.

All three stay out of the JSON envelope.

## Observability

The connection registry adds:

- active claim-provider count;
- successful identity-claim count;
- last successful identity-claim time.

The existing connection-state ladder remains grant-based.

## Acceptance boundary

Deploying Layer 14 must not claim any real Ski browser automatically.

Hosted acceptance requires:

- zero unrequested Ski identity claims;
- zero automatically created Ski grants;
- security advisors clear;
- Foundation contract, runtime and persistence suites green;
- Edge Function updated with the claim endpoint.

The visible Ski claim UX is a later appendage layer. A user must explicitly initiate it and prove an existing canonical identity.
