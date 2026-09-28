# Foundation Layer 41 — Scoped remediation executor

**Status:** LIVE  
**Scope:** atomically consume a valid Layer-40 execution admission and perform only one exact, pre-approved remediation mutation shape

Layer 40 proves that a consumed external approval still does not reach canonical truth directly.

Layer 41 adds the final mutation boundary.

The executor is deliberately not a generic SQL runner. It accepts one canonical remediation proposal, verifies that the proposal hashes to the exact SHA-256 approved in Layers 39 and 40, revalidates live incident/policy/release scope, atomically consumes the execution admission, and dispatches only to one of three hard-coded remediation operations.

## Separate mutation authority

Layer 41 creates:

`foundation_remediation_mutator`

Properties:

- **NOLOGIN**
- **NOINHERIT**
- not inherited by `service_role`
- not inherited by `foundation_remediation_approver`
- not inherited by `foundation_remediation_executor`
- may execute only `foundation.execute_scoped_remediation_v1(...)`
- has no direct UPDATE on `universe.app_registry`
- has no direct INSERT on `universe.readiness_releases`
- has no direct INSERT on the execution-event ledger

The SECURITY DEFINER executor owns the mutation logic.

The role holding mutation authority therefore cannot bypass the exact proposal/admission checks with direct table access.

## Canonical proposal

Layer 41 uses:

`shine-foundation/remediation-proposal-v1`

Proposal integrity is calculated through:

`foundation.get_remediation_proposal_sha256_v1(jsonb)`

The exact JSONB proposal must hash to the SHA-256 recorded in:

1. the Layer-39 approval receipt;
2. the Layer-39 approval consumption event;
3. the Layer-40 execution admission.

Unknown proposal fields are rejected.

Maximum proposal size:

**32 KiB**

Changing any approved mutation value therefore changes the proposal hash and invalidates execution.

## Executor

The only mutation entry point is:

`foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)`

Only `foundation_remediation_mutator` receives EXECUTE.

Before any mutation it revalidates:

- execution admission exists;
- admission has not already been consumed;
- admission integrity SHA-256;
- admission activation/expiry;
- execution operation is still active;
- operation contract / target authority / mutation shape still match;
- Layer-39 approval receipt integrity;
- matching Layer-39 consumed approval event exists;
- approval/admission action, incident, evidence, release and proposal scope all match;
- proposal SHA-256 exactly matches;
- proposal contract/version/environment/action/incident/evidence/release scope all match;
- incident is still the current active opened/changed incident;
- incident evidence fingerprint still matches;
- live Layer-36 projection is still FAIL or UNKNOWN;
- live Layer-36 fingerprint still matches;
- live release ref still matches;
- Layer-38 response policy is still approval-required under the same policy version.

A pre-mutation denial records a denied execution event but does **not** consume the admission.

Once an actual mutation attempt begins, success **or failure** consumes the admission.

That fail-safe rule prevents retrying changed mutation conditions under an old approval.

## Hard-coded operation 1 — Registry repair

Action:

`apply-registry-repair`

Mutation:

`scoped-registry-correction`

The proposal must contain the exact current Foundation registry before-state:

- current layer;
- current-layer status;
- build state;
- readiness release ref.

Layer 41 compares this expected state under row lock.

If any value has changed, execution fails.

If it still matches, Foundation updates only the Foundation registry projection to the current immutable release binding:

- bound Foundation layer;
- `verified`;
- `deployed`;
- bound release ref;
- approved evidence note.

This is a compare-and-set repair, not an arbitrary registry update.

## Hard-coded operation 2 — Release-ledger repair

Action:

`apply-release-ledger-repair`

Mutation:

`scoped-release-ledger-correction`

This operation may only create the missing readiness-release row for the **current immutable binding**.

It is insert-only.

If the target release already exists, execution fails.

The proposal controls only constrained release evidence fields:

- release label;
- canonical repository commit SHA;
- canonical GitHub commit evidence URL;
- optional evidence note.

Existing release-ledger rows are never overwritten.

## Hard-coded operation 3 — Release identity rebind

Action:

`rebind-release-identity`

Mutation:

`append-only-release-rebind`

The proposal must identify:

- Foundation layer;
- exact current binding ID;
- exact current binding release ref.

Execution also requires:

- Universe registry still points to that approved prior binding;
- release-identity health is FAIL;
- reason codes prove `release-identity-deployment-mismatch`;
- current deployment/publication evidence independently satisfies the Layer-35 binder.

Layer 41 then calls the existing immutable binder.

The new binding is append-only.

