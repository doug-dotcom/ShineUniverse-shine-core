# Shine Universe Core

Shared contracts and platform standards for the Shine Universe.

## Shine Defence

`security/shine-defence/baseline-v1.json` is the canonical minimum security contract for Shine applications.

Individual apps keep a local certification profile that maps these shared controls to app-specific evidence. An app may display **Protected by Shine Defence** only when its release revision passes every required control in its declared profile.

The baseline is deliberately conservative: a control is certified only when there is concrete, testable evidence. New controls can be added without pretending they already exist.

### Canonical extension policies

Reusable Defence policies live under `security/shine-defence/policies/`. They define stronger trust-boundary rules that apps can adopt and certify when the feature exists:

- `external-link-v1.json` — reviewed external navigation and opener isolation.
- `untrusted-content-v1.json` — bounded parsing and safe handling of untrusted imported or generated content.
- `malware-quarantine-v1.json` — quarantine, scan and release controls for uploaded assets.
- `external-data-provenance-v1.json` — provider trust, freshness, attribution and fail-closed handling for third-party data.
- `collaborative-content-v1.json` — authorship, audience, approval and concurrency boundaries for shared human/AI content.
- `authenticated-session-hardening-v1.json` — server-side authentication authority, session expiry/rotation, CSRF protection, revocation and account-flow hardening.
- `ai-prompt-and-tool-boundaries-v1.json` — prompt trust separation, bounded model I/O, schema validation, least-privilege tools and provenance-preserving AI execution.
- `personal-financial-data-v1.json` — authentication, data integrity, import/backup safety, provenance and fail-closed controls for personal financial records.
- `wagering-trial-integrity-v1.json` — authenticated trial records, strategy/result provenance, deterministic reconciliation and fail-closed simulated wagering evaluation.
- `financial-research-provenance-v1.json` — source identity, dated evidence, unit/freshness validation, calculation provenance and fail-closed financial research.
- `sensitive-memory-governance-v1.json` — authenticated ownership, source permissions, privacy classification, redaction and fail-closed disclosure for sensitive personal memory.
- `exercise-companion-safety-v1.json` — participant scoping, health-data validation, reviewed AI proposals and clinical/progression boundaries for exercise companions.

### Canonical registry

`security/shine-defence/canonical-registry-v1.json` is the machine-readable authority for reviewed Defence artefacts. It pins each contract, policy and integration-kit release to its version and exact Git blob SHA. Core CI runs `verify-registry-v1.mjs` and fails if a registered artefact changes without an explicit registry update.

An extension policy existing in Core does **not** automatically certify an app. Each app still needs local, testable evidence before claiming that profile.
