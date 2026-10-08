# Foundation Live Integration — layer 01/20: consumer wiring and ownership

Date: 8 October 2026 (Brisbane).
Baseline: `bbe104e5929edce61ef690d02b7d4bc71df80bc4`.
Historical count retained: **40/40 source sprint + 2 follow-on source increments**.
This layer delivers the versioned consumer wiring contract. It does not mount VC or verify live behaviour.

## Producer identity and consumer boundary

The companion `foundation/contracts/vc-live-consumer-wiring-v1.json` pins
`foundation/onboarding/veteran-care-server-read-v1.mjs` at Git blob `33cfc615c4fb6f871a0665679acc5656e4b16607`, exporting
`createVeteranCareServerReadEntryPoint` and `VETERAN_CARE_SERVER_READ_ADAPTERS`.

Foundation owns composition and checks. VC Integrations / Security owns the trusted server mount.
The consumer repository, branch, mount path and release commit are explicitly unresolved; they must be recorded from inspected current source before consumer rollout. Responsibility assignments are handover requirements, not owner acknowledgements.

The factory accepts only server-owned configuration, the exact 19 callable adapters and an optional server clock.
Input is exactly `{checkpointId,credentialReferenceId,authContext:{appToken,jwt}}`.
It inherits all query/return records from the pinned source and its transitive modules without translation.
A missing dependency preserves the frozen blocked entry point. `dependencies-configured` and `authorityProvided:false` do not prove permission, callback correctness or connectivity.

## Adapter responsibility

| Responsible room | Required callbacks |
| --- | --- |
| VC Integrations / Security | `verifyAppCaller`, `verifyIdentity`, `getClaims`, `getSessionState`, `verifyResultRecipient`, `getCurrentVCCapabilityHealth` |
| L / Companion | `verifyIntegrationClient`, `verifyCompanionUser`, `getCurrentVCCompanionLink`, `getMemoryDescriptor`, `getPreparationContext`, `getMemoryPermissionContext`, `getCurrentMemoryPermissionRevision`, `readSelectedMemory` |
| VC Orchestration | `getCurrentVCTask`, `getCurrentResumeCheckpoint`, `getExistingRetryIdentity` |
| Credential custody / Security | `getCurrentCredentialReference`, `resolveCredentialReference` |

L owns independent Companion proofs, owner binding, selected memory and separate consent/revocation/read authority.
Orchestration owns durable task/checkpoint/retry authority.
Credential custody / Security owns fresh protected reference resolution.
VC Integrations / Security owns current caller/session/recipient verification and authenticated health collection.
Foundation retains reusable gate semantics; no other room's adapters or database schema are changed here.

## Safe consumption

Success remains private to trusted VC server orchestration. No browser/model serialisation, logging of content or tokens, network transport, model disclosure or memory writes are authorised by this contract.
Downstream disclosure requires separate current checks.
All reads use fresh authority and final rechecks; checkpoint/retry metadata never carries saved permission.
Health can block a read but cannot grant permission.
Trusted callback provenance must be independently inspected; merely returning an echoed assertion is insufficient.
The entry point cannot sandbox trusted callbacks or guarantee cancellation of every downstream in-flight operation.

## Evidence and dependencies

Layer-40 and checkpoint-02 receipts were read at the exact baseline.
Their recorded tests are historical, not rerun by this documentation layer.
The producer export list is compared with this manifest: exactly 19 unique callbacks, each assigned once, and the producer path/blob verified against the baseline tree.
Configuration and request keys are checked against the actual source.
No runtime code is changed and no live/private read, database operation or deployment is performed.

Open: exact consumer source/mount identity; protected implementation and provenance for every callback; independent current registration/configuration evidence; owner acknowledgements; joined live synthetic withdrawal/outage tests; exact deployed-release acceptance.
These gaps do not block pinning the producer contract, but they block live readiness.
No room has been contacted or notified by this change.

Next layer: package the pinned Foundation server modules for VC consumption.
