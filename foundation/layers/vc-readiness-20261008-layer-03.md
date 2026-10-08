# VC readiness — layer 03: dedicated-project boundary

Date: 8 October 2026. Source baseline: de21958efd263f430a6877365ae18818d0e36865.
Sprint source count after merge: 3/40; 37 remain (92.5%). Historical 225-layer baseline is separate.

## What this enables for Veteran Care

Foundation now supplies a server-only deployment-descriptor check and bound identity-verifier factory. VC identity authority can be constructed only for explicit veteran_care mode with the dedicated issuer and coherent Auth, database and Storage project URLs. Legacy, offline, missing, malformed, noncanonical and mixed configurations return a bounded denial before any authority calls. The layer-01 issuer constant is shared to avoid drift. Matching settings do not authenticate a user, authorise a record, verify credentials or certify deployment. The existing server authority chain still verifies the caller and identity.

## Ownership and handover

Foundation owns these reusable producer contracts. VC Integrations & Security owns building the descriptor from actual server-owned client configuration, using the bound factory at the consuming boundary, credential provenance, registry wiring, dedicated-project cutover, live database/Storage verification and deployment. Never accept this descriptor from browser input. Construct a fresh verifier after any runtime configuration change; construction snapshots the boundary decision. Foundation's gateway may remain in its own project and is intentionally not a VC data endpoint. No VC configuration, credentials, data or hosted SQL changed.

Shine AI retains independent caller admission and model-routing ownership. This layer introduces no AI route, record handoff, grant or account linking. Reviewed VC producer-config.mjs blob 8922e85e836a1ffdabc16f4fd96578dac9c75687 and information-flow map blob 2bd68b579f39c68aa0de9de698562724231ac589 to preserve those boundaries. This receipt is a repository handover, not evidence of delivery or acknowledgement in another room.

## Verification

Command: node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
Result: 70 passed, 0 failed, including 10 new project-boundary tests. Synthetic identities and caller tokens only. Tested coherent configuration through existing authority, each mixed endpoint, wrong issuer, modes, lookalikes, unexpected fields, accessors, hostile descriptors, construction snapshot and legacy token denial.
Foundation CI runs the new test alongside identity, capabilities and runtime adapters. Merge requires Foundation and Defence workflow success. CI uses test infrastructure; no production deployment is included.

Checked Supabase changelog on 8 October 2026 and official JWT documentation: https://supabase.com/docs/guides/auth/jwts . Issuer parsing is routing rejection only; server verification remains mandatory. No dependency changes required.

## Open acceptance and next layer

Live consuming wiring, actual key/project association and private signed-in data acceptance remain with Integrations & Security. Source completion does not close those gates.
Next: layer 04, audience-bound access.
