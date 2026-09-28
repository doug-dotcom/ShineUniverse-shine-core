# Foundation Layer 32 — OIDC deployment receipt publisher

**Status:** LIVE  
**Scope:** automatic, secretless publication of Layer-31 deployment receipts from an approved GitHub Actions workflow

Layer 31 created the secure Foundation-side deployment-receipt inbox.

Layer 32 closes the publication side without putting a Supabase service-role key or management token into GitHub.

## Architecture

The live path is:

`provider deployment evidence → checked-in receipt manifest → GitHub Actions OIDC → narrow Supabase ingest → Layer-31 receipt RPC → deployment truth → health/audit/readiness`

The publisher remains intentionally separate from the deployer.

It does not deploy Foundation Gateway and it does not guess provider state.

## GitHub workflow

`.github/workflows/publish-foundation-deployment-receipt.yml`

The workflow runs on:

- manual `workflow_dispatch`;
- pushes to the receipt manifest, workflow, OIDC ingest source or publisher contract.

Production receipt manifest:

`foundation/deployments/current-foundation-gateway-provider-receipt.json`

The manifest contains only non-secret deployment evidence:

- runtime version;
- provider artefact SHA-256;
- runtime state;
- exact source commit;
- provider evidence reference;
- provider observation timestamp;
- rollback flag.

## Exact-source validation

Before publication the workflow:

1. parses the receipt manifest;
2. validates runtime version and SHA formats;
3. requires an exact 40-character Git commit;
4. fetches full repository history;
5. verifies that exact source commit exists in Shine Core.

The initial live run exposed a useful CI boundary: the default one-commit checkout could not prove the older v85 source commit.

Layer 32 corrected this with:

`fetch-depth: 0`

and the following run completed successfully.

## GitHub OIDC authentication

The workflow requests an OIDC token with audience:

`shine-foundation-deployment-receipt`

No Supabase secret is stored in GitHub.

The token is presented to the dedicated Edge Function:

`foundation-deployment-receipt-ingest`

The ingest validates the GitHub OIDC signature against GitHub's published JWKS and pins:

- issuer: `https://token.actions.githubusercontent.com`;
- repository: `doug-dotcom/ShineUniverse-shine-core`;
- ref: `refs/heads/main`;
- exact workflow ref;
- audience;
- allowed GitHub event types.

An unauthenticated request is rejected with HTTP **401**.

## Dedicated management-plane Edge Function

Source:

`foundation/runtime/deployment-receipt-ingest/index.ts`

Hosted function:

- slug: `foundation-deployment-receipt-ingest`;
- version: **1**;
- verify JWT: **false**;
- authentication: GitHub OIDC;
- artefact SHA-256: `ba07c8dbf0f2334ae719f4e8323e223f8ab539705bcd4b4ca51dd7e40baaa596`.

It is separate from the user-facing `foundation-gateway`.

The Edge Function uses Supabase's server-side database environment and calls:

`foundation.submit_service_deployment_receipt_v1`

The GitHub workflow therefore never receives a database or Supabase service-role credential.

## Foundation registration

The management-plane ingest is registered as:

`foundation.deployment-receipt-ingest`

It is:

- an active Supabase Edge Function;
- owned by `shine-core`;
- non-core for Layer-30 readiness;
- exact-source bound to commit:
  `002ac12476d133afaa3ac82bf6691ffa3fae53bc`;
- deployed artefact:
  `ba07c8dbf0f2334ae719f4e8323e223f8ab539705bcd4b4ca51dd7e40baaa596`.

## Live production proof

The corrected publisher workflow run:

**36389217864**

completed:

- checkout — SUCCESS;
- deployment receipt manifest validation — SUCCESS;
- GitHub OIDC token acquisition — SUCCESS;
- deployment receipt publication — SUCCESS;
- overall job — **SUCCESS**.

The ingest returned:

- ingest status: `accepted`;
- receipt status: `replayed`;
- reconciliation state: `reconciled`.

`replayed` is the correct result because the v85 receipt had already been inserted during Layer 31.

The Edge logs independently recorded:

`POST /functions/v1/foundation-deployment-receipt-ingest → HTTP 200`

An unauthenticated production probe returned:

`HTTP 401`

## Production receipt

The successful OIDC run published the already verified Gateway v85 evidence:

- runtime version: **85**;
- artefact SHA-256:
  `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`;
- source commit:
  `b7c5331f93eff28a781f0794c89ccf50e90a4045`;
- reconciliation: **RECONCILED**.

Layer-30 readiness remains independent of receipt publication and continues to enforce fresh health/audit/Defence evidence.

## Security boundary

Layer 32 stores no provider or database credential in GitHub.

It specifically avoids:

- GitHub repository Supabase secrets;
- Supabase personal access tokens;
- committed service-role keys;
- database-stored management credentials.

Trust is based on short-lived GitHub OIDC identity plus the Layer-31 database validation rules.

The workflow cannot directly write Foundation tables.

The OIDC ingest can submit only through the narrow Layer-31 receipt contract.

## CI

Foundation CI now covers:

- deployment receipt payload validation;
- OIDC ingest Deno type checking;
- Layer-31 reconciliation schema/tests;
- registration of the management-plane ingest runtime.

The earlier secret-based workflow design is superseded and is not part of the live architecture.

## Machine-readable contract

`foundation/contracts/deployment-receipt-publisher-v1.json`

## Closure

Layer 32 changes deployment receipt publication from:

> “a human or secret-bearing workflow must tell Foundation what was deployed”

to:

> **“an approved GitHub workflow proves its identity with OIDC and can publish exact non-secret deployment evidence through a narrow, auditable management-plane boundary.”**

The Layer-31 inbox and Layer-30 readiness gate remain authoritative after publication.
