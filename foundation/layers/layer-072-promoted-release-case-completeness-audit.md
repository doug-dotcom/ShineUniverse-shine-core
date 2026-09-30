# Foundation Layer 72 — Promotion-trust case completeness audit

**Status:** LIVE — corrected CI green, production case audit deployed and structurally clean  
**Scope:** audit the entire Layers 65–71 case chain for structural gaps, invalid bindings and legitimate waiting states

Layers 65–71 now provide every stage of a governed promotion-trust case.

Layer 72 makes the chain auditable as one system.

## What it audits

Reader:

`foundation.get_foundation_promoted_release_case_audit_v1(...)`

It walks each Shine Core promotion-trust handoff through:

1. persistent incident;
2. owner handoff;
3. owner acknowledgement;
4. owner evidence;
5. independent Foundation verification.

Layer 71 receipts are a projection of the Layer-70 proof, so a valid independent verification also means a receipt is safely projectable.

## Legitimate stages

A structurally valid case may be:

- awaiting-owner-response;
- owner-rejected;
- clarification-requested;
- awaiting-owner-evidence;
- awaiting-independent-verification;
- verified.

`owner-rejected` and `verified` are terminal structural stages.

The audit does not confuse “pending” with “broken”.

## Overdue handoff detection

Layer 65 incidents become owner work through the hosted Layer-67 materialiser.

A warning/critical current incident therefore receives a bounded handoff-materialisation grace period.

Default:

**180 seconds**

States:

- not-required
- grace
- present
- missing

A missing handoff after grace makes the audit state:

`gap`

## Cryptographic and relational integrity

For every case Layer 72 independently recomputes:

- handoff SHA-256;
- acknowledgement SHA-256;
- owner-evidence SHA-256;
- independent-verification SHA-256.

It also verifies that each stage binds the exact previous stage:

- acknowledgement → handoff;
- evidence → acknowledgement + handoff;
- verification → evidence + acknowledgement + handoff + incident.

A corrupt or mismatched historical case therefore remains visible as:

`invalid`

instead of disappearing merely because it is no longer current.

## Overall states

- **idle** — no active case and no historical case;
- **active-work** — a current incident has a valid handoff/work chain;
- **historical** — no active incident, but structurally auditable history exists;
- **gap** — active warning/critical incident is overdue for owner handoff;
- **invalid** — one or more case-chain integrity/binding checks failed.

## Authority boundary

Layer 72 is internal read-only control-plane evidence.

Direct readers:

- `foundation_runtime`
- `service_role`

The existing Foundation role graph grants `foundation_runtime` to `foundation_gateway`. Gateway therefore inherits this **read-only** audit capability through that established runtime role. Layer 72 grants no direct Gateway EXECUTE privilege and adds no mutation capability.

Denied:

- Shine Core owner;
- Shine Defence runtime;
- browser roles.

The audit cannot mutate trust, incident history, approval state or execution authority.

## Acceptance coverage

The first Layer-72 run exposed one privilege-model mismatch in the test: `foundation_gateway` inherits `foundation_runtime` by long-standing design, so Gateway can inherit this read-only audit function even though Layer 72 grants it no direct EXECUTE privilege.

The layer documentation, contract and test were corrected to reflect the real role graph rather than weakening or changing it.

The response-plan binding was also hardened before final verification so acknowledgement and owner evidence must bind the exact Layer-67 semantic plan fingerprint instead of passing through a duplicate field-name comparison.

Corrected full Foundation CI run `36690675293` completed successfully with both Foundation jobs green. Layer-72 apply/tests passed, persistence completed the full chain, and all downstream Shine Defence checks remained green.

CI proves:

- healthy empty production shape is idle;
- overdue active incident without handoff is a gap;
- current handoff without response is legitimate pending work;
- accepted acknowledgement advances to awaiting owner evidence;
- returned owner evidence advances to awaiting independent verification;
- completed verification becomes terminal verified;
- hashes/bindings verify across the complete chain;
- a corrupt historical handoff makes the audit invalid;
- internal audit access remains inside the existing Foundation runtime/control-plane boundary;
- Gateway access is inherited only through its pre-existing `foundation_runtime` membership, not a new direct grant.

## Production proof

Layer 72 is deployed in the Shine Foundation Supabase project as:

`foundation_layer_072_promoted_release_case_audit`

Current production audit:

- overall state: **idle**
- structural integrity pass: **true**
- incident state: **normal**
- active incident handoff state: **not-required**
- cases: **0**
- invalid cases: **0**
- active cases: **0**
- pending cases: **0**
- terminal cases: **0**
- historical cases: **0**
- handoff grace: **180 seconds**
- mutates authoritative truth: **false**
- mutates incident history: **false**
- grants approval: **false**
- grants execution authority: **false**

This is the correct healthy baseline. No synthetic incident or historical case was created in production merely to populate the audit.

Privilege proof:

- Foundation runtime can read audit: **yes**
- service role can read audit: **yes**
- Gateway can read audit through its pre-existing `foundation_runtime` membership: **yes**
- Gateway receives a direct Layer-72 grant: **no**
- Shine Core owner can read internal audit: **no**
- Shine Defence runtime can read internal audit: **no**
- anonymous/authenticated roles can read internal audit: **no**

Supabase advisors show no Layer-72-specific security or performance finding. Layer 72 adds one read-only function and no table or index; existing estate-wide advisory notices remain unrelated.

## Invariant

> Every stage may wait. No stage may silently disappear, skip its prerequisite, or rewrite its history.
