# Foundation Layer 61 — Consumer-safe promoted release projection

**Status:** IMPLEMENTED — CI and production verification pending  
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

## Invariant

> Downstream code consumes promoted releases, not raw bindings. Binding is a transition fact; promotion closure is the consumer trust boundary.
