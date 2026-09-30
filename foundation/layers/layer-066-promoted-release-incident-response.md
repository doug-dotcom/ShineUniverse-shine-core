# Foundation Layer 66 — Promoted-release incident response policy

**Status:** LIVE — CI green, production cause/response policy verified and authority delegation proven  
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

Full Foundation CI run `36677194160` completed successfully. Both Foundation jobs passed, the Layer-66 response-policy tests passed, and every downstream Shine Defence acceptance step remained green.

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

## Production proof

Layer 66 is deployed in the Shine Foundation Supabase project.

Current production state is healthy:

- promotion-trust incident state: **normal**
- trust state: **normal**
- cause class: **none**
- source domain: **none**
- next evidence action: **none**
- authority expansion: **false**
- automatic repair allowed: **false**

The production response plan contains all 13 declared local/delegated/denied actions.

Healthy baseline behaviour is deliberately quiet:

- inspect promoted-release trust: **admit / read-only**
- inspect canonical source truth: **not applicable**
- inspect promotion closure: **not applicable**
- fresh promoted-release observation: **not applicable**

Hard fail-closed proof:

- invented/unknown action: **deny / prohibited**
- automatic authoritative truth repair: **deny / prohibited**
- incident-history suppression/deletion: **deny / prohibited**

Release-truth authority remains delegated to:

`foundation.evaluate_control_plane_incident_response_v1`

Layer 66 does not create a second repair authority and cannot upgrade a Layer-38 decision.

Production privilege proof:

- Foundation runtime can read cause classification: **yes**
- Foundation runtime can evaluate response actions: **yes**
- Foundation runtime can read response plan: **yes**
- anonymous response-plan access: **no**
- authenticated response-plan access: **no**

Supabase advisors show no Layer-66-specific security or performance finding. New estate-wide advisor findings observed during this layer belong to concurrent GitHub-OIDC/Defence work; the existing promoted-release incident observation index is also currently reported unused because the production Layer-65 incident ledger remains empty.

## Invariant

> Promotion-trust severity changes what evidence deserves attention. It never changes who is allowed to rewrite release truth.
