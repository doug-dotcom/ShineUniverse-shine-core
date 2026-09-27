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

Core CI requires every accepted, superseded or dismissed candidate to have exactly one matching decision record, rejects decisions that predate candidate observation, and verifies superseded-candidate successor identity. Pending candidates are forbidden from carrying a decision. For checklist-backed final decisions, the decision also pins the exact checklist Git blob plus the checklist's registry identity. This preserves the human review artifact byte-for-byte after finalization while keeping certification authority exclusively in the canonical reviewed ledger plus exact receipt.

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

### Candidate supersession

`security/shine-defence/candidate-supersession-v1.json` defines the atomic replacement path when a newer release arrives while the same app already has a `pending_review` candidate. `supersede-candidate-v1.mjs` consumes one transaction containing the old candidate id, supersession provenance and a complete successor candidate-intake payload. It stages the old candidate as `superseded`, reuses the canonical intake validator to construct the successor, appends the matching superseded decision and commits the resulting queue/decision state together.

The helper never permits two pending candidates for one app, never carries checklist findings or authorization into the successor, and refuses to supersede an old checklist that a human has already approved or rejected. If review work exists but is still pending, the superseded decision fingerprints that exact checklist so it remains immutable historical evidence. `--apply` leaves certification, receipts and revocations untouched and restores both changed ledgers if any Defence gate fails.

### Structured human review

`security/shine-defence/review-checklist-v1.json` defines a non-authoritative review worksheet bound to one exact candidate and one exact canonical-registry snapshot. `generate-review-checklist-v1.mjs` derives checklist items directly from every claimed canonical policy requirement, copies the candidate evidence as reference material, and always generates `humanAuthorization.status = pending`. Canonical artefacts without a `requirements` array receive an explicit artefact-integrity review item rather than being treated as automatically satisfied.

A human reviewer may mark requirements `satisfied` or `not_satisfied`, cite candidate evidence ids and add bounded reviewer notes. Approval is valid only when every item is satisfied and the checklist contains an explicit reviewer id, reviewed timestamp and review summary. While a candidate is pending, `verify-review-checklists-v1.mjs` re-derives the checklist against the current canonical registry and rejects candidate, policy, registry, requirement or evidence drift. After a checklist-backed candidate is finalized, CI instead verifies the exact decision-pinned checklist bytes and human outcome metadata so later Defence-policy evolution does not rewrite historical review evidence.

First certification and re-certification now read only the canonical checklist at `security/shine-defence/review-checklists/<candidateId>.json`. They no longer accept a command-line authority, decision timestamp or free-form acceptance summary. The accepted decision inherits those fields from the independently validated human approval. A generated or merely pending checklist cannot authorize certification.

### Review workspace

`security/shine-defence/review-workspace-v1.json` defines the reviewer-facing workflow for completing a canonical checklist without hand-editing JSON. `review-workspace-v1.mjs` is read-only by default: it shows the candidate, evidence references, satisfied/not-satisfied/unreviewed counts and the next outstanding requirement.

A reviewer records one requirement at a time through a small JSON action file containing the item id, review state, evidence ids and/or reviewer notes. The workspace validates the proposed mutation against the exact candidate and current canonical registry before writing it. Approval or rejection is a separate explicit action: approval requires literal `APPROVE` confirmation and every item satisfied; rejection requires literal `REJECT` confirmation and at least one `not_satisfied` item. Finalized checklists are locked in workspace v1. Apply mode changes only the canonical checklist file and restores the previous version if checklist verification fails.

### Review evidence assistant

`security/shine-defence/review-evidence-assistant-v1.json` defines a strictly advisory evidence-mapping layer. `review-evidence-assistant-v1.mjs` compares each checklist requirement with only the bounded candidate evidence already copied into that checklist and writes a separate suggestion artifact under `security/shine-defence/review-evidence-suggestions/`. The deterministic engine records matched terms, a non-probabilistic score, a low/medium/high advisory confidence label and explicit evidence gaps; it retains at most three evidence leads per requirement.

Suggestion artifacts never edit checklist state, evidence references, reviewer notes or human authorization. `verify-review-evidence-suggestions-v1.mjs` recomputes the deterministic output and rejects candidate, checklist, registry, evidence or score drift. Historical suggestion artifacts remain valid after a candidate is later finalized. Review Workspace v1.1 displays validated suggestions beside the next outstanding requirement when available, but the reviewer must still explicitly record any evidence mapping before it affects the checklist.

### Review queue

`security/shine-defence/review-queue-v1.json` defines the read-only consolidated view of every `pending_review` candidate. `review-queue-v1.mjs` combines candidate identity, whether the app is already reviewed, checklist progress, human authorization, advisory evidence-assistance health and evidence-gap counts into one deterministic queue ordered by observation time.

