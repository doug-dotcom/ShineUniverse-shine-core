# Shine Universe Core


## Shine Foundation

`foundation/` is the canonical home for the shared infrastructure that connects independent Shine applications into the Shine Universe.

Foundation currently contains three systems:

- **Shine Core** — app registry, shared contracts, permission orchestration and authorised app-to-app coordination.
- **Shine ID** — canonical Shine identity and authenticated-session boundary.
- **Shine Vault** — protected resources, per-app grants, consent, revocation and access auditing.

The governing rule is **connected by choice, independent by design**: Foundation enhances apps without becoming a mandatory dependency for their primary standalone purpose.

The current machine-readable Foundation contract is `foundation/contracts/foundation-v1.json`.


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

`security/shine-defence/ecosystem-profile-ledger-v1.json` records the exact reviewed **app commit**, Defence-profile blob/version, and canonical policies that profile claimed. It is deliberately a review snapshot: later app commits do not inherit certification automatically.

### Release-claim freshness

`security/shine-defence/release-claim-v1.json` defines whether a specific app revision may make the **current** Protected by Shine Defence claim. A matching active revocation is `revoked_release` and overrides reviewed status. Otherwise only an exact reviewed commit with the exact reviewed Defence-profile blob is `reviewed_release`; later commits are `unreviewed_revision`, changed profiles on the reviewed commit are `profile_drift`, and apps absent from the ledger are `uncertified`.

The deterministic assessor lives at `security/shine-defence/integration-kit/assess-release-claim-v1.mjs`.

### Certification receipts

`security/shine-defence/certification-receipt-v1.json` defines the portable proof carried by a reviewed release. Core stores one receipt per reviewed app under `security/shine-defence/receipts/`; each receipt binds the app id/repository, exact reviewed commit, exact Defence-profile blob/version, canonical policy ids, canonical registry identity and release-claim contract identity.

Receipts are verified in Core CI against the ecosystem ledger and the **immutable registry snapshot named by the receipt's registry blob SHA**. Snapshots live under `security/shine-defence/registry-snapshots/`, so later additions to the live registry do not invalidate historical receipts.

### Revocation

`security/shine-defence/certification-revocation-v1.json` defines the append-only kill-switch for an exact reviewed release. Active records live in `security/shine-defence/revocations-v1.json`. Revocation removes the **current** badge claim but does not delete the historical certification receipt; restoring a badge requires a new reviewed release and receipt.

An extension policy existing in Core does **not** automatically certify an app. Each app still needs local, testable evidence before claiming that profile.
