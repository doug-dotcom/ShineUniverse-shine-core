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

1. request has the required identity/app/scope/purpose fields;
2. resource owner matches the requesting Shine identity;
3. grant belongs to that identity and app;
4. requested scope matches exactly;
5. requested purpose matches exactly;
6. resource selector matches the requested resource or category;
7. grant is active and inside its time window;
8. grant has not been revoked;
9. Shine Defence has not denied the request.

Everything else denies.

## Important boundary

An access denial disables only the requested connected capability. It does **not** tell the app to disable its unrelated standalone purpose.

## Tests

The reference test suite covers:

- exact allow;
- wrong app;
- scope escalation;
- purpose substitution;
- resource substitution;
- revoked grant;
- expired grant;
- cross-identity resource access;
- Defence veto;
- preservation of the standalone boundary.

CI executes the permission-engine tests on every push and pull request.
