# Foundation Layer 47 — Dependency remediation proposal

**Status:** LIVE

Layer 47 turns an active readiness incident into a bounded, integrity-linked remediation proposal without granting approval or execution authority.

Production proposal:

- ID: `c8d367d6-8831-41f8-a2c3-9479dc3d10d7`
- SHA-256: `6c674244a19f8a19f0f5b073cce34ac9bb7f74ab1897d628e60b81afcb5a18f2`
- state: current
- integrity: verified
- approval granted: false
- execution authority granted: false

It is bound to the current readiness incident event and semantic condition fingerprint.

Affected scopes:

- context operations
- control operations
- credential operations
- identity operations
- permission operations
- protected operations

For each scope the proposal permits evidence collection, upstream dependency identification, preparation of upstream remediation, and fresh readiness verification.

It explicitly prohibits:

- Foundation canonical-truth mutation
- Foundation release rebind
- safe-mode bypass
- automatic unapproved repair

The proposal becomes stale when the active incident event or semantic condition changes.

Foundation CI run `36424540723` passed the Layer-47 schema and complete downstream chain.

Security advisors report no Layer-47 findings.

## Invariant

> A remediation proposal may describe work. It does not approve that work and it does not execute that work.
