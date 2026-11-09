# Foundation reconciliation — 8 November 2026

## Applied and verified

- Supabase `foundation-gateway` remains ACTIVE version 93; no runtime redeployment.
- Provider artifact SHA-256: `9ad0189be337a91ca90b3c278d0a274a445cdbacd976f9935753d4b151e3e565`.
- All 31 deployed files exactly match `foundation/releases/layer-225-release-gateway-v93.json` at commit `b135f80d07bc1bafd8266c1bd1e510fa84a4b22d`. This is a packaged release: its contents, rather than arbitrary working-tree files, identify the deployed source.
- Deployment receipt `b81df68f-84b5-49da-b28a-d0bc4037ebe2` reconciles expected/observed deployment to version 93.
- Updated current provider receipt manifest in commit `1ba744f1e373540fcba60cebb77ebdf20912adeb`.
- Existing publication workflow run `42456720668` published the receipt through GitHub OIDC; publication `405ce01e-314e-4da8-bc1c-faa68341cc1f`. Database publication assurance reports pass/github-oidc.
- Immutable release binding `8ca3982d-d571-493a-8a8b-398c87d73daf`, release `foundation:layer-225:b135f80d`, now matches the deployed artifact and attested publication. Binding health passes.
- Enabled default-deny RLS on four postgres-owned internal dispatcher tables. No client/runtime grants existed. Retest: zero RLS-disabled tables in Foundation/Universe posture and zero anon/authenticated reads on the four tables. SQL preserved in `foundation/postgres/dispatcher-internal-rls-repair-20261108.sql`.
- Defence overall state improved from fail to warning. Recorded fresh posture `6a0bdd2a-a141-4a90-9b99-424c62c673cf`.
- Fresh hosted health checks returned HTTP 200 with contract_ok=true. After collecting the required sample, version 93 health reports healthy.
- Retrieved 20 relevant test files from the release-evidence commit and ran them against the exact deployed JavaScript module bytes: 233 tests passed, zero failed. This is module/adapter coverage, not full authenticated integration or Deno entrypoint execution.
- Current-runtime audit chains: two complete traces, zero broken traces at verification. One historical incomplete trace remains from 31 October, labelled v90. No outcome was fabricated.
- Recorded readiness observation `53ad0398-c964-4011-9b8a-53375c452c11`: degraded, with dependency-degraded and operation-audit-degraded.
- Supabase health advisors returned no notices; security advisors retain existing unrelated public-schema informational findings and one Veteran Care function warning.

## Open gates and limits

1. Version-93 artifact-bound external auth and dependency evidence remains missing at the last posture check. The existing re-attestation workflow runs every five minutes. Its current inspector scans repository runtime source; this packaged release requires care because not every working-tree file necessarily equals the archived bundle. Do not manufacture passing attestations from the earlier v90 results.
2. Full authenticated cross-app access, capability invocation, AI and Project L integration are unverified. The earlier release checkpoint explicitly recorded these limitations.
3. User/clinician product acceptance remains unverified.
4. The historical v90 audit trace has no outcome; its result cannot be reconstructed from a later successful request.
5. Universe release-ledger identity and registry pointer were subsequently reconciled to `foundation:layer-225:b135f80d`; projection retest reports aligned. This opens a release identity only; no integration or acceptance events were asserted.
6. The saved HTML evidence review is a static snapshot from earlier today; this repair did not rewrite it or establish a live dashboard refresh.
7. Provider reconciliation was verified during this session. An automatic management-plane collector that detects future out-of-band deployments has not been added.

The deployed release remains Layer 225. This session does not claim 25 newly completed build layers or increment the layer counter merely for investigation steps.

## Latest health update

At approximately 17:01 Brisbane, the automatic collector reported degraded health due to p95 latency 5370.108 ms across four probes (zero 4xx/5xx and zero runtime errors). Earlier healthy results remain historical observations; current health must retain this warning. No threshold was relaxed and no probe result was removed.

## Continuation — 8 November 2026, 17:09 Brisbane

