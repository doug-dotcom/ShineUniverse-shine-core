# Foundation audit and revocation operations

Run `node foundation/operations/audit-revocation-report-v1.mjs` from a protected operator host with existing libpq PG* connection settings. The command executes one repeatable-read, read-only transaction. No token belongs in command arguments, reports or source. It needs existing SELECT/EXECUTE permissions; it does not provision or broaden them.

Alternatively export the single JSON snapshot from `audit-revocation-snapshot-v1.sql` through an authorised database connection, then run the command with `--snapshot FILE`. Evidence expires after ten minutes. Exit 0 means a passing operational report, 2 means review required, and 1 means collection failed. None of these grants permission or certifies app acceptance.

## Response workflow

1. Match current events to both deployed runtime version and artifact SHA-256. No events, an unidentified release or old evidence is unknown. A policy/outcome pair is complete only when its predecessor hash matches. Orphan outcomes fail chain integrity.
2. Inspect every stale open trace using `foundation.get_gateway_operation_audit_trace_v1(uuid)`. Correlate the original domain request and retained execution evidence. If its outcome cannot independently be recovered, preserve it as unresolved. Do not replay the domain action or fabricate a successful outcome. Current v94 retries an identical outcome append once without repeating the business action.
3. Broken chains require integrity investigation. Historical incidents stay visible even when current-release traces pass. The global readiness function and its warning remain unchanged by this report.
4. For each pending revocation, the affected consumer retrieves its own scoped feed, invalidates cached authority and acknowledges its delivered sequence using the existing authenticated feed/ack endpoints. The operator must not impersonate the consumer or advance a checkpoint. Recollect the report to verify backlog reduction and test a protected request is refused after withdrawal.
5. An empty backlog proves only delivery accounting, not end-to-end enforcement. Use the existing permission, in-flight revocation, expiry, outage and audience tests plus a separately authorised live consumer journey. Never restore a grant to make a test pass.

## Acceptance and remaining scope

This completes the shared-platform operator tooling for audit discovery, current-release attribution, preserved historical incidents, revocation backlog triage and repeatable verification. Consumer wiring, personal-data consent, hosted recovery and user acceptance remain separate work. The dashboard's feature-area estimate may credit implemented tooling; verified product completion stays unverified until its agreed acceptance checklist is satisfied.

Verification includes JavaScript regressions, actual PostgreSQL query scenarios in a disposable CI database, the existing isolated restore/revocation persistence suites and read-only production collection. The fixture harness refuses non-local hosts, requires CI plus an explicit synthetic flag and the exact disposable database name. Fixture mutations never run on production.
