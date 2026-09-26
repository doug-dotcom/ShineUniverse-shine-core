# ADR-003 — Foundation authenticates both user and calling app

**Status:** Accepted  
**Foundation layer:** 6

## Decision

A valid Shine user session is necessary but not sufficient to use another app's Foundation grants.

Every connected request authenticates both:

- the human/user through Shine ID; and
- the calling Shine app through a server-side app credential.

App credentials are random secrets held only by app backends. Foundation stores only their SHA-256 hashes.

Direct browser/mobile clients cannot be trusted with app credentials and therefore call Foundation through their Shine app backend.

## Rationale

Without app attestation, any client possessing a valid user token could claim another registered `appId` and attempt to reuse that app's user grants.

Separating user authentication from app authentication prevents that confused-deputy path and gives Foundation an independently revocable trust relationship with every connected appendage.
