# VC readiness layer 40 — readiness handover

Baseline: `1b68f509c0c7763eec9903f88cdd583739012c20` (layer 39 merged).
Completion condition: merge this handover after all three CI checks pass.
After merge: **40/40 source-sprint layers complete; 0 remaining (0%).**

## Readiness decision

The source sprint is complete when this layer merges. **Live integration and production readiness remain unverified.** Source contracts and synthetic checks provide implementation evidence; they do not certify deployed VC, AI or L services, current production permissions, real backup custody or a production release. No deployment, live database restore, credential restoration or rollback was performed by this sprint.

The accompanying `vc-readiness-20261008-layer-40-manifest.json` indexes all 39 prior VC receipts by exact path, heading and SHA-256. These VC sprint numbers are distinct from the repository's older Foundation layer sequence. This handover is layer 40; it is intentionally outside the prior-receipt digest list to avoid a self-referential hash. The baseline identifies the merged source reviewed, not a deployed artifact.

## Completed source work

| Layers | Delivered boundary | Evidence and limits |
| --- | --- | --- |
| 01–10 | Dedicated VC identity/project, audience/session checks, exact resources, deny-by-default purpose-bound grants and expiry | Local identity/access proof; configured identifiers still require current registry and project verification |
| 11–20 | Revocation propagation/acknowledgement, stale and in-flight rejection, delegation, read/write separation, content-free audit, safe denial and outage handling | Joined synthetic revocation journey; deployed propagation and real withdrawals remain open |
| 21–30 | Independent AI caller, permission envelope, opaque private handles, L binding, separate selected-memory consent, read-only retrieval, bounded tool proposal, recipient and task authority | Joined 25-assertion VC–AI–L proof and nine-module source witness; no real tokens, model disclosure or transport |
| 31–35 | Retry identity, fresh resume, checkpoint failure handling, credential references and dependency health | Fail-closed synthetic adapter tests; protected stores, vault, scheduler and live health collection remain open |
| 36 | Nine-asset recovery inventory and metadata inspection contract | All saved inventory evidence is not inspected; recovery targets are unapproved. Metadata coverage is not restore permission |
| 37 | Isolated synthetic PostgreSQL dump/restore, schema/data/constraint parity, forced RLS, least privilege, owner isolation, paused task and cleanup | Actual database operations in CI's disposable PostgreSQL service; not a hosted VC/Supabase production restore |
| 38 | Restore followed by independently advanced revocation authority and reconciliation | 13 synthetic PostgreSQL continuity assertions; stale authority, missing ledger/watermark and tombstone loss fail closed |
| 39 | Exact approved source/artifact and independent provider/runtime observation for release or rollback | Observer only; no deployment mutation. Historical source bundles are restore-proof source, not VC deployable artifacts |
| 40 | Evidence index, ownership handover and live acceptance backlog | This receipt and handover manifest; completion depends on this PR's successful CI and merge |

## Verification record

The reviewed layer-39 baseline passed **439 local onboarding/runtime tests** and all three GitHub checks: `foundation-contracts`, `registry` and `persistence`. Layer 40 adds documentation and the receipt index; it does not change runtime behaviour. Re-run the same local suite, check the index's receipt digests and run all three checks for the layer-40 PR before merging. The PR/check history is the authoritative record of that run; this document does not predict its outcome.

Reproduce local checks from the repository root:

```sh
node --test foundation/onboarding/*.test.mjs foundation/runtime/supabase-runtime-adapters-v1.test.mjs
git diff --check
```

CI additionally runs the guarded isolated-restore and restored-revocation drivers against synthetic PostgreSQL. Both drivers require explicit CI authorisation and local synthetic connection parameters. Do not run them against production or substitute a production archive. Saved joined-proof witnesses, the layer-36 inventory and the layer-39 source bundles retain their explicit evidence scope.

## Live acceptance backlog and ownership

These are proposed responsibility areas, not evidence that a named individual has accepted ownership. Each owner must supply current independent evidence and protect the adapter boundary; an adapter returning an echoed assertion is insufficient.

| Responsibility | Required acceptance evidence before a live readiness decision |
| --- | --- |
| VC Integrations / Security | Verify the current `shine.veteran-care` registry entry, dedicated project/issuer and audience; real verified sessions, independent AI caller proof, service principals and protected adapter routing |
| Foundation / Defence | Current grant/revocation authority, durable acknowledgement/freshness, permanent grant-ID tombstones, deployed deny-by-default policies and withdrawal during an actual protected read |
| AI integration | Approved narrow tool policy and independent caller/proposal verification; demonstrate no unauthorised model disclosure or execution. The implemented proposal gate does not itself invoke a tool |
| L / Companion integration | Current `shine.companion` client and same-owner binding, separate version/purpose/preparation-bound memory consent, actual selected read and an independently verified VC recipient |
| VC Orchestration | Durable atomic retry binding, current checkpoint storage and compare-and-swap/readback, fresh resume authority and cancellation handling. No source gate grants a scheduler lease or exactly-once execution |
| Credential custody / Security | Protected vault resolution, encryption/custody and rotation/revocation; checkpoints and returned metadata must contain no tokens or secrets |
| Health operations | Authenticated protected collectors and independently fresh dependency evidence, including bootstrap outside business reads; green health supplies no permission |
| Recovery owners from layer 36 | Accepted owners, backup custody, approved recovery targets/retention, independently checked artifacts and an isolated restore of the actual hosted schema/data/roles/extensions/storage/auth dependencies |
| Foundation / Defence and recovery owners | Real post-backup authority reconciliation, current epoch/revision and ledger digest, deployed tombstone enforcement and fresh task/credential authority before any resumed work |
| Authorised release workflow / VC Integrations | Real immutable deployable artifact digest and custody, approved exact target, independent provider/runtime observations, current schema compatibility and retained current revocation authority for rollback |

Use staged, approved live journeys with independent evidence for wrong owner/audience, withdrawn/expired consent, permission-service outage, cancellation, vault rotation, stale health and restored authority drift. Record environment, exact deployed commit/artifact, timestamps, evidence mode, current authority and pass/fail without private content or credentials. Acceptance must be explicit for each gap; synthetic success must never be relabelled live.

## Operational boundaries retained

All private reads require current identity, resource, permission, purpose, recipient and task checks. Retry identities and checkpoints are correlation/progress metadata, not reusable authority. Credentials resolve freshly through a protected reference. Late revocation/cancellation withholds results; source checks cannot abort every already-running downstream operation or create a distributed lock.

Restore requires current independently reconciled authority; it cannot revive permissions from the archive. Rollback must retain current compatible schema and revocation authority, not downgrade them to match an older binary. The layer-39 observer only checks an already observed target. Its `deploymentMutationPerformed`, `rollbackPerformed` and `permissionsRestored` flags remain false.

The next phase is the live acceptance backlog above, with owner acknowledgement and independent evidence. There is no layer 41 in this 40-layer source sprint and no automatic production-readiness approval at completion.
