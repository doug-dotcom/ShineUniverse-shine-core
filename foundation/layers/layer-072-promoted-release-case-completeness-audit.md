# Foundation Layer 72 — Promotion-trust case completeness audit

**Status:** IMPLEMENTED — CI and production verification pending  
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

Readers:

- `foundation_runtime`
- `service_role`

Denied:

- Shine Core owner;
- Foundation Gateway;
- Shine Defence runtime;
- browser roles.

The audit cannot mutate trust, incident history, approval state or execution authority.

## Acceptance coverage

CI proves:

- healthy empty production shape is idle;
- overdue active incident without handoff is a gap;
- current handoff without response is legitimate pending work;
- accepted acknowledgement advances to awaiting owner evidence;
- returned owner evidence advances to awaiting independent verification;
- completed verification becomes terminal verified;
- hashes/bindings verify across the complete chain;
- a corrupt historical handoff makes the audit invalid;
- internal audit access remains Foundation-only.

## Invariant

> Every stage may wait. No stage may silently disappear, skip its prerequisite, or rewrite its history.
