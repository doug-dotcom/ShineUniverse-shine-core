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

### App/deployment status

`security/shine-defence/release-status-v1.json` defines the portable consumer-side status model. `evaluate-release-status-v1.mjs` combines a release receipt, the current app commit/profile identity, the receipt's immutable registry snapshot and the current revocation ledger into one display-safe state. Only `reviewed_release` may show the current **Protected by Shine Defence** badge.

### Shared app consumer

`security/shine-defence/integration-kit/consumer-v1.mjs` is the canonical Node consumer for receipt-backed app/deployment status. It fails closed on malformed proof material and requires an explicitly current revocation authority before an exact reviewed release may display the green Defence badge.

### Review candidate queue

`security/shine-defence/review-candidate-v1.json` defines the non-authoritative evidence bundle used to ask for review of an exact app release. The queue lives at `security/shine-defence/review-candidates-v1.json` and preserves pending, accepted, superseded and dismissed candidate history.

A candidate **never grants the badge**. Only the canonical ecosystem review ledger plus an exact certification receipt can make a release `reviewed_release`. Core CI verifies accepted candidates exactly match both of those authorities, limits each app to one pending candidate, validates canonical policy ids and rejects obvious secret material in evidence fields.

### Review decision ledger

`security/shine-defence/review-decision-v1.json` defines the separate decision record required when a review candidate leaves `pending_review`. Final decisions live in `security/shine-defence/review-decisions-v1.json` and are checked independently from the candidate queue.

Core CI requires every accepted, superseded or dismissed candidate to have exactly one matching decision record, rejects decisions that predate candidate observation, and verifies superseded-candidate successor identity. Pending candidates are forbidden from carrying a decision. This prevents a queue status field from becoming its own evidence while preserving the rule that only the canonical reviewed ledger plus an exact receipt grants the current Defence badge.

Accepted candidates are historical final outcomes. When a later release is reviewed, the older accepted record remains accepted rather than being rewritten as superseded; `superseded` is reserved for a candidate replaced before review completed.

### Atomic review promotion

`security/shine-defence/review-promotion-v1.json` defines the fail-closed promotion unit joining candidate state, the canonical reviewed ledger, the current certification receipt and the independent review decision.

Once an app has review-candidate history, Core CI requires its current reviewed identity to match exactly one accepted candidate, requires that candidate to retain exactly one accepted decision, and requires the app's current receipt to match the same release/profile/policy identity. Partial promotions fail even when the individual files are syntactically valid. Legacy reviewed apps remain valid until they enter the candidate workflow.

### Review promotion helper

`security/shine-defence/integration-kit/promote-review-v1.mjs` prepares an existing app's re-certification as one controlled operation. It promotes exactly one `pending_review` candidate, advances the canonical reviewed ledger, replaces that app's current certification receipt, appends the independent accepted decision, and creates the immutable current-registry snapshot when needed.

The helper is dry-run by default. It requires the candidate's canonical structured review checklist to contain explicit human approval before it can proceed. `--apply` performs atomic per-file replacement, runs the Defence registry/ledger/receipt/candidate/decision/checklist/promotion gates, and restores every touched file if verification fails. It handles re-certification only; first-time certification uses the separate onboarding helper below.

### First certification onboarding

`security/shine-defence/first-certification-v1.json` defines the bootstrap rules for a brand-new app. Before first certification, the app may exist in the review queue as pending, dismissed or superseded history while remaining absent from the reviewed ledger, receipts and accepted decisions. That staged state never grants the Defence badge.

`security/shine-defence/integration-kit/onboard-review-v1.mjs` accepts exactly one existing `pending_review` candidate for an app with no prior reviewed-ledger entry, receipt or accepted decision, but only after its canonical structured review checklist contains explicit human approval. It creates the initial reviewed-ledger entry, exact certification receipt, accepted decision and immutable current-registry snapshot as one guarded operation. Reviewer identity, reviewed timestamp and decision summary come from the approved checklist. The command is dry-run by default; `--apply` verifies the complete Defence state and restores every touched file if any gate fails.

### Candidate intake

