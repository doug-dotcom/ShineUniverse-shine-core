# Layer 203 — Client request validation

Completed 4 October 2026. Shared Gateway v2 request builder validates scope and purpose against the existing schema patterns, optional resource categories and UUID identifiers, and requires a resource selector. Every supplied selector is checked even when the other is valid. Context must be a plain JSON object; circular references, non-finite numbers, undefined, functions, bigint, symbol keys, class instances and enumerable accessors are rejected before transport.

Verification: 22 onboarding tests passed locally. Regression test covers 17 malformed inputs in both JWT and opaque-header modes and asserts zero network calls. Existing valid credential modes and fail-closed response handling pass.

Source completion only. Connected apps must adopt this client for the checks to apply. No Gateway deployment or app rollout is claimed. Server authorisation remains required; client validation does not grant access or sanitise arbitrary secrets within context.
