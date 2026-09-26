# Foundation Layer 8 — First appendage: Shine Travel

**Status:** Live bridge deployed; first authenticated user ALLOW not yet observed  
**Date:** 2026-09-26  
**Pilot app:** Shine Travel

Layer 8 connects the first independent Shine appendage to the hosted Foundation without making Foundation a dependency of Travel's primary purpose.

## Architecture

Shine Travel remains a Railway-hosted application with its existing Shine-L Supabase sign-in.

The connected request path is:

```
Travel browser session
  -> Travel backend
  -> server-only Shine app credential
  -> Foundation Gateway
  -> trusted Shine-L Auth issuer verification
  -> canonical Shine ID mapping
  -> Core app manifest
  -> synthetic pilot Vault resource
  -> explicit pilot grant
  -> Shine Defence
  -> append-only audit
  -> minimal allow/deny response
```

Travel does not receive direct Foundation database access and does not know or submit the user's canonical Shine ID in Gateway v2.

## Existing identity preserved

No second Travel login was introduced.

Foundation registers Shine-L in the canonical `identity_providers` federation registry as an external Supabase Auth issuer. A Travel user JWT is accepted only after Foundation verifies it against the registered Shine-L Auth service, then maps the verified Auth subject to canonical Shine ID.

## Pilot data

The first permission deliberately uses a synthetic `foundation.pilot` Vault resource.

The pilot proves identity, app attestation, manifest declaration, Vault grant, Defence and audit flow without sharing a personal preference, file, location or other private user value.

Canonical pilot permission:

- app: `shine.travel`
- scope: `vault.foundation.pilot.read`
- purpose: `travel.foundation-pilot`
- resource category: `foundation.pilot`

## Travel runtime

Travel's production Railway backend contains a server-only Foundation client and an authenticated `GET /api/foundation/pilot` endpoint. The signed-in account bar now calls that endpoint and displays a small `Foundation connected` / checking / unavailable state without exposing identity, grant or Vault internals.

The client:

- forwards the already-verified Travel user JWT;
- sends the app credential only from the backend;
- uses Gateway request v2;
- does not send `shineId`;
- has a response byte limit and request timeout;
- converts Foundation outages into an optional unavailable state.

Travel's standalone UI and trip functionality continue operating if Foundation is unavailable.

## Defence

Travel's real Railway Docker build ran the full Shine Defence/Travel gate, including the `SD-FOUNDATION-001` control, and completed 511/511 tests successfully.

The final reconciled Travel deployment completed successfully and the production container started cleanly.

## Hosted Foundation

The hosted `foundation-gateway` is ACTIVE as version 4 with Supabase's project-local JWT precheck disabled.

This is intentional: the Gateway performs custom dual authentication in code:

1. server-only app credential verification;
2. registered external user-token issuer verification.

The hosted Supabase security advisor remains at zero security lints.

## Acceptance boundary

At the current Layer 8 acceptance boundary:

- Travel production bridge: live;
- app credential: provisioned as a hash in Foundation and secret in Railway;
- trusted Shine-L issuer: active;
- existing Travel users: mapped into Shine ID;
- pilot Vault resources: provisioned;
- pilot grants: provisioned;
- Travel Railway build + Defence certification: passed;
- Foundation hosted Gateway: ACTIVE.

No production `travel.foundation-pilot` audit event had yet been observed at the time this layer was recorded, so Layer 8 does not claim that a real logged-in user has completed the first live ALLOW request.

That first observed ALLOW is the next operational milestone, not a missing deployment component.


## Federation consolidation

During Layer 8 reconciliation, a temporary duplicate issuer/connection-test path was retired. The active architecture is again the original Gateway v2 design:

- canonical federation registry: `foundation.identity_providers`;
- canonical Travel request: Gateway v2 with no caller-supplied `shineId`;
- canonical pilot scope: `vault.foundation.pilot.read`;
- canonical pilot purpose: `travel.foundation-pilot`;
- canonical pilot category: `foundation.pilot`.

Duplicate connection-test grants and the later duplicate Travel app credential were revoked rather than deleted, preserving append-only security history.


## Visible connection state

The production Railway UI now checks the authenticated pilot automatically after a user session is established.

The account bar shows:

- **Foundation connected** — the live pilot returned `allowed`;
- **Checking Foundation…** — the handshake is in progress;
- **Foundation unavailable** — Foundation could not be reached or did not allow the pilot.

The status is informational only. It does not gate Travel's primary planner, saved journeys, research or document workflows.
