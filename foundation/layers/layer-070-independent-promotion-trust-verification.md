# Foundation Layer 70 — Independent promotion-trust verification

**Status:** LIVE — CI green, independent verifier deployed and healthy production recovery independently confirmed  
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

Full Foundation CI run `36686775843` completed successfully with both Foundation jobs green and persistence `197/197` complete. Layer 70 apply/tests passed and all downstream Shine Defence checks remained green.

The original Layer-70 build was interrupted before its branch update completed. Its exact commit survived as an orphan, was transplanted onto the newer shared main without force-pushing, and the full suite was then rerun successfully.

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

## Production proof

Layer 70 is deployed in the Shine Foundation Supabase project.

The migration already existed when this room attempted promotion, recorded as:

`foundation_layer_070_independent_promotion_trust_verification`

at version timestamp `20260930075252`. Rather than retrying DDL against an existing table, the live schema/functions were verified directly against the tested contract.

Current independent production evaluation:

- verification state: **recovered**
- reason: `independent-promotion-recovery-confirmed`
- canonical recovery observed: **true**
- canonical source truth PASS: **true**
- promotion closure CLOSED/current/integrity verified: **true**
- promoted release available: **true**
- live observation NORMAL/fresh/matching: **true**
- promotion-trust incident lifecycle NORMAL: **true**
- active incidents: **0**
- watches: **0**
- owner evidence used as canonical input: **false**
- owner outcome accepted as promotion trust: **false**
- incident closure performed by verifier: **false**
- authoritative truth mutated: **false**

Current promoted release remains:

`foundation:layer-58:1a8148a8`

with promoted-release SHA-256:

`ed4e6f4d7234161a6261fc98d58fd3bfd05ca35045fabfdc57dbf8c5ac51040f`

Production contains **0 Layer-70 verification rows**, because there is currently no real Layer-69 owner evidence packet to consume.

A runner call using a nonexistent evidence-return ID correctly returned:

- status: **not-applicable**
- reason: `promoted-release-owner-evidence-not-found`
- independent verification: **true**
- source evidence used as trigger only: **true**
- owner outcome accepted as promotion trust: **false**
- incident closure performed: **false**
- authoritative truth mutation: **false**

Privilege proof:

- Foundation runtime may read/evaluate independent recovery: **yes**
- service role may evaluate and run verification: **yes**
- Shine Core owner may run verification: **no**
- Foundation runtime may run verification: **no**
- Gateway may run verification: **no**
- Shine Defence may run verification: **no**
- service role direct proof-ledger INSERT: **no**
- Shine Core direct proof-ledger SELECT: **no**
- anonymous/authenticated evaluator access: **no**

Supabase advisors:

- no Layer-70-specific security finding;
- no Layer-70 unindexed foreign-key finding;
- the three Layer-70 proof-ledger indexes currently appear as `unused_index` INFO because production has zero verification rows;
- the remaining unindexed foreign-key INFO belongs to concurrent GitHub-OIDC replay-alert work, not Layer 70.

## Invariant

> Owner evidence may trigger a fresh measurement. It never supplies the answer to that measurement.
