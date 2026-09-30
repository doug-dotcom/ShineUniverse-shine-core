# Foundation Layer 81 — Bounded overdue verification executor

**Status:** LIVE — CI green and production verification complete  
**Scope:** execute the single bounded action Layer 80 may admit: independent verification of one overdue Layer-76 receipt

Layer 80 can decide that an overdue successful execution is missing only its independent Layer-77 proof.

Layer 81 is the narrow execution boundary for that case.

> **One target receipt. One governed decision. One existing Layer-77 verifier. Nothing else.**

## Executor

`foundation.execute_case_audit_overdue_verification_v1(...)`

Inputs:

- target Layer-76 execution-event ID;
- environment;
- requested time;
- verification grace period.

Before invoking anything, Layer 81 requires:

1. the target receipt exists in the requested environment;
2. the Layer-76 receipt is `executed`;
3. the target is older than the explicit verification grace window;
4. no Layer-77 verification proof already exists for that receipt;
5. Layer 79 is currently WATCHING or CRITICAL;
6. Layer 80 currently admits `run-independent-verification`;
7. Layer 80 requires `layer-77-bounded-verifier`;
8. Layer 80 classifies the cause as `verification-omission`;
9. every no-authority/no-mutation flag remains false.

If any check fails, Layer 81 records a denied execution and does not call Layer 77.

## Only executable target

The only function Layer 81 may invoke is:

`foundation.run_case_audit_safe_response_verification_v1(...)`

It cannot dynamically select a function or SQL statement.

There is no arbitrary-SQL execution path.

## Closing the bypass

Layer 81 revokes direct `service_role` EXECUTE on the Layer-77 verifier.

That means the prior writer still exists as the trusted bounded verification primitive, but the service role can no longer call it directly.

The new route is:

**Layer 80 policy → Layer 81 eligibility binding → Layer 77 verifier**

Because Layer 81 is `SECURITY DEFINER`, its owner may call the underlying Layer-77 primitive after all Layer-81 checks pass.

## Target binding

Layer 81 binds the policy to the exact target receipt:

- execution event ID;
- source Layer-74 incident event ID;
- Layer-76 action key;
- Layer-76 policy fingerprint;
- original execution timestamp;
- verification grace threshold;
- current verification absence;
- current Layer-79 incident evidence;
- current Layer-80 policy decision.

The policy fingerprint deliberately excludes ever-increasing target age so identical policy truth stays semantically stable across clock ticks.

## Execution ledger

`foundation.case_audit_verify_exec_events`

Every attempted governed execution records:

- target execution;
- Layer-79 incident event;
- cause and Layer-80 decision;
- policy fingerprint;
- target snapshot;
- before coverage;
- result or failure;
- after coverage when executed;
- requested timestamp.

Events are:

- `executed`
- `denied`
- `failed`

The ledger is append-only.

Only one successful Layer-81 execution may exist per target receipt.

Replay of a successfully executed target returns the original Layer-81 receipt rather than invoking Layer 77 again.

## What Layer 81 can change

A successful call can create exactly the durable output already owned by Layer 77:

- one immutable verification proof for the target Layer-76 receipt.

That proof may truthfully conclude:

- `verified`
- `missing`
- `mismatch`

Layer 81 does not reinterpret or improve that conclusion.

## What Layer 81 cannot change

It cannot:

- rerun Layer 76;
- regenerate the Layer-73 observation;
- regenerate the Layer-67 handoff;
- repair or manufacture durable evidence;
- rewrite/delete a Layer-77 proof;
- change Layer-79 incident history;
- mutate release truth;
- grant approval;
- grant new execution authority;
- execute arbitrary SQL.

## Authority boundary

Only `service_role` may call the executor.

The service role cannot:

- call Layer 77 directly;
- insert Layer-81 ledger rows directly.

Foundation runtime may read the Layer-81 summary.

Foundation Gateway receives no direct summary grant and can read only through its established `foundation_runtime` membership.

Shine Core, Shine Defence and browser roles cannot execute or read the Layer-81 control directly.

## Acceptance coverage

CI uses real Layer-76 and Layer-73 rows and proves:

- an overdue successful unverified target is admitted and receives a real Layer-77 proof;
- a successful target still inside grace is denied;
- an unsuccessful Layer-76 target is denied;
- a missing target is not applicable;
- successful replay returns the original Layer-81 receipt;
- Layer-76 receipt count does not change;
- durable Layer-73 evidence count does not change;
- direct service-role Layer-77 execution is revoked;
- service-role direct Layer-81 ledger INSERT is denied;
- executor history is append-only;
- read/execute role boundaries remain intact.

## Production proof

Layer 81 is deployed in the Shine Foundation Supabase project as migration:

`20260930125254 — foundation_layer_081_bounded_overdue_verification_executor`

Live production verification confirms:

- executor ledger, executor and summary functions exist;
- `service_role` can call Layer 81;
- direct `service_role` EXECUTE on the Layer-77 verifier is **revoked**;
- Foundation runtime, Gateway, Shine Core and Shine Defence cannot execute Layer 81;
- service role cannot directly INSERT Layer-81 executor events;
- Foundation runtime can read the summary;
- Gateway reads the summary only through existing `foundation_runtime` membership;
- a nonexistent target returns `not-applicable / target-not-found`;
- that nonexistent-target check creates no Layer-81 event and no Layer-77 proof;
- production currently has zero Layer-81 execution events;
- the live summary reports `directLayer77ServiceRoleBypassAllowed=false`;
- Supabase security advisors report no Layer-81-specific finding.

## Invariant


> Layer 81 may complete missing verification. It may never manufacture the evidence being verified.
