# ADR-005 — Identity claims require two independent user proofs

**Status:** Accepted  
**Foundation layer:** 14

## Decision

Foundation will never infer that an unbound pseudonymous app session belongs to an existing canonical Shine identity.

A claim requires:

- proof of the source pseudonymous session;
- proof of an existing canonical target identity through a separately approved claim provider;
- proof of the calling Shine app backend.

The source and target identity providers must be distinct.

## Consequences

- a browser session cannot claim a Shine ID merely because the app knows who usually uses it;
- a normal app identity-provider link does not imply permission to use that provider as a claim target;
- an existing source binding can never be silently reassigned to a different Shine ID;
- the claim response does not reveal the target Shine ID or provider subjects;
- identity claim does not imply Vault consent and creates no grant.

Any later grant must be a separate explicit operation.
