# Foundation Layer 68 — Shine Core owner acknowledgement

**Status:** IMPLEMENTED — CI and production verification pending  
**Scope:** require explicit Shine Core ownership acknowledgement for current promotion-trust handoffs without granting repair authority

Layer 67 converts persistent promotion-trust incidents into owned Shine Core work.

Layer 68 closes the next seam:

`handoff → bounded owner inbox → explicit owner acknowledgement`

## Existing owner capability reused

Layer 68 reuses the isolated Layer-57 capability:

`shine_core_control_plane`

The role remains NOLOGIN, NOINHERIT, NOSUPERUSER, NOCREATEDB, NOCREATEROLE and NOBYPASSRLS.

PostgreSQL may deliberately `SET ROLE` into it. Gateway and Foundation runtime are not members.

## Owner inbox

`foundation.get_foundation_promoted_release_owner_inbox_v1(...)`

is executable only by `shine_core_control_plane`.

It exposes only current, integrity-verified, owner-current, unresponded handoffs addressed to `foundation.gateway / shine-core`.

## Explicit response

`foundation.respond_foundation_promoted_release_owner_handoff_v1(...)`

allows:

- accepted
- rejected
- clarification-requested

Only the isolated Shine Core capability may respond. The first response is immutable and authoritative for acknowledgement history; conflicting replay returns the original response.

## Acceptance means ownership only

Accepted work records `acknowledgesWorkOwnership: true` and `workOwnershipOnly: true`.

It explicitly does not grant Layer-38 approval, release-truth mutation, release rebind, incident-history mutation, runtime mutation, incident closure, promotion-trust changes, approval or execution authority.

## Immutable response receipt

Ledger:

`foundation.foundation_promoted_release_owner_handoff_responses`

Each response binds handoff ID/SHA, incident ID, owner route, Layer-66 semantic response-plan fingerprint, response state/reason/note, immutable JSON, SHA-256 and response time.

Owner access is via bounded functions only; the capability has no direct handoff/response table access.

## Currentness

`foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(...)`

keeps response history immutable but marks it stale whenever the underlying Layer-67 handoff is no longer current.

Recovery therefore does not erase acknowledgement history, but it prevents old ownership from being treated as current work.

## Acceptance coverage

CI proves:

- existing Shine Core role posture remains least privilege;
- Gateway/runtime cannot assume owner capability;
- one current handoff appears in the owner inbox;
- accepted response acknowledges ownership only;
- all mutation/approval/execution flags remain false;
- pending inbox empties after response;
- replay cannot overwrite the first response;
- response SHA verifies;
- recovery makes acknowledgement stale for current use;
- owner has no direct table access;
- service role cannot respond or directly insert;
- response history is append-only.

## Invariant

> Owning the work is not permission to perform the work. Layer 68 records responsibility, while Layer 38 and remediation approval/execution controls remain authoritative.