Each queue item exposes one workflow state and one next action: generate a missing checklist, review the next requirement, explicitly approve/reject a completed checklist, run first certification/re-certification after approval, repair invalid checklist state, or run the guarded rejection finalizer for a human-rejected candidate. Advisory suggestion drift is surfaced separately and never blocks otherwise-valid human approval or certification readiness. The queue is read-only and can render either a reviewer-friendly summary or deterministic `--json` output.

### Rejection finalization

`security/shine-defence/rejection-finalization-v1.json` defines the fail-closed closure path for a human-rejected pending candidate. `finalize-rejection-v1.mjs` requires the exact canonical checklist to validate against the still-pending candidate and to contain explicit human rejection. It then changes only two authorities: the candidate becomes `dismissed` with the human rejection summary as `decisionReason`, and one matching dismissed review decision is appended.

Reviewer id, rejection timestamp and summary come only from the rejected checklist. The decision pins the exact checklist Git blob and registry identity, so later edits or registry changes cannot silently rewrite the historical rejection. The helper never changes the ecosystem reviewed ledger, certification receipt or revocation state. Apply mode runs candidate, decision, checklist, rejection-binding and queue verification and restores both mutated ledgers if any check fails.

### Defence operations controller

`security/shine-defence/operations-controller-v1.json` defines a read-only orchestration layer over the candidate lifecycle, Review Queue and canonical certification state. `operations-controller-v1.mjs` lists every app known to either the reviewed ecosystem ledger or candidate history exactly once, classifies its current Core workflow state, and identifies the exact guarded helper plus arguments appropriate for the next step when one exists.

Pending reviews take workflow precedence and preserve human-required boundaries from Review Queue. Approved reviews route to first-certification or re-certification helpers; rejected reviews route to the rejection finalizer. Reviewed apps with an exact receipt and no matching revocation are reported as canonically reviewed and idle, while exact reviewed-release revocations route toward intake of a replacement release. Missing canonical receipts fail closed with no automatic repair helper. The controller never invokes a mutating helper and never infers which commit is currently deployed; live deployment freshness remains a separate release-status check.

### Deployment observations

`security/shine-defence/deployment-observation-v1.json` defines bounded, non-authoritative observations of an app's deployed commit and Defence-profile blob. Observations are append-only in `deployment-observations-v1.json`; `record-deployment-observation-v1.mjs` adds observations without touching certification authority. `deployment-observations-v1.mjs` selects the latest observation deterministically and reuses the existing receipt-backed `release-status-v1` engine with the receipt's immutable registry snapshot and current revocation ledger.

Observed release status is translated into five estate-level deployment states: `protected`, `deployment_drift`, `profile_drift`, `revoked` and `needs_review`. Operations Controller v1.1 consumes those results. When an observation exists, observed deployment state takes precedence over idle canonical status; a revocation on an older reviewed release therefore does not mislabel a different observed deployment as revoked. Apps without an observation remain explicitly `unobserved` and are routed to the recorder rather than guessed. None of these observation tools certify, deploy, revoke or modify an app.

### Railway + GitHub deployment collectors

`security/shine-defence/deployment-sources-v1.json` is the non-secret source registry for automated observation collection. Each binding names a reviewed app plus its Railway project/environment/service and exact GitHub repository/profile path. `verify-deployment-sources-v1.mjs` requires those repository/profile identities to match the canonical reviewed ledger.

`collect-deployment-observations-v1.mjs` queries Railway for the latest successful deployment in each registered scope, takes Railway's exact deployment `commitHash`, and asks GitHub for the Defence-profile Git blob at that same commit. It converts those two independently sourced identities into the standard deployment-observation shape, deduplicates by Railway deployment id, and appends only new evidence. Railway/GitHub credentials remain runner-owned and are never stored in Core. The observation ledger is deliberately **not** pinned in the canonical code registry because it is append-only operational evidence; its schema and collector/evaluator code remain pinned and CI validates the ledger on every change.

The live source registry now covers ten canonically reviewed apps: `shine-daash`, `shine-ski`, `shine-translate`, `shine-my-money`, `shine-travel`, `punt-49`, `fiona-finance`, `project-l`, `shine-ai` and `project-rc`. Their observations were collected from Railway deployment metadata and GitHub commit-specific profile blobs rather than inferred from branch heads.

`security/shine-defence/deployment-coverage-v1.json` defines coverage accounting across the entire reviewed estate. `deployment-coverage-v1.mjs` reports `observed`, `mapped_unobserved`, `partial_service` and `unmapped` states. `shine-music` is explicitly recorded as `partial_service`: Railway currently exposes the `rivers-malware-scanner` subservice from the same repository, but that subservice is not treated as the full reviewed app deployment. Partial services do not count as full observation coverage.

