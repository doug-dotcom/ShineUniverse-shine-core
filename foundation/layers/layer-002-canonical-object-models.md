# Foundation Layer 2 — Canonical object models

**Status:** Complete  
**Scope:** Core + ID + Vault

Layer 2 turns the Foundation v1 concepts into machine-readable objects that every connected Shine app can target consistently.

## Added objects

### App Manifest
`schemas/app-manifest-v1.schema.json`

Defines a Shine app's stable identity, version, primary purpose, supported operating modes and the Foundation scopes it may request.

Important: requested scopes are declarations, not grants.

### Shine Identity
`schemas/shine-identity-v1.schema.json`

Defines the canonical cross-Universe `shineId`, account lifecycle and authentication-provider bindings.

Authorisation must be server-verified. User-editable metadata is explicitly non-authoritative.

### Vault Resource
`schemas/vault-resource-v1.schema.json`

Defines the protected-resource envelope: owner, category, sensitivity, provenance, optional opaque storage reference and integrity metadata.

Every Vault resource requires a matching grant before another app may access it.

## Layer invariants

- Every app manifest includes standalone mode.
- Every connected app declares the minimum scopes it may request.
- Scope declaration never equals permission.
- `shineId` is the cross-Universe subject identifier.
- Provider-specific auth subjects map to `shineId`; they do not replace it.
- User-editable metadata cannot grant privileges.
- Vault resources are owned by one `shineId`.
- Vault access is grant-gated by default.
- Vault storage internals remain opaque to consuming apps.

## Next layer

Layer 3 will define the permission/grant model that joins these objects together: app + identity + resource + purpose + expiry + revocation + audit decision.
