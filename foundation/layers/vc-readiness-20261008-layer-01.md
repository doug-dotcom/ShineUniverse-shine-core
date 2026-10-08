# Foundation — VC Readiness layer 01/40: dedicated identity adapter

8 October 2026, Australia/Brisbane.

## Outcome
Added a server-only VC identity adapter that reuses Foundation's verifyAppCaller and verifyIdentity authorities. It requires the dedicated VC issuer, the configured registered VC app identity, a single JWT user proof, the configured approved provider and a verified provider-subject-to-Shine-ID binding. Caller-provided email, Shine ID and claimed app ID are not used for matching. No account linking, grants or clinical-record reads occur.

## Ownership handover
Foundation owns this reusable adapter and its tests. VC Integrations & Security owns provisioned app/provider identifiers and mounting the adapter in the VC backend after dedicated Auth acceptance. The fixture IDs shine.veteran-care and supabase:veteran-care in tests are proposals, not proof of current registration. No live identifiers were provisioned. Supply registry-confirmed IDs to createVeteranCareIdentityVerifier; do not infer a binding from email or silently adopt the old Foundation issuer.

Shine AI receives no new model configuration, prompts, retrieval or permissions in this layer. Adj remains the domain conversation owner. A verified identity creates no Vault grant.

The verifier's verified result is server-only and must not be returned as a public diagnostic. Its denied/unavailable states contain bounded reasons. Existing Foundation adapter verification remains the authority for provider token validity and active canonical account binding. The untrusted JWT issuer check only rejects wrong-provider routing.

## Evidence
Base source: 9760f6d1b0ab8207c46c817da86f667b501c8196.
Executed locally: node --test foundation/runtime/supabase-runtime-adapters-v1.test.mjs foundation/onboarding/veteran-care-identity-v1.test.mjs
50 passed, zero failed/skipped; includes 10 new synthetic VC tests and 40 existing runtime checks.
Existing CI test step now includes the new VC suite.
No actual tokens, grants, database writes, provider registration, deployment or signed-in cross-service journey occurred. Fixtures test adapter behaviour; they do not independently establish cryptographic authentication in production.

## Progress
01/40 source deliverable locally verified. Hosted/live acceptance remains pending; historical 225 counter is retained separately.
Enables VC: its backend can resolve a dedicated, verified VC account to Shine ID without email matching, while refusing unbound or wrong-provider accounts.
Next 02/40: reconcile and declare VC capabilities against registry-confirmed identifiers; do not treat registration as live invocation.
