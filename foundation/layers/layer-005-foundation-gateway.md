# Foundation Layer 5 — Foundation Gateway

**Status:** Complete  
**Scope:** trusted service boundary

Layer 5 creates one callable boundary between Shine applications and the shared Foundation systems.

## Boundary

Apps do not receive direct Foundation persistence access.

The request path is:

```
Shine app
  -> Foundation Gateway
  -> verified Shine ID
  -> registered Core app manifest
  -> Vault resource metadata
  -> effective grants
  -> Shine Defence
  -> permission engine
  -> append-only audit
  -> minimal allow/deny response
```

## Gateway contract

- `schemas/gateway-request-v1.schema.json`
- `schemas/gateway-response-v1.schema.json`
- `gateway/openapi-v1.json`

The v1 operation is `access.evaluate`.

Authentication is intentionally outside the JSON request envelope. The HTTP adapter authenticates the transport/session and passes trusted auth context into the Gateway; request-body identity claims never authenticate themselves.

## Trust-boundary ordering

The Gateway short-circuits in least-privilege order:

1. validate envelope;
2. verify Shine ID;
3. load and validate Core app manifest;
4. only then query Vault resource metadata and effective grants;
5. apply Shine Defence;
6. evaluate permission;
7. persist audit;
8. return a minimal response.

An identity mismatch therefore cannot trigger a Vault lookup, and an undeclared app scope cannot trigger Vault/grant reads.

## Fail-closed rules

- malformed envelope -> invalid;
- identity/core/vault/defence dependency failure -> unavailable;
- no matching permission -> denied;
- Defence veto -> denied;
- audit failure -> unavailable, even if the permission engine calculated allow.

An unaudited allow is never returned.

## Data minimisation

The external response contains the decision and reason code only. Internal grant IDs and Defence evidence references are written to the audit ledger but are not exposed to the calling app.

## Standalone boundary

`unavailable` means the connected Foundation capability is unavailable. The response does not instruct an app to disable its unrelated standalone purpose.

## Verification

Node tests cover allow, deny, verified identity binding, Defence veto, malformed envelopes, dependency failure, audit-write failure, response minimisation, standalone preservation and the HTTP boundary.