- Added verified bundle resolver and artifact-to-source mapping with canonical 31-file SHA-256 `496b05459eebe272c12e4cc26060f33d509dd2572aa4f80937a10d78d358a210`. Rejects source mismatch, altered bundle digest, invalid paths, duplicates and missing entrypoint.
- Defence inspector v1.1.0 inspects deployed bundle module imports and gateway entrypoint; supplemental navigator/database posture source checks remain distinct. Existing dependency assurance is pinned-import/source inspection, not an npm vulnerability database scan or full penetration test.
- Nine provenance regression tests passed in GitHub Actions run `42457408380`. The job completed SUCCESS, checked out the exact source commit and submitted its artifact attestation through GitHub OIDC.
- Attestation policy commit `00b1d5ed45e772092db7daf82b4f9a46ea8269d4`; report SHA-256 `af017c09dff6ab6daa58fcb9eb2f12453e597e1a71f66b95595d26ac825c4bdb` exactly matched the local bundle inspection. One deployed pinned npm import observed.
- Defence posture now passes all seven controls. Fresh posture observation `761a49a9-4663-42cb-b354-f478c1cfeae7` replaces the earlier warning as current evidence.
- Re-attestation workflow now also triggers on deployment manifest/mapping changes and runs bundle regression checks before acquiring its OIDC token. This closes the missing-v93-evidence issue; it does not add a management-plane deployment collector.
- Live Railway dashboard Foundation section and current Defence panel refreshed. Deployment `a967b278-50c0-41c5-b46f-08602b436b71` observed SUCCESS. Readback confirmed exact deployed code and no staged changes. URL: https://shine-universe-dashboard-production.up.railway.app . Authentication and icons retained. Local handler checks confirmed 503 when unconfigured, 401 without access, 200 for valid test credentials, refreshed content and health route.
- Earlier static Library HTML remains historical. The live hosted snapshot clearly distinguishes the Foundation refresh time from other scopes. Integration/acceptance remain unverified; prior findings remain expandable history.
- Live unauthenticated access-evaluation smoke request `303560` returned HTTP 401 `unauthenticated`, with no timeout. This is a negative access boundary test, not a successful authenticated cross-app test.
- Current readiness remains degraded for runtime latency and one historical open audit trace. At 17:08, v93 had 13 complete audit chains and zero broken current-runtime chains. The historical v90 outcome remains absent.
- Health log inspection showed five v93 /health invocations between 42 and 310 ms and one at 5414 ms, all HTTP 200 in ap-southeast-2. Probe timings also show slow 5-minute-interval requests and fast warm requests. Cold-start overhead is a hypothesis, not established causation; no warning threshold or historical evidence was altered.
- Integration inventory contains two active clients and nine active invocation adapters. All nine adapter-health rows have null last_event_at despite available labels. These labels are not fresh execution proof. Existing v93 adapters treat missing/stale health evidence as unknown.

### Remaining verification requirements

Authenticated cross-app success and denial/revocation checks need a valid existing client/user session and reviewed test resources; stored credential hashes cannot be used as bearer credentials. No new identities, credentials or personal grants were created. Product acceptance requires the corresponding real user workflow. The batch is still not represented as 25 newly completed build layers.

## Current release — v94 audit retry patch, 8 November 2026, 17:42 Brisbane

- PR #211 merged after both GitHub workflows completed successfully: Foundation + Concierge run 42459518881 and Defence run 42459518941. The SQL persistence job and contract job both passed.
- Retry prevention is now live in Supabase gateway v94. It retries only an outcome audit write once with identical evidence; it never repeats a domain operation. Persistent audit failure retains the completed response and remains observable. No old audit outcome was invented.
- All 31 deployed files were compared with the uploaded bundle. Only the HTTP handler changed from v93. Archived release: foundation/releases/audit-outcome-retry-gateway-v94.json at source commit 2af08b6b767bfa5ea41e9a9596a4e31a452a2cf5.
- Artifact SHA-256: ae18126784563b871230c5f0b0931160d0f41feda99a2c2df7e61ac2c6cc2152. Canonical file digest: bb92361ecd58742f687fd161ed651243c85e02f442638363fc08c24b626a05f6.
- Re-ran the module suite against the exact v94 file bytes: 235 passed, zero failed.
- GitHub OIDC receipt publication run 42459741134 passed; receipt e62e79a4-c261-4c54-81fc-4c0e91d09afc, publication 56e07ab2-e18e-4908-88ea-355052e03745.
- Exact-bundle Defence re-attestation run 42459741107 completed SUCCESS. All seven database posture controls pass; no missing artifact-bound evidence.
- Immutable binding d47612d6-ee60-438a-af62-6e154bf504b3, release foundation:layer-225:2af08b6b. Binding passes; Universe projection is aligned. This is a patch to Layer 225, not a claim of 25 newly completed layers.
- Three deployment smoke probes (303724–303726) returned HTTP 200 with a valid health contract. Their aggregate p95 was 13.766 ms. This small warm deployment sample does not prove the intermittent latency is resolved.
- Negative live consent request 303727 returned HTTP 401 unauthenticated and produced a complete v94 policy/outcome chain. No grant was issued.
- Readiness observation 381c170d-ce83-4e28-90c8-2349ec2e1795 remains degraded because of the historical open v90 audit trace. Current v94 runtime has a complete audit chain and no broken chain.
- Correlating platform logs by execution ID refines the latency evidence: request 10717a4d-a5e8-4bf5-8d96-0c73b0199e06 took 4510 ms, boot 615 ms and CPU 34 ms; request c17298fc-ac5a-40ab-a239-7bf43fb4eea1 took 5414 ms, boot 345 ms and CPU 26 ms. This points to waiting/platform overhead but does not establish the exact cause. The earlier uncorrelated boot estimate must not be used as a matched measurement.
- Dashboard refreshed to v94 and deployed successfully as 8fd90680-c9be-43bb-b2dc-01141be0d3f6. Access control/content checks passed. Historical snapshots retained; integration/acceptance remain unverified.

