# Foundation Layer 47 — Readiness dependency-remediation proposals

**Status:** LIVE

Layer 47 turns an active Layer-44 readiness incident into a bounded, integrity-bound remediation proposal without granting approval or execution authority.

## Preconditions

A proposal can be generated only when:

- the readiness incident is `opened` or `changed`;
- Layer 45 currently admits `propose-dependency-remediation`;
- the proposal binds to the current semantic condition fingerprint.

## Scope

The proposal is tied to:

- one readiness incident event;
- one semantic condition fingerprint;
- current reason codes;
- the exact affected readiness scopes.

Affected scopes are deduplicated.

Disposition precedence is:

`blocked > guarded > degraded`

so a scope appearing in multiple readiness sets is represented by its strongest current disposition.

## Bounded work

Allowed work:

- investigate dependency evidence;
- repair the external dependency or Defence posture;
- collect fresh readiness evidence.

Each scope receives the same bounded workflow:

1. collect fresh scope evidence;
2. identify the degraded upstream dependency;
3. prepare upstream remediation;
4. rerun Foundation readiness verification.

Explicitly prohibited:

- mutate Foundation canonical truth;
- rebind Foundation release identity;
- bypass safe mode;
- automatic unapproved repair.

The proposal records:

- `approvalGranted: false`
- `executionAuthorityGranted: false`

It is planning evidence only.

## Integrity and staleness

Every proposal has a SHA-256 integrity hash.

Status evaluation recomputes that hash.

A proposal is current only while:

- the same readiness incident event remains active;
- the same semantic condition fingerprint remains current;
- the stored proposal integrity hash verifies.

A changed incident, changed condition, or recovered incident makes the proposal stale.

## Idempotency

There is exactly one proposal per:

`readiness incident event + semantic condition fingerprint`

Repeated generation returns the existing proposal rather than creating a new row, even when invoked at a later timestamp.

## Production proof

Live proposal:

`c8d367d6-8831-41f8-a2c3-9479dc3d10d7`

SHA-256:

`6c674244a19f8a19f0f5b073cce34ac9bb7f74ab1897d628e60b81afcb5a18f2`

It is bound to readiness incident:

`2b51c535-1783-4540-b7d6-4b2ae599ec2e`

and semantic condition:

`fbaefb8f8a09d8a919e1b1d15353b387`

It covers six degraded scopes:

- context operations
- control operations
- credential operations
- identity operations
- permission operations
- protected operations

Live status is:

**current**

Integrity verified:

**true**

Repeated generation returned the same proposal ID and proposal hash; production proposal count remained one.

## CI and advisors

Hardened Foundation CI run:

`36424731367`

passed end-to-end.

Layer-47 security advisor findings:

**0**

Layer-47 performance advisor findings:

**0**

## Closure invariant

> An operational incident may produce a precise remediation proposal, but a proposal is not approval and is not execution authority.

If the incident meaning changes, the proposal expires with it.
