# Foundation Layer 33 — Deployment receipt publication attestation

**Status:** LIVE  
**Scope:** append-only database proof of who/what published or re-attested a deployment receipt

Layer 31 gave Foundation a canonical deployment-receipt identity.

Layer 32 made publication secretless through GitHub OIDC.

Layer 33 closes the evidence gap between those two layers.

## The gap

Gateway v85 already had an immutable deployment receipt created during Layer 31.

When Layer 32 later published that same receipt through GitHub OIDC, the Layer-31 RPC correctly returned:

`status = replayed`

That preserved deployment identity, but it also meant the database receipt row still showed its original submitter:

`foundation-layer31-verifier`

GitHub Actions could prove the OIDC publication occurred, but Foundation's own database could not.

Layer 33 separates:

- **deployment receipt identity** — what exact artefact/source/provider deployment exists;
- **publication attestation** — who/what submitted or re-attested that receipt, by which transport, and when.

The original receipt remains immutable.

## Publication ledger

New append-only ledger:

`foundation.service_deployment_receipt_publications`

Each accepted publication records:

- linked deployment receipt ID;
- service/environment;
- provider;
- runtime version;
- artefact SHA-256;
- source commit reference;
- provider evidence reference;
- publication outcome:
  - `accepted-new`;
  - `replayed-existing`;
- submitter;
- transport;
- GitHub run ID / attempt;
- GitHub event;
- repository;
- ref;
- workflow ref;
- workflow SHA;
- rollback flag;
- bounded metadata;
- publication timestamp.

The ledger is append-only and RLS protected.

Gateway cannot insert directly.

Foundation runtime can read it but cannot mutate it.

## OIDC publication identity

For GitHub OIDC publication events, Layer 33 treats the strongest assurance as:

- transport: `github-oidc`;
- submitted by: `github-actions-oidc`;
- repository: `doug-dotcom/ShineUniverse-shine-core`;
- ref: `refs/heads/main`.

The OIDC verifier itself remains Layer 32's responsibility.

Layer 33 records the verified identity claims passed by that ingest path.

## Idempotency

Publication identity is separate from receipt identity.

For GitHub OIDC:

`publication key = run ID + run attempt + receipt ID`

Therefore:

- retrying the same run/attempt is idempotent;
- a later GitHub run can re-attest the same immutable receipt;
- the receipt itself is not duplicated or rewritten.

The rollback suite proves:

- first accepted receipt creates `accepted-new`;
- exact same OIDC run/attempt replays the same publication event;
- a later OIDC run against the same receipt creates `replayed-existing`;
- two distinct runs produce two append-only publication events.

## Publication assurance reader

`foundation.get_deployment_receipt_publication_health_v1`

returns:

- **pass** — latest current-receipt publication is a fresh approved GitHub OIDC attestation;
- **degraded** — attestation is stale or latest publication is manual/non-OIDC;
- **unknown** — no receipt or no publication attestation exists.

The default freshness window is 24 hours.

This does not change Gateway readiness directly. It is deployment-automation assurance, not service health.

## Production proof

Before the Layer-33 OIDC replay, v85 publication assurance was:

- state: **unknown**;
- reason: `publication-attestation-missing`.

Layer 33 then changed only the non-semantic receipt-manifest revision, triggering the live Layer-32 OIDC publisher.

GitHub workflow:

**36395350182**

completed its core steps:

- deployment receipt manifest validation — **SUCCESS**;
- GitHub OIDC acquisition — **SUCCESS**;
- deployment receipt publication — **SUCCESS**.

Foundation then recorded:

- publication ID:
  `2649330b-6117-44a0-9614-aae8f6fb8478`;
- linked receipt:
  `bac106fe-57c4-4b38-b8bb-0acb5de11086`;
- runtime: **85**;
- publication outcome: `replayed-existing`;
- submitter: `github-actions-oidc`;
- transport: `github-oidc`;
- GitHub run: `36395350182`;
- run attempt: `1`;
- event: `push`;
- repository: `doug-dotcom/ShineUniverse-shine-core`;
- ref: `refs/heads/main`;
- workflow:
  `doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main`;
- workflow SHA:
  `81a3888fdc743100b07f7c710373e0cabaee2ed9`.

Publication assurance now evaluates:

**PASS**

with:

`publication-attested-by-github-oidc`

## Security properties

Layer 33 does not add another public writer.

The existing narrow Layer-31 receipt RPC remains the single accepted database write path.

The publication table:

- cannot be updated/deleted;
- cannot be directly written by Gateway;
- cannot be read by public roles;
- is visible read-only to Foundation runtime.

No provider token, OIDC token or Supabase credential is stored in the publication ledger.

## CI

Foundation CI now applies:

`foundation/postgres/deployment-receipt-publication-attestation-v1.sql`

and runs:

`foundation/postgres/deployment-receipt-publication-attestation-v1.test.sql`

The acceptance suite verifies:

- new receipt publication;
- replayed existing receipt publication;
- same-run idempotency;
- cross-run re-attestation;
- OIDC publication assurance;
- append-only history;
- Gateway/public permission boundaries.

## Machine-readable contract

`foundation/contracts/deployment-receipt-publication-attestation-v1.json`

## Closure

Foundation can now prove both:

> **“This is the immutable deployment identity.”**

and:

> **“This approved GitHub OIDC workflow re-attested that identity at this exact run/attempt.”**

without conflating or overwriting either fact.
