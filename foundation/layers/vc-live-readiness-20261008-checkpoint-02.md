# VC live readiness — increment 02: protected server read entry point

Baseline: `74b49901111cfd9a80b592464512136423f10519` (checkpoint 01 merged).
After merge: original source sprint **40/40 complete**, subsequent live-readiness increments **2 complete**. No new sprint denominator has been assigned. This increment delivers source composition; live mounting and private integration acceptance remain open.

## Behaviour

`createVeteranCareServerReadEntryPoint` composes the actual layer-35 capability-health gate and its credential-reference, resume, retry, task, recipient, selected-memory consent, L binding and current VC session chain. It accepts server-owned `{configuration,adapters,clock?}`. App and provider are fixed internally to `shine.veteran-care` and `supabase:veteran-care`. Configuration must match the existing dedicated-project descriptor; matching strings are a prerequisite, not independent registration or deployed-project evidence.

Missing, non-callable, malformed or accessor dependencies yield a frozen blocked entry point without invoking any authority or read adapter. Configuration/adapter function references are captured at construction. Unknown keys, symbols, inherited configuration and composition overrides are refused. All time checks share the supplied server clock (default Date.now); request data cannot supply clocks or gate factories. Reconfiguration requires a new entry point.

The returned object has `configurationStatus: 'blocked' | 'dependencies-configured'`, `authorityProvided: false` and `readSelectedMemory(input)`. Dependencies-configured records only that required functions and configuration were supplied; it does not attest callback correctness, freshness or live connectivity.

Input is exactly `{checkpointId,credentialReferenceId,authContext:{appToken,jwt}}`. IDs must be canonical UUIDs, app proof is bounded to 8192 characters and JWT to 16384. Credentials are captured before asynchronous calls. Caller-supplied selections, authority flags, recipient credentials, write requests and health assertions are rejected. The selected resource/task/retry binding comes from current protected checkpoint authority; fresh Companion/recipient credentials come from the protected reference resolver.

Every invocation executes fresh authority checks. A successful internal result has status `server-read-result`, `serverOnly: true`, and retains the chain's private result, current bounded deadlines and evidence modes. Model disclosure, writes and transport remain false. Failures expose a fixed redacted reason and accurately track whether the actual read adapter was invoked, while withholding content. Concurrent requests hold separate retrieval state and re-resolve credentials; no content or permission is cached.

## Trusted dependency interface

`VETERAN_CARE_SERVER_READ_ADAPTERS` exports the exact required 19 callback names:

| Protected boundary | Required callbacks |
| --- | --- |
| VC verified identity/session | verifyAppCaller, verifyIdentity, getClaims, getSessionState |
| Companion binding | verifyIntegrationClient, verifyCompanionUser, getCurrentVCCompanionLink |
| Selected memory/purpose/consent | getMemoryDescriptor, getPreparationContext, getMemoryPermissionContext, getCurrentMemoryPermissionRevision, readSelectedMemory |
| Recipient/task | verifyResultRecipient, getCurrentVCTask |
| Resume/retry | getCurrentResumeCheckpoint, getExistingRetryIdentity |
| Credential custody | getCurrentCredentialReference, resolveCredentialReference |
| Health evidence | getCurrentVCCapabilityHealth |

Each callback retains the exact query/return contract in its existing layer module; this entry point does not translate or weaken those records. Pass standalone functions or explicitly bound methods. For example, getClaims must call the actual server-owned verifier with the explicit JWT; decoding claims or accepting request-provided verification is insufficient. The current-session callback remains mandatory alongside token verification. No Supabase SDK dependency, client setup or database schema is changed here.

Foundation owns this injectable composition. VC Integrations/Security must provide protected independent identity/recipient/health adapters and mount the consumer; L supplies verified Companion consent/read authority; VC Orchestration supplies current checkpoint, existing retry and task stores; credential custody supplies fresh vault resolution. No other room has been contacted or its ownership acknowledged by this change.

## Server integration contract

Import the factory into trusted Node server composition. Supply protected dependencies and the dedicated configuration, then invoke readSelectedMemory with a current VC proof and references. Treat blocked/dependency-configured states as composition status, never permission. Consume a successful result only within authenticated VC server orchestration. A missing adapter must preserve the blocked entry point rather than installing permissive fixtures or falling back to browser credentials.

This is an in-process server entry point, **not a mounted HTTP route**. It deliberately adds no JSON response handler, disclosure callback, logger, model invocation or network transport. Do not serialize its private success result to a browser/model; downstream disclosure/transport needs its own fresh checks. The factory cannot sandbox arbitrary trusted callbacks or cryptographically establish their provenance. Source tests use explicit synthetic authority/health evidence.

Checkpoint 01's Railway/source observation remains historical; this increment does not re-attest that deployment. No VC app repository change, deployment, private read or database operation occurred. Live wiring remains unverified.

## Verification

14 added tests cover default blocked state; every missing/non-callable dependency; actual joined success; wrong project and composition overrides; getters/symbols/prototypes; construction and request capture; request/token bounds; fresh session/owner/consent/task/recipient/retry/reference denial; late cancellation and health deterioration; redacted outages/invalid clock; concurrent fresh resolution; and credential rotation during retrieval.

**453/453 local onboarding/runtime tests passed**, and git diff --check is required before publishing. The new test module is explicitly registered in Foundation CI. Merge only after foundation-contracts, registry and persistence succeed; PR history records the actual outcome, including synthetic PostgreSQL restore/continuity checks. Prior joined-proof modules and their source witnesses remain unchanged.

Next: establish a consumer wiring contract and protected runtime adapter coverage for this entry point, then verify authorised synthetic live journeys. Configured callbacks alone do not close the live acceptance backlog.
