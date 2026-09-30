# Foundation Layer 80 — Verification coverage incident response policy

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** govern what Foundation may do in response to a Layer-79 verification-coverage incident

Layer 79 can tell Foundation that verification coverage has become a persistent operational problem.

Layer 80 answers the next question:

> **What response is actually permitted for this kind of failure?**

The answer stays deliberately narrow.

## Cause classifier

`foundation.get_case_audit_verify_incident_cause_v1(...)`

It reads:

- Layer-79 incident state;
- current Layer-78 verification coverage.

It then classifies the failure as one of:

- **none**
- **verification-proof-integrity**
- **verification-omission**
- **durable-evidence-missing**
- **durable-evidence-mismatch**
- **verification-coverage-gap**
- **unknown**

The classifier also identifies the next evidence action without executing it.

### Cause precedence

A structurally invalid Layer-77 proof has highest priority.

Then:

1. overdue unverified execution;
2. missing durable evidence;
3. mismatched durable evidence;
4. generic coverage gap.

That prevents Foundation from treating a corrupted proof as a mere retry problem.

## Response evaluator

`foundation.evaluate_case_audit_verify_incident_response_v1(...)`

Every action receives:

- action class;
- decision;
- required control;
- reason code;
- current cause.

The evaluator never executes the action.

## Admitted responses

### Read-only inspection

Always admissible:

- `inspect-verification-coverage`

Conditionally admissible:

- `inspect-unverified-executions`
- `inspect-durable-evidence-chain`
- `inspect-verification-proof`

Each is admitted only when relevant to the classified cause.

### Bounded verification

`run-independent-verification`

is admitted only when:

- Layer 79 is WATCHING or CRITICAL; and
- the cause is **verification-omission**.

Required control:

`layer-77-bounded-verifier`

That points back to:

`foundation.run_case_audit_safe_response_verification_v1(...)`

Layer 80 itself still does not invoke it.

Known **missing** or **mismatched** evidence is not sent back through Layer 77 again because Layer 77 proofs are immutable and replay-safe. Re-running the verifier would only return the existing proof.

## Explicitly prohibited responses

Layer 80 always denies:

- rerunning Layer 76;
- manufacturing durable evidence;
- repairing durable evidence in place;
- rewriting a Layer-77 verification proof;
- deleting a Layer-77 verification proof;
- repairing the verification ledger by mutation;
- suppressing the Layer-79 incident;
- deleting Layer-79 incident history;
- mutating release truth.

An incident can make diagnosis urgent. It cannot create new authority.

## Response plan

`foundation.get_case_audit_verify_incident_response_plan_v1(...)`

The plan contains the complete governed action set with decisions and required controls for the current cause.

It also exposes the bounded Layer-77 verifier by name, but grants no execution through the plan itself.

## Read boundary

Declared readers:

- Foundation runtime;
- service role.

Foundation Gateway may read through its established `foundation_runtime` membership only; Layer 80 gives it no direct EXECUTE grant.

Denied:

- Shine Core;
- Shine Defence;
- browser roles.

## Deliberate non-actions

Layer 80:

- performs no verification;
- performs no safe-response reexecution;
- writes no evidence;
- changes no verification proof;
- changes no Layer-79 incident history;
- changes no release truth;
- grants no approval;
- grants no execution authority.

## Invariant

> The incident may select the next bounded control. It never becomes the control itself.
