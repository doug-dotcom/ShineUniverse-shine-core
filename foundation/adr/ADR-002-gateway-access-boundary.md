# ADR-002 — Foundation Gateway is the shared access boundary

**Status:** Accepted  
**Foundation layer:** 5

## Decision

Connected Shine applications do not receive direct access to Foundation persistence tables.

Shared access evaluation flows through the Foundation Gateway, which:

1. authenticates transport/session context outside the request body;
2. verifies the claimed Shine identity;
3. validates the requesting app against its Core manifest;
4. reads only the Vault metadata and effective grants required for the request;
5. applies Shine Defence;
6. evaluates the Foundation permission contract;
7. writes the allow/deny audit record;
8. returns a minimal result to the app.

An allow is not returned unless the corresponding audit record has been persisted.

## Consequences

- app clients do not need Foundation database credentials;
- the Foundation schema remains private;
- identity claims in request JSON do not authenticate themselves;
- internal grant IDs and Defence evidence are not exposed in the normal app response;
- Foundation outages affect connected capabilities, not unrelated standalone app functions;
- future Vault data delivery can sit behind the same boundary without exposing direct persistence access.
