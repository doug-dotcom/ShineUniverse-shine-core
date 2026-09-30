# Foundation Layer 82 — Verification execution reconciliation

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** independently prove that a successful Layer-81 execution receipt is backed by the Layer-77 proof and durable evidence it claims

Layer 81 can legitimately say:

> **I invoked the bounded Layer-77 verifier for this exact overdue execution.**

Layer 82 refuses to take that statement on trust.

It independently asks:

> **Does the durable proof exist, does the Layer-81 receipt actually match it, does the proof still match the original evidence, and does current coverage agree?**

## Independent evaluator

`foundation.evaluate_case_audit_verify_exec_outcome_v1(...)`

The evaluator accepts one Layer-81 executor event.

Only Layer-81 `executed` events are eligible.

Denied or failed executor attempts are **not applicable** because they claim no successful Layer-77 invocation.

## Layer-81 envelope integrity

Layer 82 recomputes and validates:

- the Layer-81 policy fingerprint;
- exact Layer-76 target event;
- original Layer-76 incident, action and policy fingerprint;
- original Layer-76 requested time;
- explicit verification grace threshold;
- `verificationAbsent=true` at Layer-81 admission;
- Layer-80 decision = `admit`;
- cause = `verification-omission`;
- required control = `layer-77-bounded-verifier`;
- all no-authority/no-repair/no-rewrite flags.

A forged or semantically inconsistent Layer-81 receipt becomes **receipt-mismatch** even if it happens to name a real Layer-77 proof.

## Layer-77 proof integrity

Layer 82 re-reads:

`foundation.case_audit_safe_response_verifications`

and independently recomputes the Layer-77 proof SHA-256.

It also rebinds the complete proof envelope to the original Layer-76 execution:

- execution identity;
- environment;
- incident;
- action;
- execution policy fingerprint;
- execution timestamp;
- verification state and reason;
- durable evidence identity/fingerprint/snapshot;
- original Layer-76 action result;
- verification timestamp;
- independent-read and no-mutation flags.

## Durable evidence is evaluated again

Layer 82 calls the read-only Layer-77 evaluator:

`foundation.evaluate_case_audit_safe_response_execution_v1(...)`

That re-reads the actual Layer-73 observation or Layer-67 handoff.

The current evaluation must agree with the recorded Layer-77 proof.

This catches a subtle class of failure:

- a verification proof can be structurally self-consistent;
- yet the underlying durable evidence may no longer support its recorded conclusion.

Layer 82 records that as **evidence-drift**.

It never repairs the evidence.

## Layer-78 coverage cross-check

Layer 82 also reads current:

`foundation.get_case_audit_safe_response_verification_coverage_v1(...)`

If the exact target appears in the visible Layer-78 window, its:

- coverage state;
- verification ID;
- verification state;
- proof-integrity result

must agree with Layer 82's independently recomputed result.

A disagreement is **coverage-drift**.

If the target is outside the visible Layer-78 window, reconciliation can still succeed from the durable Layer-76/77 evidence; visibility is reported explicitly rather than treated as a false failure.

## Reconciliation states

- **reconciled** — Layer 81, Layer 77, current durable evidence and visible Layer-78 coverage agree;
- **missing-proof** — Layer 81 claims execution but no Layer-77 proof exists;
- **receipt-mismatch** — Layer-81 policy/target/result envelope disagrees with durable truth;
- **invalid-proof** — the Layer-77 proof fails its own hash/binding integrity;
- **evidence-drift** — the current durable evidence no longer supports the recorded Layer-77 outcome;
- **coverage-drift** — visible Layer-78 target coverage disagrees with the reconciled proof.

## Immutable reconciliation receipt

Runner:

`foundation.run_case_audit_verify_exec_reconciliation_v1(...)`

Ledger:

`foundation.case_audit_verify_exec_reconciliations`

Each reconciliation binds:

- exact Layer-81 executor event;
- exact Layer-76 target;
- Layer-77 verification ID/state;
- reconciliation state/reason;
- proof-integrity result;
- Layer-81 receipt-match result;
- current evidence-evaluation result;
- current Layer-78 coverage;
- complete reconciliation proof;
- SHA-256 of that reconciliation proof.

Only one reconciliation may exist per successful Layer-81 execution.

Replay returns the first immutable receipt.

## Authority boundary

Runner:

- service role only.

Read-only evaluator and summary:

- Foundation runtime;
- service role.

Foundation Gateway may read only through its established `foundation_runtime` membership and receives no direct grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

Service role cannot insert reconciliation rows directly.

## Deliberate non-actions

Layer 82 does not:

- invoke Layer 77's writer;
- invoke Layer 81's executor;
- rerun Layer 76;
- create or repair Layer-73/67 evidence;
- rewrite/delete Layer-77 proofs;
- rewrite/delete Layer-81 receipts;
- mutate Layer-79 incidents;
- mutate release truth;
- grant approval or execution authority.

## Acceptance coverage

CI proves five materially different outcomes:

1. valid Layer-81 receipt + valid Layer-77 proof + matching durable evidence → **reconciled**;
2. successful Layer-81 receipt with no Layer-77 proof → **missing-proof**;
3. valid Layer-77 proof but Layer-81 action-result mismatch → **receipt-mismatch**;
4. Layer-77 proof row with invalid proof hash → **invalid-proof**;
5. structurally valid Layer-77 proof whose current durable evidence now evaluates differently → **evidence-drift**.

It also proves:

- non-executed Layer-81 events are not applicable;
- reconciliation does not create new Layer-77 proofs;
- reconciliation does not create new Layer-81 events;
- replay is idempotent;
- reconciliation history is append-only;
- service role cannot insert reconciliation rows directly.

## Invariant

> An executor receipt is evidence of a claim. Reconciliation is evidence that the claim still agrees with reality.