Remaining: a valid existing client/user session and reviewed test resources are required for authenticated positive access, cross-account denial and revocation/invocation checks. Hashes in credential stores are not usable bearer credentials. A real user workflow is required for product acceptance. Future provider-version drift collection, intermittent latency diagnosis and the historical audit incident remain open.

## Credential discovery — 8 November 2026, 17:49 Brisbane

The existing VC Foundation live integration credential was issued on 8 October and expired on 7 November 2026 at 22:48 Brisbane (12:48 UTC). Its stored Vault reference was found and matched to its registered hash without exposing the secret. The effective-credential view confirms expired. Live request 303770 to the app status route, with that stored credential passed internally, returned HTTP 403 app-caller-unverified. Expiry enforcement works.

The credential ledger is append-only. No expiry was extended and no trigger was disabled. Prepared an unexecuted atomic replacement proposal in foundation/operations/proposed-vc-service-credential-renewal-20261108.sql: generate a new 256-bit service token, store only its hash in the ledger and its encrypted value in Vault, expire after 30 days, preserve the old expired record, and leave all user grants/scopes unchanged. Activation awaits Doug's decision on the new authentication period; no replacement has been issued. An authenticated user test session remains a separate requirement for personal cross-app access tests.

## Approved VC service credential replacement — completed

Doug explicitly approved issuing the prepared 30-day replacement. The atomic operation completed at 17:53:09 Brisbane on 8 November 2026. Replacement label VC Foundation live integration v2 is active until 17:53:09 Brisbane on 8 December 2026. Its encrypted Vault value matches the registered active hash. No plaintext token was returned to chat or written to the repository. The old expired record remains intact.

Four live v94 checks passed: own VC status HTTP 200; Travel status using the VC credential HTTP 403 app-caller-mismatch; original expired credential HTTP 403 app-caller-unverified; valid replacement app credential without user credentials HTTP 401 unauthenticated on personal access evaluation. Requests 303796–303799; no timeouts. Machine-readable evidence: foundation/evidence/vc-service-authentication-20261108.json.

This verifies service authentication and isolation. It does not establish user-authorised access, cross-account/revocation success, product acceptance, or rollout of the new Vault reference to every VC consuming deployment. No personal grants, scopes, identities or client links were changed.

## Deployed VC consumer credential rollout — completed 8 November 2026

Located the actual VC Railway consumer: project d6e85c16-1f57-489b-9dfd-cc1963f765da, production 88d23731-f8c6-45c6-b55a-d7fedc82a071, service 505db8ca-1226-4987-88f6-ccf31219e2b2. Verified deployed source 8592242ca0b92310a053919427f2a2d051a97036 on codex/cadj-live-release-20261026, rather than assuming repository main.

Installed the approved v2 replacement in the existing VETERAN_FOUNDATION_APP_TOKEN variable through an internal secret transfer, without returning the value to model-visible output or writing it to a file. Redeployed the existing build explicitly. Deployment e3624f47-9a86-4b5c-ae31-054bc66e1ad0 reached SUCCESS and retained the same source commit. The build/test/build command completed. No unrelated variables were changed.

The deployed server calls createVCFoundationServerMount() without protected owner-service dependencies. Its public memory-read handler deliberately returns 503, reports retrievalPerformed=false/resultReturned=false, and does not parse credentials or invoke read authority. The eleven named owner groups in foundation-owner-services.mjs have not been composed in server.mjs. This corrects the earlier overly narrow conclusion that a user session alone was the remaining blocker: user sign-in cannot supply missing protected service composition.

