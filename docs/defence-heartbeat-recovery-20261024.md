# Bounded authority heartbeat recovery

24 October 2026: deployed logs traced release-head 401s to stale authority-sync
heartbeats. Recorded successful signed refreshes were separated by roughly five
hours despite a twice-hourly cron. The 5,400-second authorisation limit correctly
refused the expired receipts. Refreshing authority restored release-head and
rollback-source attestation; executor readiness could again record its actual
credentialReady=false state.

This candidate adds an event-driven fallback within GitHub. Completion of four
allowlisted Core control workflows can request the existing signed authority
publisher on main after 30 minutes without a recent successful run. It validates
repository IDs, source branch/event/path, run attempt, current main and event age,
re-fetches the source run from GitHub, and suppresses a fresh in-flight publisher.
The workflow has a serial concurrency group, a two-minute timeout, and actions
write only in its dispatch job. Checkout uses the watcher default-branch SHA with
credential persistence disabled. No source-run artifacts, logs or code are used.

The publisher remains the sole authority writer. Its existing OIDC verification,
lineage validation and database receipt rules remain unchanged. This helper has
no OIDC permission or hosted-service credentials. A dispatch acceptance means
only refresh-requested, not a refreshed live heartbeat. It never retries product
releases, deploys, changes TTLs or grants, or executes rollback.

## Acceptance boundary

Synthetic tests prove selection, cooldown, duplicate suppression and rejection
boundaries. CI must pass the exact candidate head before integration. Since
workflow_run requires the watcher on the default branch, draft-branch CI cannot
prove the live fallback. After authorised integration, inspect one genuine
control completion, refresh dispatch, signed publisher success and new database
receipt; verify suppressed duplicate events too. Keep the draft unmerged until
the integration owner selects it.

This mitigates recurring expiry after other Core activity resumes; it cannot
guarantee continuous freshness during a GitHub-wide outage or complete inactivity.
A scheduler outside GitHub, scoped only to dispatch this signed publisher, remains
the option for that stronger availability requirement. Do not extend the 90-minute
limit to conceal scheduler failures.
