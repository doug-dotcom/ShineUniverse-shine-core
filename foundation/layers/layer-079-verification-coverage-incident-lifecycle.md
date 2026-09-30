# Foundation Layer 79 — Verification coverage incident lifecycle

**Status:** LIVE — CI green and production verification complete  
**Scope:** turn persistent Layer-78 verification-coverage failures into append-only operational incidents

Layer 78 answers:

> **Have all successful safe-response executions actually been independently verified?**

Layer 79 makes a persistent bad answer operationally visible.

## Source of truth

Layer 79 reads only:

`foundation.get_case_audit_safe_response_verification_coverage_v1(...)`

It does not inspect or repair Layer-76 or Layer-77 directly.

The source states are:

- `idle`
- `normal`
- `pending`
- `gap`
- `invalid`

Only **gap** and **invalid** are incident-capable.

`pending` is deliberately non-incident because Layer 78 has already established that the verification is still within its explicit grace window.

## Incident lifecycle

Ledger:

`foundation.case_audit_verify_incident_events`

Lifecycle:

- **detected** — first GAP/INVALID sample starts a watch;
- **opened** — the same evidence persists past the 300-second threshold;
- **changed** — an open incident receives materially different coverage evidence;
- **recovered** — coverage returns to IDLE, NORMAL or PENDING.

The incident ledger is append-only.

## Semantic fingerprint

`foundation.case_audit_verify_incident_fingerprint_v1(...)`

The fingerprint binds the meaningful Layer-78 coverage truth:

- overall state and reason;
- execution/proof/problem counts;
- verified/pending/unverified/missing/mismatch/invalid counts;
- proof and healthy-verification percentages;
- execution-level coverage state;
- verification identity/state;
- proof-integrity result;
- durable-evidence identity/fingerprint.

Evaluation timestamps and execution-age counters are intentionally excluded so a stable problem does not create a new incident event every time the sentinel runs.

## Sentinel

`foundation.run_case_audit_verify_incident_sentinel_v1(...)`

Only `service_role` may run it.

The sentinel:

1. reads fresh Layer-78 coverage;
2. evaluates the incident transition;
3. returns the coverage and transition result.

It does **not** run Layer 77, recreate evidence, retry Layer 76, or mutate any authoritative release/incident truth outside its own append-only Layer-79 event ledger.

## Hosted monitoring

Production pg_cron job:

`shine-foundation-case-audit-verify-incident-5m`

Cadence:

`2,7,12,17,22,27,32,37,42,47,52,57 * * * *`

That produces two deliberate time boundaries:

- Layer 78 verification grace: 300 seconds;
- Layer 79 incident persistence: another 300 seconds before opening.

A temporarily late verification therefore does not become a production incident immediately.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Foundation Gateway may read the summary only through its existing `foundation_runtime` membership. Layer 79 gives Gateway no direct EXECUTE grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

The transition helper is owner-private, and service role cannot insert incident rows directly.

## Summary

`foundation.get_case_audit_verify_incident_summary_v1(...)`

Reports:

- NORMAL / WATCHING / CRITICAL operational state;
- active incident and watch counts;
- current Layer-78 coverage state/reason;
- execution/proof/problem counts;
- proof coverage and healthy-verification percentages;
- current incident evidence;
- bounded recommended action.

## Deliberate non-actions

Layer 79 grants no authority to:

- run missing Layer-77 verification;
- rerun Layer 76;
- manufacture durable evidence;
- mutate Layer-76 receipts;
- rewrite Layer-77 proofs;
- change release truth;
- close another incident domain;
- grant approval or execution authority.

## Production proof

Layer 79 is deployed in the Shine Foundation Supabase project as:

- `20260930122801 — foundation_layer_079_case_audit_verification_incident_lifecycle`
- `20260930122807 — foundation_layer_079_case_audit_verification_incident_hosted`

Live production verification confirms:

- incident ledger, sentinel and summary exist;
- current operational state: **normal**;
- current Layer-78 coverage state: **idle**;
- active incidents: **0**;
- watches: **0**;
- verification problem count: **0**;
- verification coverage: **100%**;
- healthy verification: **100%**;
- a real `service_role` sentinel execution returned no event and performed no verification, repair or target re-execution;
- service role can run only the sentinel, not the transition helper or direct incident INSERT;
- Foundation runtime can read the summary;
- Gateway can read the summary only through existing `foundation_runtime` membership and cannot run the sentinel;
- Shine Core and Shine Defence cannot read the summary or run the sentinel;
- hosted pg_cron job `shine-foundation-case-audit-verify-incident-5m` is active as job **36** on the documented cadence;
- Supabase security advisors report no Layer-79-specific finding.

## Invariant


> A verification gap may become an incident. An incident never becomes permission to invent the missing proof.
