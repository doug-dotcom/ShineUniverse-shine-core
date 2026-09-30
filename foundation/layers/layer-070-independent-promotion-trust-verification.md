# Foundation Layer 70 — Independent promotion-trust verification

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** use owner evidence only as a trigger for a fresh Foundation-owned recovery verdict

Layer 69 lets Shine Core explain what it observed.

Layer 70 answers a different question:

**What does Foundation independently observe now?**

## Independent evaluator

Reader:

`foundation.evaluate_foundation_promoted_release_independent_recovery_v1(...)`

It reads five canonical dimensions directly:

1. canonical source truth;
2. promotion closure;
3. promoted-release availability;
4. live promotion observation freshness/match;
5. promotion-trust incident lifecycle.

Owner outcome, owner facts, owner evidence references and owner recommendations are not inputs.

## Verdicts

- **recovered** — all five independent dimensions are simultaneously healthy;
- **impaired** — current canonical evidence explicitly shows a negative state;
- **indeterminate** — required live evidence is missing, stale or unknown.

Recovered is intentionally strict.

It requires:

- canonical source truth PASS;
- closure CLOSED, integrity verified and current;
- promoted release available;
- live observation NORMAL, fresh and matching;
- incident lifecycle NORMAL with zero active incidents and zero watches.

## Evidence-triggered runner

Runner:

`foundation.run_promoted_release_owner_evidence_verification_v1(...)`

Only `service_role` may execute it.

A Layer-69 packet is eligible only when it is:

- current;
- integrity verified;
- still bound to current accepted owner work;
- fresh;
- not already independently verified.

The source packet is used only as the admission trigger.

## Owner disagreement is allowed

Layer 70 records whether the owner claim:

- agrees;
- disagrees;
- is inconclusive

against the independent verdict.

Example:

> owner reports **resolved**, but canonical truth still shows HOLD

is recorded as:

- verification: **impaired**
- owner claim alignment: **disagrees**

The owner never wins by assertion.

## Immutable proof

Ledger:

`foundation.foundation_promoted_release_owner_evidence_verifications`

Each proof binds:

- exact Layer-69 evidence return;
- handoff, acknowledgement and incident IDs;
- owner-reported outcome;
- source evidence SHA-256;
- canonical source-truth state/fingerprint;
- closure state;
- promoted-release state/availability/fingerprint;
- live trust state;
- incident state;
- independent verdict;
- owner-claim alignment;
- immutable proof SHA-256.

Replay returns the original proof.

## Historical truth stays historical

If Foundation later recovers, an earlier **impaired** verification does not rewrite itself to recovered.

Its proof remains immutable.

Its source owner evidence may become stale for current use, while the recorded independent verdict remains the truthful result from when verification ran.

## Authority boundary

Layer 70:

- does not close incidents;
- does not mutate source truth;
- does not mint promotion closure;
- does not rebind releases;
- does not change promotion trust;
- grants no approval;
- grants no execution authority.

Incident recovery remains governed by fresh Layer-64/65 canonical evidence.

## Acceptance coverage

CI proves:

- owner can report resolved while independent truth remains impaired;
- the verifier records that disagreement rather than accepting the owner claim;
- owner data is trigger-only;
- replay preserves the first independent proof;
- later canonical recovery is visible through the evaluator;
- earlier verification remains immutable history;
- later recovery makes old source evidence stale without invalidating the proof;
- only service role may run verification;
- service role cannot directly insert proof rows;
- owner/runtime/Gateway/Defence cannot run verification;
- browser roles cannot call the independent evaluator;
- verification history is append-only.

## Invariant

> Owner evidence may trigger a fresh measurement. It never supplies the answer to that measurement.