### Review intake planner

`security/shine-defence/review-intake-planner-v1.json` defines a read-only bridge from observed `deployment_drift` to candidate-intake preparation. `plan-review-intake-v1.mjs` may prefill app/repository, deployed release SHA, profile path/blob, reviewed profile version and reviewed policy ids only when the deployed Defence-profile blob still exactly matches the reviewed profile. The generated draft deliberately contains `evidence: []` and no candidate observation timestamp, so it is not valid candidate-intake input and cannot create `pending_review` state.

If the deployed profile changed, the planner reports `profile_changed_requires_refresh` rather than inheriting stale profileVersion/policy claims. If a pending candidate already exists, the planner reports `pending_candidate_exists`. Materialization requires explicit bounded review evidence plus a candidate observation timestamp, then re-runs the canonical candidate-intake validator and prints ordinary intake JSON only; it never writes the review-candidate queue. Operations Controller v1.2 routes deployment drift through this planner instead of directly to candidate intake.

### Review evidence packs

`security/shine-defence/review-evidence-pack-v1.json` defines bounded GitHub compare material for a human reviewing one draftable deployment-drift release. `generate-review-evidence-pack-v1.mjs` binds the reviewed commit as compare base and the exact observed deployed commit as head, requires a forward-only `ahead` relationship, and records commit counts plus changed-file paths and numeric additions/deletions. Raw patches and file contents are never copied into Core.

The generator assigns deterministic review-focus labels such as `security_or_auth`, `api_or_server`, `database_or_migration`, `dependency_or_build`, `ci_or_deployment` and `tests` from paths only. These labels and change counts are navigation aids, not risk scores or findings. Every proposed evidence record is stamped `unreviewed` and `UNREVIEWED`; a human must inspect the pack and any underlying code/tests needed for judgement, then separately author the bounded review-evidence record used by the intake planner. Evidence packs never create candidates, satisfy checklist requirements or certify releases.

### Human diff review workspace

`security/shine-defence/human-diff-review-v1.json` defines the durable human judgement layer between an advisory evidence pack and candidate-intake evidence. `human-diff-review-v1.mjs` opens one current draftable app at a time and orders changed files with security/auth, API/server, database/migration, dependency/build and CI/deployment paths before tests and other files. Review state is stored separately from the generated pack and is bound to the exact reviewed commit, observed deployed commit and deployment observation.

A reviewer records each changed file as `reviewed_no_issue`, `reviewed_attention` or `reviewed_blocker` with optional bounded notes. Evidence cannot be accepted until every changed file has a human finding, and any blocker prevents acceptance. Final acceptance requires literal `ACCEPT EVIDENCE`, reviewer id, UTC review timestamp and bounded summary. Only then does the workspace emit a separate candidate-intake-compatible `security_diff_review` evidence record. That record still does not create a candidate, approve a checklist or certify a release; the Review Intake Planner and candidate intake remain separate guarded steps. Accepted review artifacts are immutable in workspace v1.

### Candidate intake readiness

`security/shine-defence/candidate-intake-readiness-v1.json` defines the final fail-closed bridge between accepted human diff-review evidence and candidate intake. `candidate-intake-readiness-v1.mjs` requires the accepted review and separate evidence record to bind the current deployment-drift identity exactly, re-derives the evidence record from the durable human review, rejects tampering or stale deployment identity, and then runs the canonical candidate-intake validator over the resulting payload.

A successful bridge result is `candidate_intake_ready` and includes the deterministic candidate-id preview plus the fully validated candidate-intake payload. It does **not** write `review-candidates-v1`. Operations Controller v1.3 may surface that ready state and point to `intake-review-v1.mjs --input <validated-candidate-intake.json> --apply`; that separate explicit apply remains the only action that can create `pending_review` state. With no accepted human diff reviews yet, the live readiness report correctly contains zero ready candidates.

### Defence Command Centre

`security/shine-defence/command-centre-v1.json` defines the read-only estate dashboard contract. `command-centre-v1.mjs` joins the existing Operations Controller, deployment coverage, deployment observations, Review Intake Planner, candidate-intake readiness and durable human diff-review progress into one deterministic row per canonically reviewed app.

Each row shows estate/certification state, deployment coverage, observed deployment identity/status, pre-candidate human-review progress, intake readiness/candidate preview when available, and the exact next action already selected by Operations Controller. The Command Centre deliberately does not recompute certification or release status and invokes no helper; missing data is shown explicitly rather than inferred. This makes it an operational projection, not a new authority.


An extension policy existing in Core does **not** automatically certify an app. Each app still needs local, testable evidence before claiming that profile.
