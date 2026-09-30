# Foundation Layer 61 — Consumer-safe promoted release projection

**Status:** LIVE — consumer boundary green in CI and promoted release verified in production  
**Scope:** stop downstream components from treating a raw immutable binding as a promotion-complete release

Layer 60 gives Foundation an immutable answer to:

> Has this exact binding reached canonical source-truth closure?

Layer 61 gives downstream code one answer to:

> Which Foundation release, if any, is safe to consume as promotion-complete?

## One downstream surface

Reader:

`foundation.get_foundation_promoted_release_v1(...)`

Assertion:

`foundation.assert_foundation_promoted_release_v1(...)`

A promoted release is available only when the current Layer-60 state is all of:

- `closed`;
- `releaseClosed: true`;
- `integrityVerified: true`;
- `receiptCurrent: true`.

Anything else returns:

- `available: false`;
- `state: hold`;
- no promoted-release payload.

## Promoted release projection

When available, consumers receive the exact:

- immutable binding ID;
- release ref;
- Foundation layer;
- Git source ref;
- Git source commit SHA;
- runtime version;
- artifact SHA-256;
- Layer-60 closure ID;
- Layer-60 closure SHA-256;
- Layer-59 canonical source-truth fingerprint;
- closure timestamp.

The complete projection receives its own deterministic SHA-256.

## Consumer roles

Internal read/assert access is granted to:

- `foundation_runtime`;
- `shine_defence_runtime`;
- `service_role`.

Browser-facing roles remain denied.

Assertions are read-only. They do not create bindings, repair projections, close promotions or modify readiness.

## Raw-binding CI boundary

Layer 61 adds:

`foundation/integration-kit/verify-promoted-release-consumer-boundary-v1.mjs`

Core CI scans production SQL/JS/TS for direct consumption of:

`current_foundation_release_identity`

New production consumers fail CI unless they are one of the explicitly reviewed control-plane internals that must reason about pre-closure transition state.

Current allowlist:

- immutable binding implementation;
- readiness drift attribution;
- scoped remediation executor;
- release projection reconciliation.

Tests are excluded because they must exercise lower-level controls directly.

This means a future downstream component cannot quietly bypass Layer 60 by reading the raw current binding.

## Runtime health remains separate

The promoted-release projection explicitly carries:

- `runtimeReadinessClaimed: false`;
- `mutatesAuthoritativeTruth: false`.

Source-truth promotion completion and live runtime readiness remain independent facts.

## Acceptance coverage

The first Layer-61 CI run exposed a test-only PostgreSQL/JSON mistake: the stale-path assertion treated JSON `null` as SQL `NULL`. The implementation itself applied successfully and returned the expected fail-closed payload.

The test was corrected without changing production logic.

Corrected full Foundation CI run `36664259812` completed successfully. The raw-binding bypass verifier, Layer-61 apply/tests and the downstream persistence chain all passed.

CI proves:

- a closed current Layer-60 receipt produces one promoted-release projection;
- source commit is derived from the exact binding source ref;
- the consumer projection SHA-256 is deterministic;
- Foundation runtime can assert the promoted release;
- Shine Defence runtime can assert the promoted release;
- a stale closure produces no promoted-release payload;
- runtime and Defence assertions fail closed on stale closure;
- browser roles cannot consume the internal projection;
- CI rejects new raw-binding production consumers outside the control-plane allowlist.

## Production proof

Layer 61 is deployed in the Shine Foundation Supabase project.

Current production projection:

- state: **promoted**
- available: **true**
- release: `foundation:layer-58:1a8148a8`
- binding ID: `187d5232-83b5-4c2f-acc6-62da7a9a9515`
- source commit: `1a8148a8eb748a19ac03107d9e9ec7313297384b`
- runtime: `90`
- closure ID: `df864db1-abe4-4a28-b784-7a1d7b83dc5d`
- canonical source-truth fingerprint: `3e7ce8f50385b3fadddddc247d3573bf`
- promoted-release SHA-256: `ed4e6f4d7234161a6261fc98d58fd3bfd05ca35045fabfdc57dbf8c5ac51040f`
- runtime readiness claimed: **false**
- authoritative truth mutation: **false**

Production privilege proof:

- anonymous read: **no**
- authenticated read: **no**
- Foundation runtime read: **yes**
- Foundation runtime assert: **yes**
- Shine Defence runtime read: **yes**
- Shine Defence runtime assert: **yes**

The Supabase control-plane SQL session does not use downstream runtime impersonation as the proof boundary; role ACLs are verified directly and CI executes the assertions under the actual runtime roles.

Security/performance advisor counts are unchanged and contain no Layer-61-specific finding.

## Invariant

> Downstream code consumes promoted releases, not raw bindings. Binding is a transition fact; promotion closure is the consumer trust boundary.