The rebind operation **does not** silently rewrite the Universe registry or readiness-release ledger. Those projections remain separate remediation operations with their own approvals.

## Execution ledger

Layer 41 adds:

`foundation.remediation_execution_events`

Every execution attempt records:

- execution ID;
- admission;
- approval receipt;
- incident;
- action;
- event type;
- reason;
- proposal SHA-256;
- exact proposal;
- before snapshot;
- mutation result;
- after snapshot;
- failure detail when applicable;
- timestamp.

Lifecycle values:

- `denied`
- `failed`
- `executed`

The ledger is append-only.

A partial unique index guarantees only one consuming event (`failed` or `executed`) per admission.

## Admission consumption semantics

### Denied before mutation

Examples:

- proposal hash mismatch;
- expired admission;
- stale incident;
- changed evidence;
- changed policy.

Result:

- execution denied;
- denial recorded;
- admission remains unconsumed.

### Mutation attempted and failed

Examples:

- approved registry before-state no longer matches;
- release-ledger target unexpectedly already exists;
- rebind prerequisites fail after admission.

Result:

- mutation transaction is rolled back;
- failure event is recorded;
- admission becomes consumed;
- fresh approval/admission is required.

### Mutation executed

Result:

- exact hard-coded mutation is applied;
- before/result/after evidence is appended;
- admission becomes consumed;
- replay is denied.

## Admission status integration

Layer 41 upgrades:

`foundation.get_remediation_execution_admission_status_v1(uuid)`

An admission now reports:

`consumed`

after either an executed or failed mutation attempt and includes the consuming execution event.

`mayAttemptExecution` becomes false.

## Production control health

Layer 41 adds:

`foundation.get_scoped_remediation_executor_control_health_v1()`

Current production state:

- control health: **PASS**
- mutator role exists: **true**
- mutator login: **false**
- service role is mutator member: **false**
- approver is mutator member: **false**
- admission executor is mutator member: **false**
- service role can execute: **false**
- approver can execute: **false**
- admission executor can execute: **false**
- mutator can execute scoped executor: **true**
- mutator can update registry directly: **false**
- mutator can insert release ledger directly: **false**
- mutator can insert execution events directly: **false**
- registered execution operations: **3**
- auto-repair registered: **false**
- arbitrary SQL execution: **false**

Healthy production currently has:

- execution admissions: **0**
- remediation execution events: **0**

## Production release

Layer 41 release:

`foundation:layer-41:1a8148a8`

Current Gateway identity:

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

Current release identity:

**PASS**

Current release projection:

**ALIGNED**

Current incident state:

**NORMAL**

After Layer-41 promotion the reconciliation sentinel recorded the new aligned projection and created no incident event.

## Acceptance coverage

Layer-41 CI performs actual mutation-path integration inside rollback-only transactions.

It proves:

- initial release-ledger projection can be repaired through approval → consumption → admission → mutation;
- tampering with the approved proposal is denied without consuming the admission;
- an exact approved release-ledger proposal executes successfully;
- execution admission becomes consumed after success;
- registry mismatch remains a separate incident after release-ledger repair;
- an approved registry proposal with the wrong compare-and-set before-state fails and consumes the admission;
- the failed mutation rolls back;
- a fresh approval/admission with the correct before-state repairs the registry;
- registry + release-ledger repairs restore projection alignment;
- a simulated replacement runtime makes the immutable binding stale;
- an approved append-only rebind binds the new runtime;
- rebind does not silently rewrite Universe registry/release projection;
- consumed admission replay is denied;
- service/approver/admission-executor roles cannot perform mutation;
- mutation authority remains isolated to the dedicated mutator role;
- the mutator role has no direct table mutation grants.

Foundation CI run:

`36413060917`

passed end-to-end with the formal Layer-41 contract.

## Advisor hardening

Post-deployment advisors initially identified missing covering indexes on:

- `approval_receipt_id`;
- `incident_event_id`.

Both are now covered.

Current Layer-41 advisor result:

- **no Layer-41 security findings**
- **no unindexed Layer-41 foreign keys**
- remaining performance notices are only unused-index INFO entries because production has no remediation execution rows

## Closure invariant

Layer 41 establishes:

> **Canonical truth can now be repaired, but only after an incident persists, policy allows remediation, an independent approver signs one exact proposal, that approval is consumed, an independent execution gate revalidates live truth, and a separately held mutator executes one hard-coded mutation shape.**

There is still no generic repair authority.

There is still no automatic repair path.

Every mutation is explicit, scoped, single-use and auditable.
