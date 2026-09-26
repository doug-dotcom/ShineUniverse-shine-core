# ADR-004 — Identity providers are approved per app

**Status:** Accepted  
**Foundation layer:** 10

## Decision

Foundation identity providers are not globally interchangeable across appendages.

Each connected Shine app must have an explicit active link to every identity provider it is permitted to use.

The Gateway supplies the requesting app identity to the identity verifier, and the verifier accepts a JWT issuer only when:

- the provider is active in Foundation; and
- the provider is actively linked to that requesting app.

## Rationale

A globally trusted issuer is still the wrong issuer for an app unless Core says the relationship exists.

Per-app provider approval reduces confused-deputy and cross-app identity-routing risk while preserving canonical Shine ID after successful verification.
