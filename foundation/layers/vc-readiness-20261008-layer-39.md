# VC readiness layer 39 — exact release/rollback

Baseline: 59b2acd9fad43cd89115da6725ff022c14f1e553 (layer 38 merged).
After merge: 39/40 complete; 1 remaining (2.5%).

## Behaviour

createVeteranCareReleaseRollbackVerifier is a protected read-only observer for an approved release or rollback target. It accepts only {action:'release'|'rollback',authContext:{serviceToken}}. Expected commit/artifact/deployment scope comes from a current server-owned plan, never caller overrides. A current release operator is verified before any plan/provider/runtime observation and again before returning success.

The approved plan fixes app, environment, plan ID/revision, exact 40-hex source commit, 64-hex artifact digest, current compatible schema revision, authority epoch, minimum revocation revision and expiry. Current authority must independently match schema/epoch and meet the revocation floor. An independent compatibility adapter must attest this candidate source/artifact against the presently active schema for the requested action. An older binary must not restore an older schema/authority baseline.

The observer takes two independently correlated provider/runtime observation pairs with fresh random request IDs. Both sources must report the approved exact commit/artifact and active matching deployment ID/app/environment, valid recent non-future timestamps and explicit live or synthetic modes. Runtime schema, authority epoch and revocation revision must match current authority exactly. Drift across pairs, changed plan/authority, withdrawn compatibility/operator, stale evidence at the five-minute boundary, clocks/expiry errors and outages withhold success. Release deadline is bounded by current plan, authority, operator and final observations.

Success returns exact-release-observed with immutable release/authority/evidence metadata and observationsMatched true. Both actions retain deploymentMutationPerformed false, rollbackPerformed false and permissionsRestored false. This verifies an already observed target; it does not deploy or execute rollback. Live evidence mode must be established by authenticated real adapters. Source test fixtures report synthetic and do not prove a deployed release.

## Pinned source evidence

Two separate complete JSON source bundles are fetched from exact GitHub commits, retaining each file's original contents and SHA-256. The release bundle pins the layer-38 merged source 59b2acd9fad43cd89115da6725ff022c14f1e553 and includes the isolated restore runner/fixture plus restored-revocation runner/SQL. Its actual file SHA-256 is b0d02b1c7451352f69b04521099f4d5b17f463b438765a91049bfb37fd831c4c.

The rollback source bundle pins layer-37 merged source 60ecc7fe6679a8f7caa7ac22622cb3234228792e, containing its original isolated runner/fixture. Its actual file SHA-256 is 2023de1aaf4d7588cd823150f5a35dce8fcbef8cc76fc1497c9100c3f1e4b9ab. These are historical restore-proof source bundles, not deployable VC application artifacts or production rollback approvals. The sidecar source-evidence JSON explicitly sets production release/rollback verification and deployment performed to false. They must not be substituted for actual runtime binary/package digests in a production observation plan.

## Ownership and interfaces

Foundation owns exact observation composition and protected source evidence. Existing generic promoted-release/Defence release and rollback contracts remain intact; this VC observer is additional consumer-specific coverage, not a replacement or fresh credit for those systems. VC Integrations/Security owns operator authentication, real provider/runtime adapters, artifact custody/provenance, current authority and schema compatibility. Actual deployments/rollback execution remain owned by the authorised release workflow.

verifyReleaseOperator receives {authContext,foundationAppId:'shine.veteran-care',purpose:'veteran-care.release-observation'} and returns exactly {verified,foundationAppId,purpose,servicePrincipalId,revision,validUntil}. Service identity is a bounded vc-release-* server principal. getCurrentReleasePlan({foundationAppId,action}) returns exactly {foundationAppId,action,environment,planId,revision,status,sourceCommitSha,artifactSha256,schemaRevision,authorityEpoch,minimumRevocationRevision,validUntil}; status must be approved and environment staging or production.

getCurrentReleaseAuthority({foundationAppId,environment}) returns exactly {foundationAppId,environment,schemaRevision,authorityEpoch,revocationRevision,validUntil}. getReleaseSchemaCompatibility receives exactly {foundationAppId,environment,action,sourceCommitSha,artifactSha256,schemaRevision} and returns those fields plus compatible true only after independent candidate/schema compatibility verification. An echoed caller assertion is insufficient.

Provider/runtime observations receive exactly {foundationAppId,environment,requestId}. Each returns those fields plus {deploymentId,sourceCommitSha,artifactSha256,status,observedAt,evidenceMode}; runtime additionally returns {schemaRevision,authorityEpoch,revocationRevision}. Provider identity/digest must come from authoritative deployment inventory; runtime digest/commit from immutable build metadata checked against custody rather than a fabricated echo. Correlation and authenticity must be independently verified. Runtime observation must not be the provider's same cached record disguised as a second source. Only active observations less than five minutes old are accepted.

This gate trusts protected adapter capabilities; it cannot cryptographically authenticate arbitrary callback implementations. Point-in-time rechecks do not hold a distributed deployment lock. Exact identity agreement alone does not certify user flows, data safety or all release policies. Actual provider/runtime observations, real production artifacts, approved rollback target, deployed schema compatibility and current authority proof remain open. No hosting, Supabase deployment, database downgrade, credential restore or live rollback occurs.

## Evidence

13 local tests cover exact independent observations; rollback retaining current authority; identity/artifact/scope/nonce mismatches; inactive/stale/future/malformed/accessor evidence; incompatible rollback/authority downgrade; plan/authority/compatibility changes; deployment drift; operator gates; caller overrides; expiry/clock/freshness boundary; redacted outages; input capture; and pinned source bundle byte/file-digest parity with no live claim.

439/439 local onboarding/runtime tests passed; diff check passed. Registered in Foundation CI; all three checks must pass before merge, including the actual synthetic PostgreSQL restore/continuity drills. No production deployment/rollback evidence is claimed.

Next: layer 40, readiness handover.
