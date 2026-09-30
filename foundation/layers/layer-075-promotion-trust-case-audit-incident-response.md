# Foundation Layer 75 — Promotion-trust case-audit incident response policy

**Status:** LIVE — CI green, response policy deployed and fail-closed production baseline verified  
**Scope:** decide the safe next action for case-chain structural incidents without creating repair authority

Layer 74 escalates persistent failures in the governance chain itself.

Layer 75 answers:

> What response is appropriate, and which existing control must authorize it?

## Cause separation

Cause classes:

- **none**
- **case-chain-gap**
- **case-chain-integrity**
- **observer-drift**
- **observer-freshness**
- **unknown**

A gap and an integrity failure are deliberately different.

## Missing current handoff

A Layer-72/73 GAP may mean a live promotion-trust incident did not receive its expected Layer-67 owner handoff after grace.

Layer 75 may therefore admit:

`materialise-current-owner-handoff`

Required control:

`layer-67-bounded-generator`

This does not execute the generator.

It only declares that the existing bounded Layer-67 materialiser is the valid work-creation path.

Layer 67 must still independently prove:

- an active promotion-trust incident exists;
- the current incident event matches;
- the Layer-66 response plan is valid;
- the owner route is active;
- the handoff does not already exist.

## Broken historical integrity

An INVALID case is different.

Layer 75 admits read-only inspection of the case history.

It does **not** allow a new handoff to pretend old corrupt evidence has been repaired.

Always denied:

- automatic case-chain repair;
- history rewrite;
- history deletion;
- incident suppression;
- incident-history deletion.

Append-only history remains append-only.

## Observer drift/freshness

If the problem is the Layer-73 observer rather than the chain itself, Layer 75 may admit:

`record-fresh-promotion-case-audit-observation`

as:

`evidence-only`

Recording fresh evidence cannot repair the state it observes.

## Release-truth authority stays Layer 38

Release-truth actions are still delegated to:

`foundation.evaluate_control_plane_incident_response_v1`

Layer 75 returns the Layer-38 decision unchanged.

A critical case-audit incident cannot turn:

- deny → approval-required;
- approval-required → admit.

## Response plan

`foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(...)`

returns:

- incident and case-audit state;
- cause class and source domain;
- next evidence action;
- safe local action decisions;
- Layer-38 delegated action decisions;
- explicit no-authority-expansion/no-auto-repair/no-history-rewrite flags.

## Authority boundary

Read/evaluate:

- Foundation runtime
- service role
- Gateway through existing `foundation_runtime` inheritance

Denied:

- Shine Core owner
- Shine Defence runtime
- browser roles

Layer 75 executes no action.

## Acceptance coverage

Initial full Foundation CI run `36696759415` completed successfully and proved the Layer-75 cause/response semantics across the full Foundation/Defence chain.

The first production proof then exposed a small honesty issue: unknown actions correctly returned `deny / prohibited`, but mutation flags were JSON `null` because no action class existed. That was safe but ambiguous. Layer 75 was hardened so unknown/fail-closed actions now explicitly return `mutatesAuthoritativeTruth: false` and `mutatesIncidentHistory: false`.

The hardened full Foundation run `36697106346` completed successfully with persistence **207/207** green and all downstream Shine Defence checks passing.

CI proves:

- healthy baseline has no cause;
- healthy handoff materialisation is not applicable;
- unknown actions fail closed;
- critical GAP admits only the existing bounded Layer-67 materialiser;
- Layer-38 external approval remains required for registry repair;
- Layer-38 rebind denial remains denial;
- automatic case-chain repair remains denied;
- INVALID admits history inspection but not fake work regeneration;
- history deletion remains denied;
- observer freshness admits only evidence refresh;
- runtime/Gateway read-only role graph remains intact.

## Production proof

Layer 75 is deployed in the Shine Foundation Supabase project through:

- `foundation_layer_075_promoted_release_case_audit_incident_response_policy`
- `foundation_layer_075_case_audit_response_explicit_fail_closed_flags`

Current production is healthy:

- Layer-74 incident state: **normal**
- Layer-73 case-audit state: **normal**
- cause class: **none**
- source domain: **none**
- next evidence action: **none**
- authority expansion: **false**
- automatic repair allowed: **false**
- history rewrite allowed: **false**

Current response plan contains **15** declared actions.

Healthy-baseline behaviour:

- inspect promotion case audit: **admit / read-only**
- inspect promotion case history: **not applicable**
- record fresh case-audit observation: **not applicable**
- materialise current owner handoff: **not applicable**

Hard fail-closed proof:

- automatic case-chain repair: **deny / prohibited**
- case-chain history rewrite: **deny / prohibited**
- unknown action: **deny / prohibited**
- unknown-action authoritative mutation flag: **false**
- unknown-action incident-history mutation flag: **false**
- unknown-action executes action: **false**

Release-truth authority remains delegated to:

`foundation.evaluate_control_plane_incident_response_v1`

and missing-current-handoff work is permitted only through the existing bounded:

`foundation.generate_foundation_promoted_release_owner_handoff_v1`

Layer 75 itself executes neither path.

Production privilege proof:

- Foundation runtime can read/evaluate response plan: **yes**
- service role can read/evaluate response plan: **yes**
- Gateway can read through existing `foundation_runtime` membership: **yes**
- Shine Core owner can read plan: **no**
- Shine Defence runtime can read plan: **no**
- anonymous/authenticated roles can read plan: **no**

Supabase advisors show no Layer-75-specific security or performance finding. Layer 75 adds functions only; existing estate-wide notices remain unrelated.

## Invariant

> A broken governance chain can tell us which existing control to use. It cannot invent a new authority to repair itself.
