# Foundation Layer 66 — Promoted-release incident response policy

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** classify promotion-trust incident causes and define safe next actions without creating a second release-mutation authority

Layer 65 makes persistent loss of promoted-release trust an operational incident.

Layer 66 answers:

> What should Foundation do next, and which existing authority boundary controls that action?

## Cause separation

Cause reader:

`foundation.get_foundation_promoted_release_incident_cause_v1(...)`

It classifies current trust evidence into:

- none
- canonical-source-truth
- promotion-closure-open
- promotion-closure-integrity
- promotion-closure-stale
- observer-drift
- observer-freshness
- promotion-hold-other
- unknown

Each cause names the evidence domain and the next non-mutating evidence action.

## Local safe actions

Layer 66 directly admits only actions that do not mutate release truth:

- inspect promoted-release trust;
- inspect canonical source truth;
- inspect promotion closure;
- record a fresh promoted-release observation when observer drift/freshness is the cause.

A fresh observation is evidence-only. It cannot repair the condition it observes.

## No second mutation authority

Release-truth actions are delegated to the existing Layer-38 policy:

`foundation.evaluate_control_plane_incident_response_v1(...)`

Delegated actions include:

- request release re-attestation;
- propose registry repair;
- propose release-ledger repair;
- apply registry repair;
- apply release-ledger repair;
- rebind release identity.

Layer 66 returns the Layer-38 decision and required control unchanged.

A Layer-65 critical incident therefore cannot turn a Layer-38 denial into approval-required or an approval-required decision into admit.

## Hard denials

Always denied:

- automatic authoritative truth repair;
- suppression of promoted-release incident history;
- deletion of promoted-release incident history.

Unknown actions also fail closed.

## Response plan

`foundation.get_foundation_promoted_release_incident_response_plan_v1(...)`

returns:

- incident/trust state;
- cause class and source domain;
- next evidence action;
- all local and delegated action decisions;
- explicit `authorityExpansion: false`;
- explicit `automaticRepairAllowed: false`;
- the existing Layer-38 release-truth authority function.

## Acceptance coverage

CI proves:

- healthy trust is classified as no cause;
- trust inspection remains read-only;
- healthy observer refresh is not applicable;
- critical HOLD from canonical-source-truth failure is classified correctly;
- authoritative registry repair preserves Layer-38 external-approval requirement;
- Layer-38 rebind denial remains denial;
- automatic repair remains prohibited;
- observer freshness incidents admit only evidence refresh;
- unknown actions fail closed;
- history suppression remains denied;
- runtime can read/evaluate plans;
- browser roles cannot.

## Invariant

> Promotion-trust severity changes what evidence deserves attention. It never changes who is allowed to rewrite release truth.