`security/shine-defence/candidate-intake-v1.json` defines the front-door rules for constructing a `pending_review` candidate from an exact app release, Defence-profile identity, canonical policy claims and bounded evidence. Candidate ids are deterministic (`appId` plus the first 12 characters of the release SHA), duplicate or conflicting queue state fails closed, and intake never mutates the reviewed ledger, receipts, decisions or revocations.

`security/shine-defence/integration-kit/intake-review-v1.mjs` consumes one reviewable JSON input file and is dry-run by default. `--apply` writes only the candidate queue, then runs the registry, candidate and promotion-state verifiers; the queue file is restored if any gate fails. Evidence acceptance validates structure and queue consistency, not the truth of external claims.

### Structured human review

`security/shine-defence/review-checklist-v1.json` defines a non-authoritative review worksheet bound to one exact candidate and one exact canonical-registry snapshot. `generate-review-checklist-v1.mjs` derives checklist items directly from every claimed canonical policy requirement, copies the candidate evidence as reference material, and always generates `humanAuthorization.status = pending`. Canonical artefacts without a `requirements` array receive an explicit artefact-integrity review item rather than being treated as automatically satisfied.

A human reviewer may mark requirements `satisfied` or `not_satisfied`, cite candidate evidence ids and add bounded reviewer notes. Approval is valid only when every item is satisfied and the checklist contains an explicit reviewer id, reviewed timestamp and review summary. `verify-review-checklists-v1.mjs` re-derives the canonical requirements and rejects candidate, policy, registry, requirement or evidence drift.

First certification and re-certification now read only the canonical checklist at `security/shine-defence/review-checklists/<candidateId>.json`. They no longer accept a command-line authority, decision timestamp or free-form acceptance summary. The accepted decision inherits those fields from the independently validated human approval. A generated or merely pending checklist cannot authorize certification.

### Review workspace

`security/shine-defence/review-workspace-v1.json` defines the reviewer-facing workflow for completing a canonical checklist without hand-editing JSON. `review-workspace-v1.mjs` is read-only by default: it shows the candidate, evidence references, satisfied/not-satisfied/unreviewed counts and the next outstanding requirement.

A reviewer records one requirement at a time through a small JSON action file containing the item id, review state, evidence ids and/or reviewer notes. The workspace validates the proposed mutation against the exact candidate and current canonical registry before writing it. Approval or rejection is a separate explicit action: approval requires literal `APPROVE` confirmation and every item satisfied; rejection requires literal `REJECT` confirmation and at least one `not_satisfied` item. Finalized checklists are locked in workspace v1. Apply mode changes only the canonical checklist file and restores the previous version if checklist verification fails.

### Review evidence assistant

`security/shine-defence/review-evidence-assistant-v1.json` defines a strictly advisory evidence-mapping layer. `review-evidence-assistant-v1.mjs` compares each checklist requirement with only the bounded candidate evidence already copied into that checklist and writes a separate suggestion artifact under `security/shine-defence/review-evidence-suggestions/`. The deterministic engine records matched terms, a non-probabilistic score, a low/medium/high advisory confidence label and explicit evidence gaps; it retains at most three evidence leads per requirement.

Suggestion artifacts never edit checklist state, evidence references, reviewer notes or human authorization. `verify-review-evidence-suggestions-v1.mjs` recomputes the deterministic output and rejects candidate, checklist, registry, evidence or score drift. Historical suggestion artifacts remain valid after a candidate is later finalized. Review Workspace v1.1 displays validated suggestions beside the next outstanding requirement when available, but the reviewer must still explicitly record any evidence mapping before it affects the checklist.

### Review queue

`security/shine-defence/review-queue-v1.json` defines the read-only consolidated view of every `pending_review` candidate. `review-queue-v1.mjs` combines candidate identity, whether the app is already reviewed, checklist progress, human authorization, advisory evidence-assistance health and evidence-gap counts into one deterministic queue ordered by observation time.

Each queue item exposes one workflow state and one next action: generate a missing checklist, review the next requirement, explicitly approve/reject a completed checklist, run first certification/re-certification after approval, repair invalid checklist state, or finalize a human-rejected candidate. Advisory suggestion drift is surfaced separately and never blocks otherwise-valid human approval or certification readiness. The queue is read-only and can render either a reviewer-friendly summary or deterministic `--json` output.

An extension policy existing in Core does **not** automatically certify an app. Each app still needs local, testable evidence before claiming that profile.
