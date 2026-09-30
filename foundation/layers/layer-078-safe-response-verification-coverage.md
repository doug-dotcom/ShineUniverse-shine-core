# Foundation Layer 78 — Safe-response verification coverage audit

**Status:** LIVE — CI green and production verification complete  
**Scope:** make Layer-77 verification coverage measurable across every successful Layer-76 execution

Layer 77 can independently verify one execution receipt.

Layer 78 asks the estate-level question:

> **Have all successful safe-response executions actually been independently verified?**

## Coverage reader

`foundation.get_case_audit_safe_response_verification_coverage_v1(...)`

Inputs:

- environment;
- evaluation time;
- explicit verification grace period;
- visible-item limit.

It reads only:

- Layer-76 execution receipts;
- Layer-77 verification proofs.

It executes no target and writes nothing.

## What requires verification

Only Layer-76 receipts with:

`event_type = executed`

enter the coverage denominator.

Denied and failed attempts are historical execution truth, but they do not claim that a target produced durable evidence and therefore do not require Layer-77 verification.

## Per-execution states

- **verified** — a structurally valid Layer-77 proof says durable evidence verified;
- **pending** — no proof yet, but the execution is still inside the explicit grace window;
- **unverified** — no proof and the grace window has expired;
- **missing** — Layer 77 proved the claimed durable evidence is absent;
- **mismatch** — Layer 77 proved the durable evidence and receipt disagree;
- **invalid** — the Layer-77 verification proof itself fails integrity/binding checks.

## Proof integrity is independently recomputed

Layer 78 does not trust the Layer-77 row just because it exists.

For every proof it recomputes SHA-256 from the immutable proof document and requires the proof document to agree with the verification columns and original Layer-76 receipt:

- execution event;
- environment;
- incident event;
- action;
- policy fingerprint;
- verification state/reason;
- durable evidence identity/fingerprint;
- original execution action result;
- independent-read flag;
- no-target-reexecution flag;
- no history/release/incident mutation flags;
- no approval or execution-authority flags;
- no-mutation flag.

Malformed flag types are treated as an **invalid proof**, not as an evaluator error.

## Overall states

- **idle** — no successful Layer-76 executions exist;
- **normal** — every successful execution is verified;
- **pending** — all uncovered executions are still inside the grace period;
- **gap** — at least one receipt is overdue, missing, or mismatched;
- **invalid** — at least one verification proof is structurally invalid.

`invalid` dominates `gap`, because a corrupted proof cannot safely be interpreted as a normal evidence failure.

## Metrics

The response reports:

- successful execution count;
- required verification count;
- proof count;
- verified count;
- pending count;
- overdue-unverified count;
- missing-evidence count;
- mismatch count;
- invalid-proof count;
- problem count;
- proof coverage percentage;
- healthy-verification percentage.

Coverage and health are deliberately separate. A system can have 100% proof coverage while some proofs truthfully say **missing** or **mismatch**.

## Authority boundary

Declared reader access:

- Foundation runtime;
- service role.

Foundation Gateway is already a member of `foundation_runtime`, so it can read this internal audit only through that established inheritance. Layer 78 grants Gateway no direct EXECUTE privilege.

Denied:

- Shine Core owner;
- Shine Defence runtime;
- browser roles.

Layer 78 has no writer, executor or repair path.

## Production proof

Layer 78 is deployed in the Shine Foundation Supabase project as migration:

`20260930120521 — foundation_layer_078_case_audit_safe_response_verification_coverage`

Live production verification confirms:

- the coverage reader exists and executes successfully;
- current production state is **idle** because there are no successful Layer-76 execution receipts yet;
- execution count: **0**;
- verification-required count: **0**;
- verification proof count: **0**;
- problem count: **0**;
- verification coverage: **100%**;
- healthy verification: **100%**;
- proof integrity is recomputed: **true**;
- target re-execution: **false**;
- mutation performed: **false**;
- Foundation runtime and service role can read;
- Gateway can read only via its established `foundation_runtime` membership;
- Gateway has no direct EXECUTE grant;
- Shine Core, Shine Defence and browser roles cannot read;
- Supabase security advisors report no Layer-78-specific finding.

## Invariant


> Verification is not complete because a verifier exists. It is complete only when every successful execution has a valid independent proof.
