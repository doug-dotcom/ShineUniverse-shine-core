# VC readiness — layer 05: session authority checks

8 October 2026, Brisbane. Source baseline: 1d7bed876e7ceceec1cb9b083bca27eaa997f31f.
After successful merge: 5/40 source-verified producer layers; 35 remain (87.5%). This counter is independent of VC consumer acceptance.

## Enables Veteran Care

createVeteranCareSessionIdentityVerifier composes the dedicated-project, caller, identity and verified-audience checks with mandatory session authority. It withholds identity unless the verified JWT has a valid session ID, bounded numeric token expiry and satisfied optional not-before. It looks up the exact verified session/user/project on every request, without caching successful results. Missing, revoked, inactive, mismatched or expired session state denies access. Lookup errors and invalid/regressing server clocks fail closed with bounded unavailable responses.

Token expiry and effective session expiry are checked again after the asynchronous lookup. Caller session IDs, browser state and decoded claims cannot supply the lookup identity. The lookup receives no tokens or secrets. Successful output remains server identity/audience context, not a grant or portable credential.

## Contract and ownership

Foundation producer: foundation/onboarding/veteran-care-session-v1.mjs, version 1, isolated branch foundation/vc-readiness-layer-05. Layer-04 audience guard gains an optional server session hook; its previous audience-only API remains available, but it does not certify session liveness. Consumers requiring this layer must use the session-bound factory.

getSessionState is a mandatory trusted server dependency. Input: {sessionId,authSubject,providerId,appId,issuer}, derived from verified claims/identity. Output: null for absent sessions, or {status,sessionId,authSubject,issuer,expiresAt}. Only status active is accepted; expiresAt must explicitly be numeric Unix seconds or null for no session time-box. The adapter must check dedicated-project session existence and effective inactivity/time-box policy; existence alone is insufficient. It must perform a fresh authoritative lookup, not return a browser session or cached token validity.

VC Integrations & Security owns actual session lookup implementation/credentials, dedicated-project client setup, consuming branch, browser sign-in/sign-out/recovery, deployment and live acceptance. No Auth schema, SQL, key, account, record or VC application file changed. The guard is point-in-time verification: revocation after lookup and long-running work still require checks at the consumer's sensitive operation/delivery boundary. Grant revocation remains a later distinct Foundation outcome.

Shine AI retains independent caller admission, replay controls and its service policies. This context cannot bypass them. No AI files or models changed.

## Coordination evidence

Read latest VC main e7eb5a03a801a92a57b504ec2283971d20c7f33c:
- VC-AUTH-RECOVERY-20261008-L06.md, blob e7d37c1210fd1bcb3549153e33cc447218ec2b0e: source tests pass; real sign-in/recovery remains pending.
- VC-L07-SESSION-NAVIGATION-20261008.md, blob 5aab68ad49ea2fadba2530d5a9d308f86322a608: browser-navigation lifecycle guard implemented; live provider expiry/sign-out and BFCache acceptance remain pending.

This server-side shared-service guard complements that browser work. It does not implement or claim those consumer outcomes. Repository handover is discoverable coordination, not acknowledgement by other active chats.

## Verification

Command: node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
96 passed, 0 failed, including 14 new tests. Synthetic JWTs and mocked claims/session authorities verify binding, absence/revocation, malformed/expired proof, not-before, policy expiry, expiry during lookup, clock failure, bounded outage, per-request rechecking, caller/audience rejection and concurrency isolation.
Foundation CI includes the new suite; Foundation and Defence workflow success is required before merge.

No real signed-token, hosted session lookup, private browser, production deployment or live revocation acceptance is claimed. Open: real dedicated-project session adapter and consumer wiring, sign-out/revocation probes, effective timeout enforcement and exact deployed version.

## Sources and next

Supabase changelog checked on 8 October 2026. Official docs: https://supabase.com/docs/guides/auth/sessions and https://supabase.com/docs/guides/auth/signout . Signed-token verification alone does not establish current session liveness; deleted auth.sessions rows and effective session policy must be checked where required.

Next: layer 06, exact resource scoping.
