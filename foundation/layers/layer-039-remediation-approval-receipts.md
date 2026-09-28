# Foundation Layer 39 — Scope-bound remediation approval receipts

**Status:** LIVE  
**Scope:** represent external approval for Layer-38 approval-required remediation actions as immutable, time-bounded, single-use receipts without executing the approved action

Layer 38 establishes a response policy boundary:

- non-mutating evidence and proposal actions may be admitted;
- authoritative mutation is never directly admitted;
- when mutation becomes relevant during a warning/critical incident, it is marked **approval-required**.

Layer 39 turns that external approval requirement into verifiable database evidence.

## Separate approver authority

Layer 39 creates the dedicated Postgres role:

`foundation_remediation_approver`

Properties:

- **NOLOGIN**
- **NOINHERIT**
- not inherited by `service_role`
- may issue remediation approval receipts
- may not consume them
- has no direct table mutation grant

`service_role` cannot mint approval.

It may consume a valid receipt, but consumption itself does not execute the remediation action.

This separates:

**approval authority** from **runtime/control-plane consumption**.

## Approval receipt ledger

Immutable approval receipts live in:

`foundation.remediation_approval_receipts`

Each receipt is bound to the exact:

- environment;
- current active incident event;
- incident key;
- incident state/severity;
- remediation action;
- Layer-38 policy version;
- incident evidence fingerprint;
- Foundation release ref;
- proposed remediation SHA-256;
- approver identity;
- approval method;
- approval time;
- expiry time.

The receipt includes its own SHA-256 integrity hash.

The append-only consumption/denial ledger is:

`foundation.remediation_approval_events`

## Issuance

Receipts are issued through:

`foundation.issue_remediation_approval_receipt_v1(...)`

Only `foundation_remediation_approver` receives EXECUTE.

Issuance succeeds only when:

1. the supplied incident event is still the current active `opened` / `changed` incident;
2. the incident is WARNING or CRITICAL;
3. Layer 38 currently says the action is `approval-required`;
4. the required control is `external-approval`;
5. the action mutates authoritative truth;
6. the incident snapshot contains a valid Foundation release ref;
7. a concrete remediation proposal SHA-256 is supplied;
8. the approval expiry is no more than **15 minutes** after approval time.

The receipt explicitly states:

- `singleUse: true`
- `executionAuthority: false`
- `executesAction: false`

Approval therefore proves consent for a scoped remediation attempt.

It does not perform it.

## Approval methods

Supported approval methods:

- `explicit-human`
- `external-governance`

The approval source must be supplied as a concrete approver identity.

## Consumption

A receipt is consumed through:

`foundation.consume_remediation_approval_receipt_v1(...)`

Only `service_role` receives EXECUTE.

Consumption is transactional and row-locked.

It fails closed when:

- receipt is missing;
- receipt has already been consumed;
- approval is not yet valid;
- receipt integrity hash does not verify;
- receipt has expired;
- action differs;
- incident event differs;
- remediation proposal hash differs;
- the incident has changed or recovered;
- evidence fingerprint no longer matches;
- Layer-38 policy is no longer approval-required;
- policy version no longer matches.

A denied attempt is recorded but does **not** consume the approval.

A successful attempt writes exactly one `consumed` event.

Replay is then denied.

## Single-use semantics

Once consumed, the approval cannot be reused.

A later retry requires a new approval receipt.

This deliberately prefers fail-safe interruption over replayable mutation authority.

If execution fails after approval consumption, the action remains unexecuted and a new approval is required.

## Incident-change invalidation

Approvals bind to the exact Layer-37 incident event and evidence fingerprint.

If an active incident appends a new `changed` event, any approval bound to the previous incident event becomes stale.

This prevents a remediation approved for one diagnosed failure from being reused against materially different evidence.

## Proposal binding

Every receipt binds to:

`proposal_sha256`

The approval therefore applies to one exact proposed remediation payload.

Changing the proposal requires a new approval.

## No approval for prohibited actions

Layer 39 cannot mint a receipt for actions that Layer 38 denies.

In particular:

`auto-repair-authoritative-truth`

cannot receive an approval receipt.

Incident suppression and incident-history deletion are likewise outside the approval path because they are not Layer-38 approval-required actions.

## Status reader

Internal status is available through:

`foundation.get_remediation_approval_status_v1(uuid)`

Possible states include:

- active
- not-yet-valid
- consumed
- expired
- stale
- invalid
- missing

Status also reports:

- receipt integrity;
- whether the bound incident is still current;
- scope metadata;
- approval timing;
- consumption time;
- `executionAuthority: false`;
- `executesAction: false`.

## Control health

Layer 39 adds:

`foundation.get_remediation_approval_control_health_v1()`

Production currently reports:

- state: **PASS**
- approver role exists: **true**
- approver role login: **false**
- `service_role` can issue: **false**
- Foundation runtime can issue: **false**
- `service_role` is approver member: **false**
- `service_role` can consume: **true**
- Foundation runtime can consume: **false**
- `service_role` can directly insert receipts: **false**
- `service_role` can directly insert approval events: **false**
- execution authority: **false**

## Production release

Layer 39 release:

`foundation:layer-39:b7c5331f`

Gateway runtime identity remains:

- runtime: **85**
- source: `b7c5331f93eff28a781f0794c89ccf50e90a4045`
- artefact: `a596c895d31e272d2358d69e500eb708a43462de69df32e7e8a87d540907b83f`
- deployment receipt: `bac106fe-57c4-4b38-b8bb-0acb5de11086`
- publication: `2649330b-6117-44a0-9614-aae8f6fb8478`
- assurance: **github-oidc**

Current release projection:

**ALIGNED**

Current incident state:

**NORMAL**

Current live approval data:

- receipts: **0**
- approval events: **0**

Healthy Foundation therefore does not mint dormant approvals.

The first post-promotion reconciliation sentinel recorded the new aligned Layer-39 projection and created no incident or approval activity.

## Acceptance coverage

Foundation CI proves:

- dedicated approver role exists and is separated from `service_role`;
- `service_role` cannot issue receipts;
- receipt scope captures incident/action/policy/evidence/release/proposal;
- receipt integrity hash verifies;
- wrong action scope is denied without consumption;
- correct scope consumes exactly once;
- replay is denied;
- expired approval is denied;
- changed incident evidence invalidates old approval;
- auto-repair cannot receive approval;
- `service_role` cannot directly insert receipts/events;
- public API roles cannot read approval status;
- receipt consumption never returns execution authority.

Full Foundation CI run:

`36408833719`

completed successfully.

## Advisor result

Post-deployment:

- **no Layer-39 security findings**
- no missing-index or structural performance findings
- the three new indexes are initially reported as unused because healthy production currently has zero approval rows

## Closure invariant

Layer 39 establishes:

> **A remediation approval is a short-lived, single-use proof for one exact incident, action, release and proposal. The system that consumes the proof cannot mint it, and consuming it never performs the remediation.**

Approval is evidence.

Execution remains a separate future boundary.