Machine-readable findings: foundation/evidence/vc-consumer-rollout-and-integration-gaps-20261108.json. Post-deployment checks queued as 304045 (health) and 304046 (closed memory transport). Full user-authorised integration and acceptance remain unverified. No synthetic users or personal grants were created during this continuation.

## Durable VC orchestration owner — implemented and CI verified

Implemented three protected callbacks (current task, checkpoint and retry identity) in Shine-Veteran- PR #904, merged to codex/cadj-live-release-20261026 at 6c94ae0983d0253279b938e02a2ca8b48beafa8d. Queries enforce exact owner/binding, current state, expiry and matching revisions. Checkpoint withdrawal or task cancellation prevents reuse. The provider uses transaction-local SELECT-only role access and returns no memory content.

Applied vc_foundation_orchestration_owner_store_v1 to VC project akyzwuvfvugzyauaptsk. All three private metadata tables have RLS enabled; anon/authenticated have no schema usage; all row counts are zero. Only the existing postgres administrator has an administrative reader-role membership, with SET/INHERIT false after testing. No runtime login, user identity or personal grant was created. Rolled-back SQL acceptance checks passed; fixture data and temporary test permission were not retained.

GitHub Actions run 42476839268 completed SUCCESS: 11 tests passed, zero failed and zero skipped, including the real PostgreSQL 17 provider test. It verified positive owner reads, wrong-owner denial, checkpoint withdrawal, cancellation and pooled transaction-role isolation. Ten unit tests also passed locally.

The source is merged but not yet configured in the live server. Railway's latest observed deployment remains e3624f47-9a86-4b5c-ae31-054bc66e1ad0 at source 8592242ca0b92310a053919427f2a2d051a97036. No new deployment was claimed. A protected bounded pool, remaining nine owner groups and trusted server composition are still required. Public memory-read transport remains closed and user-authorised integration/acceptance remains unverified.

Evidence: foundation/evidence/vc-orchestration-owner-20261108.json. This increment does not represent 25 completed layers.

## Protected VC identity backend — source merged, activation pending

Implemented the identity adapter's concrete Foundation/VC PostgreSQL dependencies and current Auth policy reader in Shine-Veteran- PR #905, merged at 67af917ad29ecc04d54e89dc5e89ceaeadcb5531. SQL is restricted to the three exact parameterised adapter statements; lookup values and project/provider/app scope are validated. Transactions assume dedicated reader roles and return only required metadata. The current-policy reader uses the fixed VC Management API GET endpoint with redirect denial, no cache and a 2.5-second deadline. Missing/nullable fields deny access rather than implying unrestricted sessions.

Validation: ten identity unit tests passed locally; twenty combined identity/orchestration unit tests passed. GitHub Actions 42477387743 completed SUCCESS with eleven tests, zero failures and zero skips. The PostgreSQL 17 test exercised actual RLS/column-restricted queries through the existing identity adapter: wrong-subject, revocation, logout, expiry, banned/deleted/anonymous users, and disabled/unverified identity bindings denied. Sensitive email/password/refresh-token columns and writes were denied. SDK token verification was stubbed in this database test; this is not a live authenticated user workflow.

Live metadata inspection confirms the VC provider, app association and app registration are active, the provider key has the required publishable format, and the three Auth tables have RLS enabled. No key value or personal record was retrieved.

The two reader role/policy SQL files are proposals, not live migrations; Auth policy changes require the actual Auth table owner. No runtime login, management credential, personal binding, session, auth setting or token was changed. Protected pools, appropriate current-policy credential custody, companion credential custody, remaining L/memory/recipient/health owner services and server composition remain outstanding. The public memory route remains closed. Latest observed Railway deployment remains e3624f47-9a86-4b5c-ae31-054bc66e1ad0 on source 8592242ca0b92310a053919427f2a2d051a97036; merged source is not claimed as deployed.

Evidence: foundation/evidence/vc-identity-owner-20261108.json. No layer counter increase or full integration/acceptance claim.

## VC credential custody backend — implemented, table installed empty

Shine-Veteran- PR #906 merged at 62bb9f2b2ee4c96db29a82c1133c93a3347c5de6. The new owner implements the existing credential adapter's two callbacks using exact owner/app/purpose/audience/revision queries. It reads AES-256-GCM sealed contexts and requires independently protected key custody; the database reader cannot access Vault. Authentication binds the reference, owner, scope, revision, expiry and key ID. A fresh metadata lookup after key retrieval/decryption withholds results withdrawn during the wait. No HTTP credential response or credential writer was added.

