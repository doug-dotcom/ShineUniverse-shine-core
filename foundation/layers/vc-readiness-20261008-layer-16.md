# VC readiness — layer 16: read/write separation

8 October 2026, Brisbane. Baseline 2d6173e22bea8f1b85dcf00e7b52247a0981993f.
After merge: 16/40 source-verified producer layers; 24 remain (60%).

## Enables VC

The new server route dispatcher accepts exactly {operation:'read',readRequest}. It refuses edits, uploads, deletes, missing/inferred operations, mixed envelopes and accessor fields before authority lookup or private preparation. It has no write handler or generic fallback. Nested edit payloads or write capability substitutions are also refused by the reused exact read-input gate.

Existing permission semantics already support a selected record read. This layer does not count that grant logic again: its addition is an explicit operation dispatch boundary for a consuming server route, so a valid read grant cannot select a mutation path. Actual read permission, freshness and in-flight release checks remain the existing guarded-read implementation.

## Ownership and limits

Foundation owns createVeteranCareReadDispatcher under foundation/onboarding/. VC Integrations & Security owns binding the actual consumer route, read-only credentials/data adapter and any separately authorised write/upload routes. It must never route mutations through this dispatcher or use read approval as write approval.

A trusted prepareResult callback must itself use read-only data access and perform no external disclosure before the final gate. This JavaScript boundary cannot sandbox callback side effects or undo a misconfigured callback's writes. No database-level read-only guarantee, record edit workflow, upload implementation or live consumer acceptance is claimed. Delegated scope-ready remains metadata only and cannot enter the self-read gate as authority.

No VC, SQL, Auth/Storage, credentials, model, UI or deployed runtime changes. CI adds the focused route suite. Receipt is a discoverable handover, not cross-chat acknowledgement.

## Evidence

6 new tests cover valid two-check reads, write/edit/upload/delete/unknown operation refusal before preparation, mixed envelopes/accessors, nested mutation payloads and write capabilities, missing grants/in-flight revocation and caller mutation during asynchronous verification.
240/240 local onboarding/runtime tests passed. Existing 16/16 synthetic access journey passed. git diff --check passed. Foundation and independent Defence CI required before merge.
Open: actual consuming route, data-adapter least privilege, hosted exact revision and authenticated read/write isolation proof.

Next: layer 17, audit event contract without clinical content.
