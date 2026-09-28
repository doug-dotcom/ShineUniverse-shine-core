# Atlas Feed — Layer 1: canonical feed-event contract

## Goal

Give the Shine Universe one strict event envelope before any Atlas Feed transport, persistence or subscription surface exists.

This prevents future publishers from inventing incompatible payload wrappers and prevents consumers from treating an event as implicitly authorised merely because it exists.

## Implemented

- Canonical contract: `atlas-feed/contracts/feed-event-v1.json`.
- Deterministic validator: `atlas-feed/runtime/validate-feed-event-v1.mjs`.
- Acceptance tests: `atlas-feed/runtime/validate-feed-event-v1.test.mjs`.
- Dedicated CI gate: `.github/workflows/atlas-feed.yml`.

## Contract boundary

Every v1 event carries:

- immutable event identity;
- namespaced topic;
- producing app, capability and release;
- subject kind/key;
- occurrence/publication/freshness timing;
- explicit audience mode and data class;
- provenance mode, observation time and evidence references;
- payload schema identity/version;
- bounded JSON payload.

## Fail-closed rules

Layer 1 rejects:

- unknown top-level or nested envelope fields;
- malformed UUID/topic/schema versions;
- publication before occurrence;
- invalid freshness/expiry;
- grant audience without an explicit grant id;
- grant id on non-grant events;
- non-first-party provenance without evidence;
- payloads over 64 KiB or deeper than eight levels;
- credential-bearing payload keys such as password, token, API key, authorization or cookies.

## Explicitly not claimed

Layer 1 does **not** claim:

- a hosted Atlas Feed service;
- persistence;
- publication endpoints;
- query/subscription endpoints;
- Realtime;
- Foundation grant verification at runtime;
- retries/replay/delivery guarantees;
- consumer materialisation.

Those are later layers.

## Acceptance

Layer 1 is complete when:

1. all Atlas Feed validator tests pass;
2. the Atlas Feed CI workflow is green on the pull request;
3. the change is merged to `main`.

## Next layer

Layer 2 should implement the **publisher admission boundary**: a Foundation-authenticated publish request that validates app identity/capability, the Layer-1 envelope and permission context before any event can be accepted for persistence.