Eleven local unit tests passed. GitHub Actions 42477879159 completed SUCCESS with twelve tests, zero failures and zero skips. The PostgreSQL 17 test ran the actual adapter/provider, including positive synthetic resolution, wrong owner/revision, tampering, resealing, revocation during key retrieval, immutable binding, expiry-extension and terminal-state guards, and client/reader write denial. The initial local cross-owner substitution test was corrected to replace both ciphertext and authentication tag, so it actually tests a foreign authenticated envelope; the complete corrected suite passed.

A rolled-back VC database dry run also passed guard/permission assertions. Applied migration vc_foundation_credential_custody_v1 to akyzwuvfvugzyauaptsk. Post-readback: credential_references has zero rows, RLS enabled, no anon/authenticated schema usage, SELECT-only ciphertext/metadata reader, no reader Vault usage or SELECT, NOLOGIN/NOSUPERUSER/NOBYPASSRLS. Only the postgres administrative creator membership exists with SET/INHERIT false. No synthetic fixtures, keys, credentials, runtime login/membership or personal grants were retained/created.

Health advisors returned no notices. Security advisors retained the same unrelated informational findings and leaked-password-protection warning; no finding for the new custody table.

Server composition remains unconfigured and public memory-read stays closed. A bounded protected pool, separately provisioned key custody, a consented credential enrolment/writer and the remaining L/memory/recipient/health owner services are still needed. The renewed VC app service token is not a per-user companion/recipient credential context. This source/schema increment is not a live authenticated integration or acceptance result and does not increment the layer counter.

Evidence: foundation/evidence/vc-credential-custody-20261108.json.

## VC companion-link backend — 9 November 2026 Brisbane

PR #907 merged at 0338c0736b281dfa1cce3344bbf8704213af1f49. Implements the existing companion-link adapter's durable owner lookup. A general Foundation companion link alone does not qualify: an explicit active VC association for the same owner/link is required. The provider independently reads the canonical Foundation client/account/link and revocation state, bounds expiry by the earlier source expiry, then re-reads the VC association to detect withdrawal/revision change during the cross-database lookup.

Ten unit tests passed locally. GitHub Actions 42536314902 completed SUCCESS with eleven tests, zero failures/skips, using two independent PostgreSQL 17 services. Verified wrong-owner denial, canonical-only denial, withdrawal on either side, disabled client/account, expiry, immutable bindings, terminal state, restricted columns/roles and final VC reread. The sequence is not a distributed atomic snapshot; the surrounding invocation still needs current admission/rechecks.

Both database provisioning scripts passed rolled-back dry runs. Applied vc_foundation_companion_link_v1 to VC and foundation_vc_companion_link_reader_v1 to Foundation. VC association table remains empty with RLS enabled and browser schema access denied. Both reader roles are NOLOGIN/NOSUPERUSER/NOBYPASSRLS, have no writes, and have no runtime membership. The only administrative creator memberships have SET/INHERIT false. A restricted-role canonical query with sentinel IDs executed successfully and returned zero rows; temporary test membership was rolled back. No personal link/binding, consent or grant was created or modified. Foundation's reader cannot select private client metadata.

Post-change security advisors retain the same pre-existing findings with no new companion-link issue. Source is merged, not claimed as configured in the live server. L client/user proof verification remains unimplemented; protected pools, consented enrolment, remaining memory/recipient/health owners and trusted composition remain outstanding. Public memory transport remains closed. No layer counter increase or live integration/acceptance claim.

Evidence: foundation/evidence/vc-companion-link-owner-20261109.json.

## Companion client and L user proof owner — 9 November 2026 Brisbane

Implemented both remaining L identity callbacks in PR #908, merged at 8e34c949b90f3d0b23cd5c841cfc960dd9cebdee. Companion client proof uses the fixed existing Foundation client-status GET endpoint and only its client token. User proof uses the active registered supabase:shine-l provider, actual pinned SDK getClaims/getUser verification, fixed Project L issuer/audience/session checks, current Auth policy, current Auth session/refresh/account state, canonical verified Shine binding, and a final session reread to catch logout during binding lookup. Metadata supplies no identity.

Ten local unit tests passed. Initial CI 42553266163 completed SUCCESS with eleven tests. The integration test used two independent PostgreSQL 17 services and the actual SDK with synthetic ES256 keys/JWKS; an altered signature was rejected. No synthetic key/token was installed live and no live user login is claimed. Live invalid-client request 309657 returned HTTP 403 integration-client-unverified without timeout.

