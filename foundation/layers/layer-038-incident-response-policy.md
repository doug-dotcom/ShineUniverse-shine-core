# Foundation Layer 38 — Incident response policy

**Status:** LIVE  
**Scope:** define permitted, approval-gated and prohibited response actions for Foundation control-plane incidents without granting the incident engine repair authority

Layer 37 establishes a persistent incident lifecycle for release-projection exceptions.

Layer 38 answers the next question:

> What is Foundation allowed to do once an incident exists?

The answer is now an explicit policy matrix.

Incident severity changes **response relevance**, never underlying authority.

## Response action catalogue

Layer 38 registers eleven control-plane response actions across five classes.

### Observe

- `inspect-projection-evidence`

Read-only inspection of registry, release-ledger, binding and reconciliation evidence.

### Evidence

- `collect-fresh-evidence`
- `request-release-reattestation`

These may gather or request fresh evidence but do not rewrite authoritative truth.

### Proposal

- `propose-registry-repair`
- `propose-release-ledger-repair`

These create proposed remediation only.

They do not execute the repair.

### Authoritative mutation

- `apply-registry-repair`
- `apply-release-ledger-repair`
- `rebind-release-identity`
- `auto-repair-authoritative-truth`

These actions change authoritative release truth and therefore receive the strongest policy boundary.

### Incident-history mutation

- `suppress-control-plane-incident`
- `delete-control-plane-incident-history`

These would hide or remove append-only incident evidence and remain prohibited.

## Explicit policy matrix

The policy ledger is:

`foundation.control_plane_incident_response_policies`

Current policy view:

`foundation.current_control_plane_incident_response_policies`

Layer 38 has:

- **11 active actions**
- **4 incident states**
- **44 current policies**

Incident states:

- `normal`
- `watching`
- `warning`
- `critical`

Decisions:

- `admit`
- `approval-required`
- `deny`
- `not-applicable`

No response falls through an unspecified default.

## Core authority rule

Layer 38 enforces:

> **An incident does not grant new authority.**

No authoritative mutation is directly admitted in any incident state.

When a warning or critical incident makes an authoritative repair relevant, the decision is:

`approval-required`

with control:

`external-approval`

The policy evaluator does not issue that approval and does not execute the mutation.

## Always prohibited

The following remain denied in every state:

- `auto-repair-authoritative-truth`
- `suppress-control-plane-incident`
- `delete-control-plane-incident-history`

A critical incident therefore cannot cause Foundation to rewrite registry/release/binding truth automatically or erase the evidence that an incident occurred.

## State behaviour

### NORMAL

Admitted:

- inspect projection evidence;
- collect fresh evidence.

Not applicable:

- re-attestation request;
- repair proposals.

Denied:

- all authoritative mutations;
- automatic repair;
- incident suppression/deletion.

### WATCHING

Admitted:

- inspect evidence;
- collect fresh evidence.

Repair proposals are still not applicable because the Layer-37 persistence threshold has not yet been crossed.

Authoritative mutations remain denied.

### WARNING

Admitted:

- inspect evidence;
- collect fresh evidence;
- request re-attestation;
- prepare registry repair proposal;
- prepare release-ledger repair proposal.

Authoritative mutation becomes relevant but remains:

**approval-required**

### CRITICAL

Evidence collection and repair proposals remain admitted.

Authoritative repair and release rebinding remain:

**approval-required**

Critical severity does not bypass control-plane authority.

## Evaluator

Response evaluator:

`foundation.evaluate_control_plane_incident_response_v1(text,text)`

It returns:

- current incident state;
- action class;
- decision;
- required control;
- whether the action mutates authoritative truth;
- whether the action mutates incident history;
- policy version/evidence;
- current incident summary;
- `authorityExpansion: false`.

Unknown action keys fail closed with:

`response-action-not-registered`

and decision:

`deny`.

## Response plan

Foundation can expose the complete current response plan through:

`foundation.get_control_plane_incident_response_plan_v1(text)`

The plan is advisory/policy output only.

It explicitly reports:

- `authorityExpansion: false`
- `automaticRepairAllowed: false`

and lists all eleven actions with their current decisions.

## Policy health

Coverage reader:

`foundation.get_control_plane_incident_response_policy_health_v1(text)`

Production currently reports:

- state: **PASS**
- active actions: **11**
- expected policies: **44**
- current policies: **44**
- missing policies: **0**
- authority-expansion violations: **0**
- automatic-repair policy violations: **0**
- incident-history mutation violations: **0**

## Production release

Layer 38 release:

`foundation:layer-38:b7c5331f`

The Gateway runtime remains v85 because Layer 38 is database control-plane policy, not a Gateway artefact change.

Current release projection remains:

**ALIGNED**

Current control-plane incident state remains:

**NORMAL**

- active incidents: **0**
- watches: **0**
- incident events: **0**

The live NORMAL response plan admits only non-mutating inspection/evidence activity and denies authoritative mutation.

## Acceptance coverage

Foundation CI proves:

- policy coverage is complete: 44/44;
- NORMAL admits read-only inspection;
- NORMAL denies registry repair;
- automatic authoritative repair is denied;
- incident-history deletion is denied;
- WATCHING admits evidence collection;
- WATCHING does not make repair proposals applicable;
- WATCHING denies authoritative repair;
- WARNING admits re-attestation and proposals;
- WARNING requires external approval for authoritative mutation;
- CRITICAL still requires external approval for registry repair, release-ledger repair and release rebinding;
- CRITICAL cannot suppress/delete incident history;
- unknown actions fail closed;
- runtime may evaluate/read policy;
- runtime may not mutate the policy catalogue or ledger.

Full Foundation CI run:

`36407485861`

completed successfully.

## Advisor result

Post-deployment:

- **no Layer-38 security findings**
- **no Layer-38 performance findings**

## Closure invariant

Foundation incident response now obeys:

> **Evidence may be collected automatically, proposals may become relevant during real incidents, but authority to rewrite canonical truth is never created by the incident itself.**

Layer 38 decides what is permissible.

It executes nothing.
