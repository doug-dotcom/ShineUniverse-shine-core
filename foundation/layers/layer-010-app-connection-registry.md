# Foundation Layer 10 — App connection registry

**Status:** Complete  
**Scope:** Shine Core onboarding and appendage observability

Layer 10 makes app onboarding repeatable and observable instead of bespoke.

## App-specific identity trust

`foundation.app_identity_providers` explicitly links each registered Shine app to the identity providers it is allowed to use.

A provider being trusted by Foundation globally no longer means every connected app may use that provider.

The runtime verifies the caller's JWT issuer against:

1. the registered Foundation identity provider;
2. the requesting app's active provider link.

This prevents a valid token from an unrelated Shine identity project being accepted for the wrong appendage.

## Derived connection state

`foundation.app_connection_status` derives one app-level state from authoritative evidence:

- **registered** — Core manifest exists;
- **credentialed** — at least one active app credential exists;
- **identity-ready** — at least one active identity-provider link exists;
- **grant-ready** — at least one effective active grant exists;
- **live-observed** — at least one real allow decision has been audited;
- **disabled** — Core registry has disabled the app.

The view also records credential/provider/grant counts plus observed allow/deny counts and the latest decision.

No user-specific data is exposed through this view.

## Travel acceptance state

Shine Travel is the first entry.

Until a real signed-in Travel session reaches the pilot Gateway successfully, its truthful state is expected to be **grant-ready**.

After the first audited ALLOW, the same view automatically advances it to **live-observed** without a manual status update.

## Canonical status contract

`schemas/app-connection-status-v1.schema.json` defines the portable status shape for future admin/control-plane surfaces.

## Verification

PostgreSQL acceptance tests exercise the full progression from registered -> credentialed -> identity-ready -> grant-ready -> live-observed, and verify that the dedicated Foundation runtime can read only active app/provider links.


## Hosted acceptance

Layer 10 is live in the dedicated Shine Foundation project.

Current Shine Travel status:

- connection state: **grant-ready**;
- active app credentials: **1**;
- approved identity providers: **1** (`supabase:shine-l`);
- effective active grants: **2**;
- observed ALLOW decisions: **0**.

The hosted Gateway is version **5** and now enforces the app/provider link during user identity verification.

Supabase's hosted security advisor reports **0 security lints** after the Layer 10 deployment. The only Layer 10 performance lint discovered during rollout was the provider foreign-key index; it has been added in both production and source.