Provisioning exposed a real hosted permission gap. Foundation reader migration foundation_vc_l_identity_reader_v1 applied and effective schema USAGE is verified. Project L migration project_l_vc_session_reader_v1 reported success and installed column grants/RLS policies, but GRANT USAGE on schema auth did not take effect. A role-scoped session query failed permission denied for schema auth. Current postgres lacks Auth-schema USAGE WITH GRANT OPTION. Reader has no Auth-schema USAGE and remains unusable; migration API success is not readiness.

PR #910 fixes both L and VC Auth reader provisioning scripts to assert effective USAGE immediately after GRANT. It reproduces a limited provisioner with USAGE but no GRANT OPTION and checks transaction rollback, including rollback of the new reader role. Both final workflows passed: L proof 42553626420 (eleven tests, zero failures/skips), VC identity 42553626584. Merged at f70816de6e2de9b7591f20582c25b04914da9353. The updated assertion is source protection; it does not retroactively repair the already-partial live L installation.

Prepared, but did not execute, the narrow schema-owner operation foundation/operations/project-l-auth-schema-reader-owner-grant-20261109.sql. The actual Auth schema owner must grant USAGE to vc_foundation_l_identity_reader, then verify a reader-scoped sentinel query. No broader role membership, ownership changes or RLS bypass were introduced. Existing VC identity reader proposals remain unapplied; they need the same effective schema-access verification.

Both new readers remain NOLOGIN/NOSUPERUSER/NOBYPASSRLS with no runtime membership. Project L reader cannot select email/password/refresh-token values or write sessions. No real users, sessions, tokens, identity bindings, companion links or personal grants were changed. Security advisors retain the same pre-existing findings.

Runtime pools, current-policy credential custody, remaining memory/recipient/health owners and trusted server composition remain outstanding. Public memory transport remains closed. No acceptance event or layer-counter increase is asserted.

Evidence: foundation/evidence/vc-l-identity-owner-20261109.json.

## Selected-memory consent owner — 9 November 2026 Brisbane

PR #911 merged at 3350960df1843c0e9c6b2b558be616b28e7c2e0f. Implements current selected-memory consent and owner permission-revision callbacks. A single SQL snapshot returns the exact app/client/owner/link revision/memory version/preparation/scope/purpose grant metadata with its owner revision. Missing owner ledger remains unknown; no implicit zero/empty authority. Revoked grants remain visible as revoked. Overflow/ambiguity denies completeness.

Consent insert/update advances the owner permission revision atomically. Failed or duplicate writes roll back that advance. Bindings, dates and evidence are immutable; revoked grants cannot reactivate, consent history cannot be deleted and revision counters cannot reset/delete. This is a reader and ledger schema, not a consent enrolment interface.

Ten local unit tests passed. CI 42556818071 completed SUCCESS with eleven tests, zero failures/skips, including the actual adapter/provider against PostgreSQL 17. Concurrent revocation checks showed coherent pre-commit active/revision-1 and post-commit revoked/revision-2 snapshots; failed writes did not advance the counter. Exact scope, history retention, immutable/terminal guards and restricted columns/client/write access passed.

Applied project_l_selected_memory_consent_v1 after a successful rolled-back Project L schema/permission dry run. Both private tables have RLS enabled and remain empty (zero owner revision rows and zero grants). Reader has effective schema USAGE, required metadata SELECT only, no write or private evidence-reference access, NOLOGIN/NOSUPERUSER/NOBYPASSRLS, and no runtime membership. Browser roles have no schema USAGE. A reader-scoped sentinel query executed successfully and returned zero rows; temporary test membership was rolled back. No real owner ledger, consent, grant or personal record was created/changed.

The current L catalogue has text source IDs and content, but the exact UUID/version/owner mapping required by the selected-memory contract is not yet established. VC appointment preparation and draft consent-plan tables were inspected by schema only; no existing OAuth/draft/search record was promoted to per-record permission. Memory descriptor/preparation mapping, content reader, recipient/health services, trusted enrolment/writers and server composition remain outstanding.

The prior Project L Auth permission blocker was rechecked and remains: reader Auth-schema USAGE=false and current connection grant option=false. This independent consent increment does not bypass it. Public memory transport stays closed; no live integration, acceptance or layer-counter increase asserted.

Evidence: foundation/evidence/vc-selected-memory-consent-owner-20261109.json.
