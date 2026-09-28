# Foundation Layer 40 — Remediation execution admission

**Status:** LIVE  
**Scope:** independently revalidate a consumed Layer-39 approval against live incident, policy and release evidence before allowing one narrowly registered remediation operation to be attempted

Layer 39 creates scope-bound external approval receipts.

Layer 40 adds a separate execution-admission boundary.

A consumed approval is necessary, but it is not sufficient.

Before a remediation operation can even be attempted, a dedicated executor gate independently checks that the approval still matches the current control-plane truth.

Layer 40 does **not** implement or execute the repair itself.

## Separate executor authority

Layer 40 creates:

`foundation_remediation_executor`

Properties:

- **NOLOGIN**
- **NOINHERIT**
- not inherited by `service_role`
- not inherited by `foundation_remediation_approver`
- may issue execution admissions
- cannot mint Layer-39 approvals
- has no direct insert access to admission ledgers
- has no generic SQL remediation capability

This separates:

**approval authority**  
from  
**execution-admission authority**  
from  
**future repair execution**.

## Explicit execution-operation registry

Layer 40 registers exactly three remediation operations:

1. `apply-registry-repair`
2. `apply-release-ledger-repair`
3. `rebind-release-identity`

Each has an explicit:

- operation contract;
- target authority;
- mutation shape;
- maximum admission duration.

There is no generic SQL operation.

`auto-repair-authoritative-truth` is not registered and cannot receive execution admission.

## Gate

Execution admission is issued through:

`foundation.issue_remediation_execution_admission_v1(...)`

Only `foundation_remediation_executor` receives EXECUTE.

The gate independently revalidates:

1. Layer-39 approval receipt integrity;
2. that the approval has actually been consumed;
3. approval activation/expiry;
4. exact remediation action;
5. exact incident event;
6. exact proposal SHA-256;
7. operation is explicitly registered;
8. incident is still current and active;
9. incident evidence fingerprint still matches;
10. live Layer-36 projection is still FAIL or UNKNOWN;
11. live Layer-36 evidence fingerprint still matches;
12. live Foundation release ref still matches;
13. Layer-38 policy still says approval-required;
14. policy version still matches;
15. Layer-39 consumption event scope matches the approval receipt.

Any mismatch fails closed.

## Admission lifetime

A successful execution admission lasts for at most:

**60 seconds**

and never longer than the underlying approval receipt.

One consumed approval can produce at most one execution admission.

If the admission expires unused, a fresh approval is required.

## Admission evidence

Successful admissions are stored in:

`foundation.remediation_execution_admissions`

Gate decisions are stored in:

`foundation.remediation_execution_admission_events`

Denied attempts are preserved as evidence but do not issue an admission.

Admission records include:

- approval receipt;
- approval consumption event;
- current incident;
- action;
- operation contract;
- target authority;
- mutation shape;
- Layer-38 policy version;
- evidence fingerprint;
- release ref;
- proposal SHA-256;
- admission/expiry time;
- integrity SHA-256.

The admission explicitly states:

- `singleUse: true`
- `mayAttemptExecution: true`
- `executesAction: false`

Layer 40 therefore grants permission to **attempt** the exact registered operation.

It does not perform that operation.

## Status reader

Admission state is available through:

`foundation.get_remediation_execution_admission_status_v1(uuid)`

States include:

- active
- not-yet-valid
- expired
- stale
- invalid
- missing

An admission becomes stale if:

- the incident changes or recovers;
- evidence fingerprint changes;
- release ref changes;
- the response policy is no longer approval-required;
- the registered execution operation is disabled/removed.

## Control health

Layer 40 adds:

`foundation.get_remediation_execution_admission_control_health_v1()`

Production reports:

- state: **PASS**
- executor role exists: **true**
- executor role login: **false**
- `service_role` is executor member: **false**
- approver role is executor member: **false**
- `service_role` can issue admission: **false**
- approver can issue admission: **false**
- executor can issue admission: **true**
- `service_role` can directly insert admissions: **false**
- `service_role` can directly insert admission events: **false**
- active registered execution operations: **3**
- executes action: **false**

Healthy production currently has:

- execution admissions: **0**
- execution-admission events: **0**

## Production runtime transition during Layer 40

While Layer 40 was being built, another Foundation deployment moved the live Gateway from the prior v85 runtime to:

- runtime: **90**
- source:
  `1a8148a8eb748a19ac03107d9e9ec7313297384b`
- artefact:
  `3294e28293df667224ed9ab2551e2e5a6a88bab6f6805791bec14e7d22512692`
- deployment receipt:
  `f79bde0b-588e-44a7-ac0f-d4f6e78bf986`
- publication:
  `e61ac83e-9a92-4185-88a8-9eea66ed8c2f`
- publication assurance: **github-oidc**

The older Layer-39 release identity remained correctly bound to v85 and therefore became stale.

Layer 36 reported:

**FAIL**

with:

`release-identity-health-failed`

Layer 37 correctly created only a **detected critical watch**.

Layer 40 promotion then bound the new release to the real v90 deployment:

`foundation:layer-40:1a8148a8`

Release identity returned **PASS** and release projection returned **ALIGNED**.

The incident sentinel then recorded:

`recovered`

after **283 seconds**.

The persistence threshold is 300 seconds, so the transient deployment-transition mismatch never escalated into an active incident.

This was a live production proof of the Layer 36 → 37 debounce/recovery design.

## Acceptance coverage

Layer-40 CI proves:

- executor role is isolated from service/approver roles;
- only three registered remediation operations exist;
- auto-repair is not executable;
- wrong proposal scope is denied without admission;
- consumed approval with exact live scope issues one admission;
- admission integrity hash verifies;
- admission TTL is at most 60 seconds;
- admission permits attempt but does not execute;
- one approval cannot issue a second admission;
- unconsumed approval is denied;
- expired consumed approval is denied;
- changed live incident/evidence makes existing admission stale;
- `service_role` cannot issue admission;
- approver role cannot issue admission;
- `service_role` cannot bypass the gate with direct inserts;
- public API roles cannot read admission status.

Initial fully green Foundation run:

`36410448830`

Post-advisor FK-index hardening rerun:

`36410793509`

also completed the Layer-40 apply/tests and full downstream persistence chain successfully.

## Advisor result

Post-deployment:

- **no Layer-40 security findings**
- **no unindexed Layer-40 foreign keys**
- remaining Layer-40 performance notices are only unused-index INFO entries because healthy production currently has no execution admission records

## Closure invariant

Layer 40 establishes:

> **Even a valid, consumed external approval cannot directly reach canonical truth. A separate executor role must prove that the incident, policy, evidence, release, action and proposal all still match in real time, and the resulting admission is short-lived and non-executing.**

Execution remains a separate future boundary.
