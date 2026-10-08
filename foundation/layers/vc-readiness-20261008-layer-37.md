# VC readiness layer 37 — isolated database restore

Baseline: ee0554f240ac43af27186948537056d0a004058f (layer 36 merged).
After merge: 37/40 complete; 3 remaining (7.5%).

## Behaviour

verify-veteran-care-isolated-restore-v1.mjs runs an actual PostgreSQL custom-format dump/restore drill in the existing disposable CI PostgreSQL service. It requires explicit GitHub CI authorisation, the CI service container ID and the fixed synthetic loopback postgres connection. It accepts no remote connection string, production archive or caller database name. Generated source/target database and reader role names use a per-run random suffix; both databases start empty and are distinct from the Foundation persistence test database.

The synthetic fixture contains two owners' selected records, an old active permission snapshot, a later revocation ledger entry, a paused task, a stable retry binding and a resumable checkpoint. It has primary/foreign/check constraints, a forced owner-select row-level-security policy and a NOLOGIN/NOSUPERUSER/NOBYPASSRLS reader with only schema usage and selected-table read access. It contains no real clinical data, credentials, storage objects or deployed application schema.

The runner creates the fixture, dumps it using the service's matching PostgreSQL tools, hashes the archive, restores to the other empty database, then compares canonical SHA-256 digests for all six tables, column schema, constraints and policies. It verifies RLS is enabled/forced, the reader has no insert/update/delete/truncate/reference/trigger privileges or permission-table access, each owner sees exactly its own row, and an unrelated owner sees no rows. The paused task remains paused; no restored checkpoint triggers work.

The runner then drops only databases it created, drops its generated role and removes container/local archives. Cleanup failures fail the proof. Generic failure output contains no command credentials or database content. A passed report is printed only after all checks and cleanup succeed. It labels evidence synthetic-postgres-ci, databaseRestoreExecuted true, productionBackupVerified false, productionRestorePerformed false, restoreAuthorityProvided false and revocationContinuityVerified false. The archive digest records integrity of this generated dump; it does not validate an uninspected production backup.

## Ownership and boundaries

Foundation owns this reproducible source drill and CI registration. VC Integrations owns production schema/data backups and a separately authenticated isolated restore of the actual VC schema, including deployed extensions, policies, role grants and integrity evidence. L owns restoring its independent memory database; Security owns identity/credential reissue. This drill exercises generic PostgreSQL schema/data/ACL restoration and synthetic tenant isolation, not hosted Auth, Storage, extensions, a Supabase project restore or cross-room recovery.

The reader role is provisioned separately in the same disposable service before restoring table grants. Roles are cluster-level and this drill does not prove global role backup/restore. The synthetic schema is deliberately separate from existing Foundation SQL. No production database, live authority policy, deployed adapter or remote vault is accessed or changed. Real backup coverage remains uninspected as recorded in layer 36.

Revocation rows are included in data parity, but their precedence over a restored old grant is not yet proved; layer 38 owns that behaviour. A database restore never supplies fresh session, user, consent, task, recipient or deployment authority. No recovery completion or production readiness is certified here.

## Evidence

5 local guard tests cover the explicit CI boundary, missing/altered/remote connection settings, generated database cleanup names, unauthorised CLI refusal and redaction of rejected production connection details. 424/424 local onboarding/runtime tests passed; diff check passed. The local workspace has no PostgreSQL client/server or Docker, so no actual local database restore was run.

The persistence CI job now runs the actual isolated drill before its existing Foundation schema/bootstrap suites. It must pass, along with Foundation contracts and independent Defence registry checks, before merge. Successful persistence CI is the evidence for this real synthetic database restore; it remains distinct from a production/live backup restore. The printed report includes archive/schema/constraint/table hashes and explicit evidence limits.

Next: layer 38, restored revocation continuity.
