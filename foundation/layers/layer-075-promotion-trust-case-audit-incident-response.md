# Foundation Layer 75 — Promotion-trust case-audit incident response policy

**Status:** IMPLEMENTED — CI and production verification pending  
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

## Invariant

> A broken governance chain can tell us which existing control to use. It cannot invent a new authority to repair itself.
