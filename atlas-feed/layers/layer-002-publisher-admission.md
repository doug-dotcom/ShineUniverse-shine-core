# Atlas Feed — Layer 2: publisher admission boundary

## Goal

Prevent an Atlas Feed event from reaching any future persistence layer until Foundation has proved **who is publishing, under which live capability, and under which owner/grant context**.

Layer 2 remains intentionally pre-persistence.

## Implemented

- Contract: `atlas-feed/contracts/publisher-admission-v1.json`.
- Admission service: `atlas-feed/gateway/publisher-admission-v1.mjs`.
- HTTP route: `POST /v1/atlas-feed/publish/admit`.
- Foundation app-token authentication for general signals.
- Foundation app + user identity verification for personal/sensitive owner publication.
- Existing `foundation.app_capabilities` registry used as the publisher capability authority.
- Existing `foundation.effective_access_grants` used for grant-audience validation.
- Defence-backed `context-operations` front-door policy registration.
- Dedicated Node and Postgres acceptance tests.

## Admission rules

A request is admitted only when:

1. the request envelope is current and structurally valid;
2. the nested event passes the Layer-1 validator;
3. the supplied app credential verifies to the event's source app;
4. the source capability belongs to that app and is `live`;
5. personal/sensitive events resolve to the explicitly named Shine owner through a verified user session;
6. personal/sensitive events do not use the broad `internal` audience;
7. grant-audience events reference an active Foundation grant with exact declared scope, purpose and resource context;
8. private grant-audience events match the verified owner;
9. the Gateway's existing Defence-backed context-operation admission policy allows the operation.

## Important boundary

An **admitted** response means only:

> Foundation has accepted that this publisher is eligible to submit this exact event to a later Atlas persistence layer.

It does **not** mean:

- the event was stored;
- the event was broadcast;
- a subscriber may read it;
- a consumer grant was created;
- the event is canonical app data.

## Next layer

Layer 3 should add the **append-only event store** and idempotent persistence receipt, while preserving the Layer-2 decision as a mandatory prerequisite.
