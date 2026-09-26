# Foundation Layer 3 — Permission and grant engine

**Status:** Complete  
**Scope:** Core + ID + Vault + Defence gate

Layer 3 defines and tests the permission path that joins the Layer 2 Foundation objects.

## Canonical objects

- `permission-request-v1.schema.json` — one app asking one Shine identity for one scoped action and purpose against a resource.
- `access-grant-v1.schema.json` — explicit, resource-bounded consent granted to one app for one scope and one purpose.
- `access-decision-v1.schema.json` — explicit allow/deny result with a stable reason code.
- `grant-revocation-v1.schema.json` — revocation event that terminates a grant.
- `access-audit-event-v1.schema.json` — append-only decision evidence for later inspection.

## Deterministic reference evaluator

`integration-kit/permission-engine-v1.mjs` is the reference policy evaluator for Foundation v1.

An allow requires all of the following:

1. the request has the required identity/app/scope/purpose fields;
2. Shine ID has supplied a verified `shineId` matching the request;
3. Core has supplied the registered manifest for the requesting app;
4. that manifest declares the exact requested scope and purpose;
5. the Vault resource owner matches the requesting Shine identity;
6. the grant belongs to that identity and app;
7. requested scope matches the grant exactly;
8. requested purpose matches the grant exactly;
9. the resource selector matches the requested resource or category;
10. the grant is active and inside its time window;
11. the grant has not been revoked;
12. Shine Defence has not denied the request.

Everything else denies.

## Important boundaries

- A manifest declaration is **not** a grant.
- A valid grant cannot bypass ID verification or app registration.
- A grant cannot be reused for a different scope, purpose, app, identity or resource boundary.
- Shine Defence can veto an otherwise valid access path.
- An access denial disables only the requested connected capability. It does **not** tell the app to disable its unrelated standalone purpose.

## Tests

The reference suite covers exact allow plus fail-closed behaviour for:

- unverified identity;
- identity mismatch;
- unregistered app;
- undeclared scope;
- missing app grant;
- scope escalation;
- purpose substitution;
- resource substitution;
- revoked grant;
- expired grant;
- cross-identity resource access;
- Defence veto;
- preservation of the standalone boundary.

CI executes both the canonical object registry verifier and the permission-engine tests on every push and pull request.
