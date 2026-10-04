# Layer 225 — release, deployment and rollback checkpoint

2026-10-04. Foundation Gateway sprint runtime release is deployed as Supabase version 93, ACTIVE.

Validation: all 259 Foundation JavaScript tests passed locally. Version 91 deployed the sprint bundle; its 31 files matched uploaded source and /health returned HTTP 200. The previous live version 90 bundle was saved in layer-225-rollback-gateway-v90.json, then restored as version 92. File equality and HTTP 200 verified restoration. The sprint bundle was restored as version 93, again exact file equality and HTTP 200. Rollback is redeployment of the saved source bundle, not reversal of database changes.

Release packaging preserves the version 90 live entrypoint and unrelated dependencies while updating Gateway, permission engine, integration consent, orchestration, ticket redemption and runtime adapters, plus their Wellness handoff dependency. Exact uploaded bundle is layer-225-release-gateway-v93.json. Local tests used repository source; control-plane file comparison and hosted health verify the deployed bundle, not full authenticated integration.

Remaining: authenticated cross-app access/invocation smoke tests; live Defence external connectivity, AI integration and L permitted memory retrieval. L gatewayAppId remains null in ownership catalogue. Onboarding/shared-client changes are repository source and require rollout by consuming apps. SQL recovery archive is preserved evidence, not an instruction to reapply historical migrations. No live grants or accounts were changed by this release.

Sprint 199–225 has 27 recorded source/release checkpoints. This is not a declaration that all cross-service integration is complete.
