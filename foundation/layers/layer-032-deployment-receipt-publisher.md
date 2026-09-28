# Foundation Layer 32 — Deployment receipt publisher automation

**Status:** BUILT + CI-GATED; production secret presence not observable through the current GitHub connector  
**Scope:** trusted workflow publication of Layer-31 deployment receipts

Layer 31 created the secure Foundation-side inbox for verified management-plane deployment receipts.

Layer 32 packages the observer-to-inbox handoff as a reusable GitHub Actions workflow so an authorised deployment mechanism no longer needs a human to construct or submit the receipt manually.

## Workflow

`.github/workflows/publish-foundation-deployment-receipt.yml`

The workflow is intentionally **not a deployer**.

It runs after an authorised deployer/observer has obtained provider evidence.

Required inputs:

- runtime version;
- provider artefact SHA-256;
- exact 40-character source commit;
- provider evidence reference;
- provider observation time;
- runtime state;
- explicit rollback flag.

## Exact-source validation

Before publication the workflow verifies that the supplied source commit exists in the checked-out Shine Core repository and resolves exactly to the supplied 40-character SHA.

Branch names such as `main` are not accepted as source identity.

## Payload builder

`foundation/integration-kit/build-deployment-receipt-payload-v1.mjs`

builds the RPC payload and rejects:

- malformed artefact SHA;
- non-exact source commit;
- missing provider evidence;
- invalid runtime state;
- invalid provider observation timestamp.

The payload includes workflow provenance such as run ID and repository, but never includes secrets.

## Secret boundary

The publisher expects two GitHub runtime secrets:

- `FOUNDATION_SUPABASE_URL`;
- `FOUNDATION_SUPABASE_SERVICE_ROLE_KEY`.

They are referenced only from the `foundation-production` GitHub environment.

The workflow sends the service-role credential directly to Supabase over HTTPS to invoke the Layer-31 RPC.

The credential is not:

- committed to Git;
- written into the receipt payload;
- stored in Foundation tables;
- printed in the workflow's receipt summary.

The current GitHub connector intentionally does not expose repository/environment secrets, so this build cannot verify whether those two secrets are already configured.

Layer 32 therefore does **not** claim a successful live workflow dispatch until secret presence is proven by an actual run.

## Workflow behaviour

The publisher:

1. validates the exact source commit;
2. builds the bounded non-secret receipt;
3. calls `submit_service_deployment_receipt_v1`;
4. requires receipt status `reconciled` or `replayed`;
5. reads `get_deployment_reconciliation_status_v1`;
6. fails if Foundation reports `unknown` or `drift`.

`awaiting-proof` is valid for a genuinely new deployment because Layer 30 must still require fresh runtime health/audit/readiness evidence.

## Separation of authority

The workflow deliberately does not:

- deploy the Edge Function;
- infer a runtime version;
- calculate or guess the provider artefact identity;
- poll Supabase using a management PAT;
- change readiness directly.

Deployment authority, provider observation and Foundation reconciliation remain separate concerns.

## Production path already proven

Layer 31 proved the same RPC path against Gateway v85:

- version: **85**;
- artefact: `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`;
- source: `b7c5331f93eff28a781f0794c89ccf50e90a4045`;
- reconciliation: **RECONCILED**.

Layer 32 automates construction and submission of that already-proven receipt contract.

## CI

The Foundation contracts job now runs:

`node --test foundation/integration-kit/build-deployment-receipt-payload-v1.test.mjs`

Coverage verifies:

- canonical payload generation;
- no secret fields;
- explicit rollback metadata;
- malformed artefact rejection;
- non-exact source rejection;
- missing provider evidence rejection.

## Machine-readable contract

`foundation/contracts/deployment-receipt-publisher-v1.json`

## Operational boundary

Layer 32 closes the **code and workflow automation** side of deployment receipt publication.

One operational prerequisite remains externally observable only through a real workflow run:

> the `foundation-production` GitHub environment must contain `FOUNDATION_SUPABASE_URL` and `FOUNDATION_SUPABASE_SERVICE_ROLE_KEY`.

Until an actual dispatch succeeds, Foundation should describe the publisher as **built and CI-gated**, not as proven live automation.
