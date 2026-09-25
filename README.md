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

An extension policy existing in Core does **not** automatically certify an app. Each app still needs local, testable evidence before claiming that profile.
