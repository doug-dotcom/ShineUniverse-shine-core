# Foundation Layer 14 — Explicit identity claim and merge

**Status:** Complete in source; hosted activation pending  
**Scope:** Shine ID claim boundary

Layer 14 introduces an explicit, two-proof identity claim flow for apps that begin with an unbound pseudonymous session such as Shine Ski.

## Rule

A pseudonymous app session may not become a canonical Shine identity from one proof.

A successful claim requires all three transport credentials:

1. **calling app proof** — server-only Shine app credential;
2. **source session proof** — the app's existing pseudonymous session credential;
3. **target identity proof** — a separately authenticated credential for an already-bound canonical Shine identity.

No caller supplies a Shine ID, provider subject or Vault grant in the request JSON.

## Request

`POST /v1/identity/claim`

The JSON envelope contains only:

- request ID;
- app ID;
- source provider ID;
- target provider ID;
- request time.

Credentials remain in transport headers.

## App-specific claim providers

`foundation.app_claim_identity_providers` is separate from normal app identity providers.

An identity provider approved for ordinary access is not automatically approved as a claim target, and a claim target is not automatically an ordinary login provider for that app.

## Atomic database claim

`foundation.complete_identity_claim_v1` is the only runtime write path for the claim.

It validates:

- the app is active;
- the source provider is approved for the app;
- the target provider is explicitly approved as a claim provider;
- the target provider is already bound to the supplied active canonical Shine ID;
- the source provider subject is currently unbound, or already bound to the same Shine ID.

Outcomes:

- `linked`;
- `already-linked`;
- `denied / source-already-bound`;
- other policy denials.

The function cannot reassign an existing source binding to a different Shine ID.

## No automatic Vault grant

Identity claim and Vault consent are deliberately separate operations.

A successful claim inserts the new identity binding and an append-only identity-claim event. It does **not** create an access grant.

## Observability

`foundation.app_connection_status` now also derives:

- active claim-provider count;
- successful identity-claim count;
- last successful claim time.

The app connection state itself remains grant-based. A newly claimed Ski session therefore remains `identity-ready` until a separate explicit grant is issued.

## Client

`onboarding/identity-claim-client-v1.mjs` is the reusable server-side claim client.

It sends:

- app credential in `X-Shine-App-Token`;
- source pseudonymous credential in `X-Shine-User-Token`;
- target identity JWT in `Authorization: Bearer ...`.

None of those credentials are placed in the JSON body.

## Acceptance boundary

Layer 14 source and CI may be deployed without linking any real Ski session.

The live Ski app should remain unclaimed until a user explicitly starts the claim flow and proves an existing canonical identity.
