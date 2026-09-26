# Foundation Layer 12 — Appendage onboarding kit

**Status:** Complete  
**Scope:** repeatable app onboarding

Travel and Dive proved Foundation can connect apps with different session models. Layer 12 turns those lessons into a reusable kit so the next appendage does not need a bespoke Foundation architecture.

## Connection spec

`schemas/appendage-connection-spec-v1.schema.json` defines the portable, secret-free description of a Shine appendage connection.

A spec contains only architecture facts:

- app identity and primary purpose;
- source repository, branch and backend entrypoint;
- identity-provider type and public verification metadata;
- runtime platform and required environment-variable **names**;
- pilot scope, purpose and resource category;
- explicit standalone-fallback safety declarations.

A connection spec must not contain:

- raw app credentials;
- user credentials;
- canonical Shine IDs;
- provider subjects;
- credential IDs;
- resource IDs;
- passwords, API secrets or service-role keys.

## Compiler

`onboarding/connection-spec-v1.mjs` validates a spec and compiles it into a deterministic onboarding plan containing:

- Core app manifest;
- identity-provider registration shape;
- app/provider link;
- runtime wiring contract;
- pilot permission contract;
- the live items that still require secure provisioning.

Compilation never generates or stores secrets and never chooses a user's canonical Shine ID.

## Reusable backend client

`onboarding/foundation-app-client-v1.mjs` is the common server-side Gateway client for Shine appendages.

The client:

- emits Gateway request v2 only;
- never accepts or sends caller-supplied `shineId`;
- keeps app and user credentials in headers;
- supports both proven identity modes:
  - bearer JWT;
  - opaque user token;
- byte-bounds Foundation responses;
- fails to an optional/unavailable result rather than instructing the app to disable itself.

## Golden examples

The two existing appendages are captured as secret-free examples:

- `onboarding/examples/travel-v1.json`;
- `onboarding/examples/dive-v1.json`.

These are architecture fixtures, not credential stores.

## CI

Layer 12 CI validates both example specs and tests the compiler/client boundary, including:

- standalone fallback;
- secret/personal-ID rejection;
- identity/runtime mode matching;
- app-namespaced pilot purposes;
- no Shine ID in Gateway v2 bodies;
- no credentials in Gateway JSON;
- JWT and opaque-header transport;
- network and oversized-response fail-closed behaviour.

## Outcome

The expected workflow for appendage #3 is now:

1. write one connection spec;
2. validate/compile it;
3. provision live credential + provider key + canonical user binding + grant;
4. use the shared backend client;
5. let `app_connection_status` derive the real state.

The architecture work should therefore decrease with each new Shine appendage.


## Acceptance

Layer 12 is verified on commit `9d8bf75430a3d9b1e67eabd8001ef873359ebda5`.

- object registry: **PASS**
- Foundation contract/runtime suite: **PASS**
- Travel onboarding example: **PASS**
- Dive onboarding example: **PASS**
- connection-spec compiler tests: **PASS**
- shared backend client tests: **PASS**
- Deno Edge Function type-check: **PASS**
- clean PostgreSQL Foundation rebuild and acceptance suite: **PASS**

Layer 12 makes no live credential, user-binding or grant changes. It adds the reusable tooling required to make the next appendage connection materially smaller and safer.
