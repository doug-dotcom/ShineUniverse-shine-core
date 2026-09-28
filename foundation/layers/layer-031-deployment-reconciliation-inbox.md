# Foundation Layer 31 — Management-plane deployment reconciliation inbox

**Status:** LIVE  
**Scope:** verified deployment-receipt ingestion + automatic deployment-truth reconciliation without storing provider management credentials

Layer 30 made Foundation able to evaluate readiness from canonical evidence.

It also exposed a deliberate boundary: Foundation could not know that Supabase had deployed a new Gateway version until an external actor reconciled the management-plane deployment into Foundation deployment truth.

Layer 31 removes the **manual SQL reconciliation** step while keeping provider credentials outside the database.

## Architecture

Layer 31 introduces a narrow management-plane receipt boundary:

`trusted provider observer → verified non-secret receipt → Foundation reconciliation inbox → deployment truth → fresh health/audit → readiness`

The observer may run in CI, Work, a trusted deployment workflow, or another authorised management-plane service.

Foundation itself does not store a Supabase personal access token or provider management credential.

## Deployment receipt

New append-only ledger:

`foundation.service_deployment_receipts`

A receipt contains only:

- service/environment;
- provider;
- runtime reference;
- runtime version;
- artefact SHA-256;
- runtime state;
- exact Git commit source reference;
- provider evidence reference;
- provider observation time;
- submitter identity;
- bounded metadata.

It explicitly does **not** contain:

- Supabase management token;
- service-role secret;
- request payloads;
- user data.

## Narrow writer

`foundation.submit_service_deployment_receipt_v1`

may be executed only by `service_role`.

It cannot be executed by:

- `foundation_gateway`;
- `foundation_runtime`;
- `anon`;
- `authenticated`.

The Gateway also has no direct INSERT privilege on the receipt table.

## Validation

The receipt writer requires:

- active registered service;
- known provider;
- valid environment;
- non-empty runtime version;
- 64-character artefact SHA-256;
- exact Git commit source reference;
- bounded provider evidence reference;
- recent provider observation time;
- bounded JSON metadata.

For the production Foundation Gateway, the Supabase runtime reference is pinned to:

`supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway`

A different runtime reference is rejected.

Numeric runtime regressions are rejected unless the receipt explicitly carries rollback metadata.

Identical receipts are idempotent.

## Automatic reconciliation

An accepted receipt appends:

1. the management-plane receipt;
2. a deployment expectation;
3. a deployment observation.

The deployment observation begins with:

`health_state = unknown`

This is intentional.

A newly observed deployment therefore cannot inherit the previous runtime's health/readiness.

Layer 30 continues to require the new runtime to earn its own:

- deployment-bounded health;
- complete privileged policy/outcome audit trace;
- readiness evaluation.

## Reconciliation status

`foundation.get_deployment_reconciliation_status_v1`

returns:

- **unknown** — no verified receipt;
- **drift** — receipt exists but deployment truth is not aligned;
- **awaiting-proof** — deployment reconciled, but current-runtime health/readiness proof is still pending;
- **reconciled** — deployment truth is aligned and the receipt runtime has current health/readiness evidence.

The reader uses canonical health evidence's `metrics.runtimeVersion`, not the deployment observation's informational health field.

## Production proof — Gateway v85

Layer 31 was exercised against the already verified v85 Gateway without changing the runtime.

Receipt:

- provider: `supabase-edge`;
- runtime: **85**;
- artefact: `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`;
- source: `github://doug-dotcom/ShineUniverse-shine-core/commit/b7c5331f93eff28a781f0794c89ccf50e90a4045`;
- provider state: `ACTIVE`;
- exact-source verified: true.

The receipt was accepted and stored append-only.

Deployment truth remained:

**ALIGNED**

Because v85 had already earned matching current-runtime health and audit evidence, the final reconciliation status is:

**RECONCILED**

Layer-30 readiness remains:

**RESTRICTED / guarded**

because Shine Defence is currently fail-closed. The management-plane receipt does not bypass or weaken Defence/readiness semantics.

## New-deployment behaviour

For a genuinely new Gateway version, the expected transition is:

1. observer detects provider deployment;
2. observer verifies source/artifact identity;
3. observer submits receipt;
4. Foundation immediately reconciles expectation + observation;
5. health/readiness become deployment-specific and cannot inherit the previous runtime;
6. status reports `awaiting-proof`;
7. automatic health probes and privileged traffic produce current-runtime evidence;
8. Layer 30 evaluates the new runtime;
9. reconciliation becomes `reconciled`.

## Observer boundary

Layer 31 does **not** put the Supabase Management API token into Postgres.

The management-plane fetch remains outside Foundation's database trust boundary.

This is deliberate:

- credentials remain in an authorised execution environment;
- Foundation receives only the evidence it needs;
- the receipt ledger is non-secret and auditable;
- provider access can be rotated independently of Foundation data.

## Acceptance coverage

The rollback suite proves:

- valid receipt reconciles deployment truth;
- new runtime without health reports `awaiting-proof`;
- identical receipt is idempotent;
- unmarked numeric rollback is rejected;
- incorrect Gateway runtime reference is rejected;
- receipt history is append-only;
- Gateway/runtime roles cannot submit receipts;
- service role can submit;
- Foundation runtime can read reconciliation status;
- public roles cannot read reconciliation status.

## Machine-readable contract

`foundation/contracts/deployment-reconciliation-inbox-v1.json`

## Closure

Layer 31 turns deployment reconciliation from an ad-hoc database operation into a narrow, auditable management-plane ingestion contract.

Foundation still does not pretend it can see provider state without an observer.

Instead, it now has a safe standard way for a trusted observer to say:

> **“This exact artefact from this exact source commit is now what the provider says is deployed.”**

and automatically starts the new runtime's health/audit/readiness proof cycle.
