# Shine Foundation

Shine Foundation is the shared infrastructure layer that turns independent Shine applications into the connected Shine Universe.

Foundation is composed of three tightly coupled systems:

- **Shine Core** — app registry, shared service contracts, permission orchestration, event routing and app-to-app coordination.
- **Shine ID** — the canonical Shine identity and authenticated-session boundary.
- **Shine Vault** — protected user resources, explicit grants, consent state and auditable access.

Shine AI and Shine Defence remain independent Universe systems that Foundation integrates with. Foundation does not absorb them.

## Foundation principle

> Connected by choice, independent by design.

A Shine application must continue to provide its primary purpose without Foundation being available. Foundation may add identity, convenience, personalisation, cross-app coordination and shared intelligence, but it must not become a single point of failure for an application's core function.

The supported operating modes are:

1. **Standalone** — the app performs its primary function without Foundation.
2. **Connected** — the app uses Shine ID, Core and/or Vault services.
3. **Universe-enhanced** — the app can participate in authorised cross-app experiences coordinated through Core.

## Access model

Foundation uses a deny-by-default, least-privilege access flow:

1. Shine ID verifies the user identity and session.
2. Shine Core verifies the requesting app and requested scope.
3. Shine Vault evaluates whether the user has granted that app access to the specific resource/category.
4. Shine Defence may apply additional security and policy checks.
5. Foundation returns an explicit allow/deny decision.
6. The decision is auditable.

An app is never granted access to a user's entire Vault merely because the app belongs to the Shine Universe.

## Canonical contract

The machine-readable contract is:

- `contracts/foundation-v1.json`

Architectural decisions are recorded under:

- `adr/`
