# Foundation Layer 15 — Explicit Vault consent and grant issuance

**Status:** Source complete; hosted deployment pending  
**Scope:** Shine Vault consent boundary

Layer 15 completes the second half of the opt-in Foundation connection flow.

Layer 14 may prove that an app session belongs to an existing canonical Shine identity. Layer 15 is the separate, deliberate action that authorises an app to access one exact manifest-declared Vault scope.

## Rule

Identity is not consent.

A successful identity claim never implies Vault permission. A grant may be created only when all of these are true:

1. the calling Shine backend proves its server-only app credential;
2. Shine ID verifies an already-bound active canonical identity;
3. the app manifest declares the exact scope, purpose and resource category;
4. the selected Vault resource/category belongs to that Shine identity;
5. Shine Defence does not veto the request;
6. the request contains explicit `consent: true`;
7. the consent request is fresh and idempotent.

## Request

`POST /v1/grants/consent`

The JSON envelope contains the request ID, app ID, scope, purpose, resource category, optional exact resource ID, explicit consent flag and request time.

It does **not** contain a Shine ID, provider subject, app credential or user credential. Credentials remain in transport headers.

## Atomic persistence

`foundation.issue_access_grant_v1` is the only runtime write path for explicit user grants.

It re-checks the active identity, active app manifest, declared scope and Vault ownership inside Postgres before inserting an `access_grants` row with `consent_method = explicit-user`.

Repeated consent for an already-active matching grant returns `already-granted` and does not duplicate or broaden permission.

## Evidence

`foundation.grant_consent_events` is append-only and records the consent outcome without storing transport credentials.

`foundation.app_connection_status` additionally derives successful consent count and most recent consent time.

## Acceptance boundary

Layer 15 may be deployed and tested with synthetic/rollback records only.

No real Shine Ski identity claim or Vault grant is part of Layer 15 deployment acceptance.
