# Atlas Feed

Atlas Feed is the Shine Universe's **permissioned signal plane**.

Its job is deliberately narrow: independent Shine apps may publish small, typed, provenance-bound signals that other authorised parts of the Universe can later discover or consume **without direct app-to-app database coupling**.

Atlas Feed does **not** own an app's canonical domain data. The source app remains authoritative. Feed events are references/signals with explicit freshness, audience and provenance.

## Governing rules

1. **Connected by choice, independent by design.**
2. **No implicit access.** Publication never creates a consumer grant.
3. **Source remains authoritative.** Atlas Feed does not become the system of record for specialist app data.
4. **Fail closed on ambiguity.** Unknown fields, malformed audience rules, invalid timing or unsafe payload keys are rejected.
5. **Small bounded events.** The feed is a signal plane, not a bulk-data transport.
6. **Provenance is mandatory.** Consumers must be able to see where a signal came from and how fresh it is.
7. **No credentials in payloads.** Secrets, tokens, cookies and authorization material are forbidden.

## Layers

- **Layer 1 — Feed event contract:** canonical envelope, deterministic validator and CI gate.
- **Layer 2 — Publisher admission:** Foundation-authenticated app/capability/owner/grant admission before persistence.

Persistence, querying/subscription, delivery, replay and consumer-read authorisation are intentionally deferred to later layers.
