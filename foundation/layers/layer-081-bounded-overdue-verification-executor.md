# Foundation Layer 81 — Bounded overdue-verification executor

**Status:** LIVE — CI green and production verification complete  
**Scope:** execute exactly one Layer-80-admitted independent verification without opening any broader repair or re-execution path

Layer 80 can say:

> **This overdue successful execution may now be independently verified through the Layer-77 bounded verifier.**

Layer 81 is the narrow execution doorway for that decision.

## One target per call

Executor:

`foundation.execute_case_audit_overdue_verification_v1(...)`

The caller must supply one exact Layer-76 execution-event ID.

Layer 81 does not:

- scan for work;
- select a target automatically;
- loop over overdue receipts;
- retry Layer 76;
- manufacture evidence.

This keeps execution explicit and auditable.

## Admission requirements

All of the following must be true at execution time:

1. the target is a real Layer-76 receipt in the requested environment;
2. its Layer-76 event type is `executed`;
3. its age is greater than the explicit verification grace period;
4. it still has no Layer-77 verification proof;
5. Layer 79 is currently WATCHING or CRITICAL;
6. the current Layer-79 incident has a durable event ID;
7. Layer 80 admits `run-independent-verification`;
8. Layer 80 classifies the cause as `verification-omission`;
9. required control is exactly `layer-77-bounded-verifier`;
10. every no-authority/no-repair/no-rewrite flag remains false.

If any requirement fails, Layer 81 records a denied attempt rather than expanding authority.

## Concurrency and replay

Calls for the same Layer-76 target acquire a transaction-scoped advisory lock.

That makes admission and execution serial for one target.

The executor ledger permits at most one **executed** Layer-81 event per target.

Once an execution succeeds, replay returns that original event and its Layer-77 result.

## What it executes

Layer 81 calls exactly:

`foundation.run_case_audit_safe_response_verification_v1(...)`

and accepts only Layer-77 outcomes:

- `verified`;
- `missing`;
- `mismatch`.

A negative verification outcome is still a successful Layer-81 execution because the verifier ran and recorded truthful immutable evidence.

Layer 81 never interprets **missing** or **mismatch** as permission to repair anything.

## Bypass closure

Before Layer 81, `service_role` could call the Layer-77 verifier directly.

Layer 81 revokes that direct EXECUTE privilege.

After Layer 81:

- service role can call the Layer-81 executor;
- service role cannot call Layer 77 directly;
- the SECURITY DEFINER Layer-81 executor can invoke Layer 77 as its owner only after all admission checks pass.

This makes the Layer-80 policy an enforced gate rather than advisory documentation.

## Executor ledger

`foundation.case_audit_verify_exec_events`

Each event binds:

- exact Layer-76 target;
- current Layer-79 incident event where applicable;
- Layer-80 decision/cause;
- stable policy fingerprint;
- target eligibility snapshot;
- before coverage;
- Layer-77 action result for executed events;
- after coverage;
- denial or failure reason;
- request timestamp.

The ledger is append-only.

A partial unique index guarantees at most one executed event per target.

## Stable policy fingerprint

`foundation.case_audit_verify_exec_policy_fp_v1(...)`

The fingerprint binds:

- target identity and original request time;
- target Layer-76 action/policy;
- verification grace threshold;
- target verification state at admission;
- Layer-79 incident identity/evidence;
- Layer-80 decision/cause/control and all authority flags.

It deliberately excludes the target's ever-increasing age counter so the same policy does not become a different policy every second.

## Read boundary

Executor:

- service role only.

Summary:

`foundation.get_case_audit_verify_exec_summary_v1(...)`

Declared readers:

- Foundation runtime;
- service role.

Gateway may read the summary only through existing `foundation_runtime` membership; no direct grant is added.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

Service role cannot insert executor-ledger rows directly.

## Deliberate non-actions

Layer 81 does not:

- rerun Layer 76;
- create or alter Layer-73 durable target evidence;
- rewrite or delete a Layer-77 proof;
- mutate release truth;
- mutate Layer-79 incident history;
- auto-select or batch targets;
- grant broader execution authority.

## Production proof

Layer 81 is deployed in the Shine Foundation Supabase project as migration:

`20260930125254 — foundation_layer_081_bounded_overdue_verification_executor`

Live production verification confirms:

- executor ledger, executor and summary functions exist;
- `service_role` can execute Layer 81;
- `service_role` **cannot** execute the Layer-77 proof writer directly;
- Foundation runtime, Gateway, Shine Core and Shine Defence cannot execute Layer 81;
- service role cannot insert executor-ledger rows directly;
- a real service-role call for a nonexistent target returns `not-applicable` / `target-not-found` without creating a ledger event;
- current production executor ledger count: **0**;
- current summary: **0 executed / 0 denied / 0 failed**;
- summary explicitly reports direct Layer-77 service-role bypass as **false**;
- Foundation runtime can read the summary;
- Gateway can read only through existing `foundation_runtime` membership and receives no direct summary grant;
- Shine Core and Shine Defence cannot read the summary;
- no Layer-81-specific Supabase security advisor finding is present.

CI proof:

- full Foundation persistence/Defence chain: **445 steps green**;
- contract job: green;
- separate Defence workflow: green;
- real-chain Layer-81 test proved an overdue successful Layer-76 receipt can create exactly one Layer-77 verification proof through Layer 81 after direct Layer-77 service-role access is revoked;
- replay returns the first Layer-81 execution;
- within-grace and unsuccessful Layer-76 targets are denied;
- Layer-76 execution count and durable target-evidence count remain unchanged.

## Invariant


> One admitted omission may trigger one bounded verification. Nothing else comes along for the ride.
