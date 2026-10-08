# VC readiness layer 38 — restored revocation continuity

Baseline: 60ecc7fe6679a8f7caa7ac22622cb3234228792e (layer 37 merged).
After merge: 38/40 complete; 2 remaining (5%).

## Behaviour

verify-veteran-care-restored-revocation-v1.mjs reuses the actual layer-37 isolated PostgreSQL dump/restore runner. Only after archive/schema/data/RLS parity succeeds does it exercise restored revocation precedence. The synthetic source authority advances its revocation revision from 2 to 3 after the archive has been taken and restored. Its current ledger digest is obtained independently from the source database; the restored database still has revision 2 and a different digest. Nothing in the backup supplies the newer watermark.

The isolated proof SQL adds a protected recovery watermark and a selected-read policy requiring exact current/applied authority epoch, revision and digest equality, plus agreement with the digest recomputed from the actual restored ledger. The selected grant must be active and have no revocation tombstone. This is deliberately an isolated proof schema, not a migration for the deployed VC data model. Existing owner RLS still applies. Recovery tables/functions are protected from public use and the reader cannot edit authority.

A separately unrevoked second-owner grant is the positive control. While the restored ledger lags the current watermark, both owners are blocked. After reconciliation, the positive control reads while the first owner's restored old active grant remains blocked by its later tombstone. Replaying the old active permission cannot undo withdrawal. Wrong epoch, unexpected ahead revision, missing ledger entry/digest mismatch and absent current watermark fail closed. Restoring the canonical ledger restores only the positive control's read. The task stays paused; no retry/checkpoint automatically executes.

The outer runner prints success only after all continuity checks and complete database/role/archive cleanup. Its report includes synthetic-postgres-ci mode, current/backup ledger SHA-256 values, proof SQL hash, 13 named checks, revocationContinuityVerified true and productionRevocationVerified false. Production backup/restore and fresh runtime authority remain explicitly unverified/required. The unchanged standalone layer-37 drill still reports revocation continuity unverified; only this extended proof can claim the synthetic continuity checks.

## Ownership and limitations

Foundation/Defence owns the continuity invariant and current authority watermark. VC Integrations owns durable production tombstones, authenticated watermark acquisition, reconciliation, digest/epoch integrity, role/policy enforcement and a separately isolated restore of the real schema. Orchestration owns keeping recovered tasks paused and reconciling original operation/checkpoint identity. L owns selected memory consent enforcement. Existing layers' fresh session, Companion user/link, selected consent, task, retry, recipient, credential and health checks are unchanged.

A trusted production reconciler must obtain the current watermark independently of the restored backup, verify complete ledger coverage and atomically apply the protected epoch/revision/digest. Missing current authority cannot become a default empty ledger. A restored or caller-provided self-attestation cannot establish freshness. This synthetic source/target share one disposable CI service; it does not verify distributed transport, signed watermark provenance or a production control plane.

The synthetic ledger uses permanent grant-ID tombstones. Reconsent needs a distinct newly authorised grant ID; replaying an old active row never clears its tombstone. The proof's digest compares canonical ordered JSONB of the complete ledger. Production ledger design, global ordering/partitioning, latest-watermark updates, concurrency isolation and missing-event detection must be established by the real adapters; this fixture is not a production schema prescription. No live grant or consent is created, revoked or restored.

These point-in-time database checks do not certify production recovery or make metadata a grant. Actual hosted schema, real post-backup withdrawals, authenticated canonical ledger transport, storage/Auth recovery and full consumer integration remain open. No production database, vault, credentials, runtime authority contract or cross-room state is changed.

## Evidence

2 local CLI guard tests prove the extended runner refuses unauthorised/remote execution and redacts connection details. 426/426 local onboarding/runtime tests passed; diff check passed. No local PostgreSQL/Docker is available, so the actual continuity checks run in persistence CI.

The new CI step independently repeats the real dump/restore and runs 13 PostgreSQL assertions: lagging watermark blocks positive control; old grant blocked; reconciled positive control reads; tombstone defeats active grant; replay defeated; epoch mismatch; ahead revision; missing-ledger digest mismatch; deleted tombstone cannot revive; repaired-ledger positive control; missing watermark; reader cannot edit authority; paused task preserved. It must pass with all three required CI checks before merge. This is real PostgreSQL execution using synthetic data, not live production revocation evidence.

Next: layer 39, exact release/rollback.
