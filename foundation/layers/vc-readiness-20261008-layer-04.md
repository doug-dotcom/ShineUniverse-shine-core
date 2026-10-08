# VC readiness — layer 04: audience-bound identity

8 October 2026, Brisbane. Source baseline: 2dcbce2b64749e947ca77448175c1076aa75fa33.
After successful merge: 4/40 source-verified layers; 36 remain (90%). Historical baseline remains separate.

## New enabling behaviour

Foundation supplies createVeteranCareAudienceIdentityVerifier: a server-only wrapper around the layer-03 project-bound identity verifier. It verifies the exact JWT through a supplied dedicated-project Supabase Auth getClaims authority before returning identity. Verified issuer, authenticated audience (string or a singleton array), authenticated role and subject must agree with the existing identity authority. Missing, foreign, wildcard, anonymous or multiple audiences fail closed. Error responses contain no identity, token or dependency detail.

The user proof is snapshotted before asynchronous verification. Claims from browser input, user metadata and decoded token payload are never used as positive audience authority. No ambient session lookup, token signing, account linking, grant or private record access is introduced.

Reconciliation: layer 01 already checks active app credentials and rejects foreign issuer routing. Those existing checks are reused, not counted again. The new outcome is mandatory verified user-token audience and subject coherence. Supabase's authenticated audience is general, not a unique VC app name; the dedicated issuer plus independently verified configured VC caller form the app boundary. A valid user audience alone does not authorise VC.

## Producer/consumer ownership

Producer contract: foundation/onboarding/veteran-care-audience-v1.mjs, version 1.
Foundation owns this additive guard and source tests on isolated branch foundation/vc-readiness-layer-04. Existing generic Gateway and permission engine are unchanged.

VC Integrations & Security owns choosing the registered VC app/provider identifiers, constructing the actual server-only dedicated Supabase client, supplying its supported auth.getClaims implementation, consuming this wrapper, enforcing records/grants and live deployment acceptance. The Auth object is a trusted dependency, never request input; decode-only implementations are forbidden. Returned audience context is local server data, not a portable credential. Live consuming branch and acceptance are not yet agreed or verified.

Shine AI retains its separate HMAC caller authentication, nonce admission, request-body/app binding and model/context/memory policies. This module is not a Shine AI admission credential. Reviewed Shine-Ai README at e38b95769442bca90315e2719e6b7f5288aeec74, blob e1b36341678c2d334a903b7f309484df31ae8368; no AI files changed.
Reviewed current VC room interface contract, blob f7c9593f09a6a8eb7c531c942bf27f63d6dd85d4. Private handoffs still require authenticated identity, exact record/version, explicit purpose and server checks. No shared VC files or credentials changed. Repository receipt is discoverable coordination, not acknowledgement by another room.

## Verification and limits

Command: node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
82 passed, 0 failed, including 12 new tests. Synthetic JWTs and mocked authority outputs test the guard contract; they are not signed real tokens or proof of SDK/hosted acceptance. Tests cover wrong app, wrong project with identical generic audience, invalid/multiple audience, forged caller claims, verified subject/role disagreement, failed/outage authority, wrong configuration, proof mutation and concurrent request isolation.
New test is included in Foundation CI. Foundation and Defence workflows must pass before merge. No production deployment, hosted Auth call, key rotation, grant mutation or database test is claimed by local evidence.

Sources checked: Supabase changelog on 8 October 2026; https://supabase.com/docs/guides/auth/jwt-fields and https://supabase.com/docs/reference/javascript/auth-getclaims . Supported getClaims verifies an explicit JWT; no decode-only fallback is used.

## Next and open gates

Layer 05: session authority checks. Audience success does not prove current session revocation, grant expiry or resource authorisation.
Consumer SDK wiring, real signed-token wrong-audience tests and exact live deployed acceptance remain open with Integrations & Security.
