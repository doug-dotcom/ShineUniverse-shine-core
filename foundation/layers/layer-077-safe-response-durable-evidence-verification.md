# Foundation Layer 77 — Safe-response durable evidence verification

**Status:** LIVE — CI green and production verification complete  
**Scope:** independently prove that a successful Layer-76 receipt is backed by the durable evidence it claims to have created

Layer 76 records that a bounded safe target returned successfully.

Layer 77 refuses to treat that receipt as self-proving.

It re-reads the durable target ledger directly and asks:

> **Does the claimed evidence actually exist, and does it match the receipt?**

## Independent evaluator

Reader:

`foundation.evaluate_case_audit_safe_response_execution_v1(...)`

It accepts only a Layer-76 execution-event ID.

It never calls the Layer-73 recorder or Layer-67 handoff generator.

It therefore cannot recreate missing evidence while trying to verify it.

## Observation proof

For:

`record-fresh-promotion-case-audit-observation`

Layer 77 resolves the claimed `observationId` directly in:

`foundation.foundation_promoted_release_case_audit_observations`

Verification requires:

- the durable row exists in the same environment;
- the action-result contract is correct;
- the result status is a Layer-73 record status;
- the result semantic fingerprint exactly matches the stored observation fingerprint;
- the semantic fingerprint is recomputed from the stored observation snapshot and must match the stored fingerprint.

## Handoff proof

For:

`materialise-current-owner-handoff`

Layer 77 resolves the claimed `handoffId` directly in:

`foundation.foundation_promoted_release_owner_handoffs`

Verification requires:

- the durable row exists in the same environment;
- incident ID, owner route and response-plan fingerprint match;
- the receipt's `handoffSha256` matches the durable row;
- SHA-256 is recomputed from the stored handoff document and matches the stored hash.

The stored hash is therefore not trusted merely because both tables repeat it.

## Verdicts

- **verified** — durable evidence exists and all action-specific bindings match;
- **missing** — the receipt names a valid evidence ID that is absent from the durable ledger;
- **mismatch** — durable evidence exists but does not match the execution receipt, or the receipt's evidence identity is malformed.

Denied and failed Layer-76 attempts are not eligible because they claim no successful target execution.

## Immutable verification proof

Ledger:

`foundation.case_audit_safe_response_verifications`

Each proof binds:

- exact Layer-76 execution event;
- Layer-74 incident event;
- action and policy fingerprint;
- original action result;
- durable evidence ID/fingerprint;
- independent comparison checks;
- durable evidence snapshot;
- verification state/reason;
- verification timestamp;
- SHA-256 of the complete verification proof.

Only one proof may exist per execution receipt.

Replay returns that first proof.

## Authority boundary

Runner:

`foundation.run_case_audit_safe_response_verification_v1(...)`

Only `service_role` may invoke it.

The service role cannot directly insert verification rows.

Foundation runtime may read the independent evaluator and verification summary, but cannot run the proof writer.

Gateway, Shine Core, Shine Defence and browser roles cannot run verification.

## Layer 81 access closure

Layer 77 originally granted `service_role` direct access to the proof writer, as recorded in the Layer-77 production proof below.

Layer 81 later closes that direct path.

Current stack behaviour after Layer 81:

- `service_role` cannot call `foundation.run_case_audit_safe_response_verification_v1(...)` directly;
- the only service-role verification entrypoint is `foundation.execute_case_audit_overdue_verification_v1(...)`;
- Layer 81 enforces Layer-79 incident state, Layer-80 admission, exact target identity, verification grace and proof absence before invoking Layer 77;
- Layer 77 itself remains the immutable proof writer and replay authority.

This preserves the historical Layer-77 deployment facts while tightening the current authority boundary.

## Deliberate non-actions


Layer 77 does not:

- rerun Layer 73;
- rerun Layer 67;
- repair missing evidence;
- alter a Layer-76 execution receipt;
- rewrite incident history;
- mutate release truth;
- close an incident;
- grant approval;
- grant execution authority.

A bad receipt remains visibly bad.

## Acceptance coverage

CI proves:

- a real Layer-73 row verifies its observation receipt;
- a missing observation is recorded as `missing`;
- a fingerprint disagreement is recorded as `mismatch`;
- a real Layer-67 handoff verifies only when receipt fields and recomputed document SHA-256 agree;
- a handoff hash disagreement is preserved as `mismatch`;
- denied Layer-76 attempts are not eligible;
- verification never creates new observation or handoff rows;
- replay preserves the first verification;
- summary counts verified/missing/mismatch truthfully;
- service role cannot directly insert verification history;
- runtime/Gateway/owner/Defence cannot run verification;
- verification history is append-only.

## Production proof

Layer 77 is deployed in the Shine Foundation Supabase project as migration:

`20260930114924 — foundation_layer_077_case_audit_safe_response_verification`

Live verification confirms:

- verification ledger and all three Layer-77 functions exist;
- service role can run the bounded verifier;
- Foundation runtime can independently evaluate/read but cannot write verification proofs;
- Gateway, Shine Core and Shine Defence cannot run verification;
- service role cannot directly insert verification rows;
- a nonexistent execution ID returns `not-found / not-applicable` without mutation;
- production currently contains no Layer-76 successful execution receipts, so the Layer-77 summary is truthfully empty: 0 verified, 0 missing, 0 mismatch;
- Supabase security advisors report no Layer-77-specific finding.

## Invariant

> An execution receipt may claim success. Only durable evidence makes that success independently believable.
