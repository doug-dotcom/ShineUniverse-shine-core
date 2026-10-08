# VC readiness layer 36 — recovery inventory

Baseline: 809dfc4e540cc7ae485f5c3851b13161e10fd61e (layer 35 merged).
After merge: 36/40 complete; 4 remaining (10%).

## Behaviour

The source inventory defines nine required recovery areas and their ownership: release source (Foundation); database schema and records (VC Integrations); revocation ledger (Foundation/Defence); storage objects (VC Integrations); identity configuration and credential custody (VC Integrations/Security); retry/checkpoints (VC Orchestration); and selected Companion memory (L). Recovery method is explicit: restore, reconcile, rebuild or reissue. This is a dependency inventory, not a claim that Foundation controls or backs up another room's data.

vc-readiness-20261008-layer-36-inventory.json records the exact source baseline. Every backup-evidence status is not-inspected and every approved maximum backup-age target is null. backupCoverageVerified and restoreVerified are false. No actual backup, vault or deployed database was inspected, copied or restored.

createVeteranCareRecoveryInventory adds protected metadata inspection. It authenticates a current VC recovery operator before evidence lookups, reads an inventory generation, inspects each fixed asset, then rechecks the generation and operator. Null asset evidence becomes an explicit missing gap. Missing/unverified metadata, unapproved targets and backups at or beyond their approved age boundary remain gaps. Scope/owner/boundary/method/generation mismatches, malformed metadata, accessors, future or reversed timestamps, failed adapters, withdrawn operator and invalid/regressing clocks withhold the inventory.

An available evidence row must have an opaque artifact ID, SHA-256 metadata, captured/verified timestamps and explicit live or synthetic mode. These values are trusted collector metadata; Foundation does not download the artifact or independently recompute its checksum in this layer. metadataCoverageComplete only describes validated metadata coverage within supplied approved targets. Even complete coverage always returns restorePermitted false, restoreVerified false, liveRestoreVerified false and requiresIsolatedRestoreProof true. No recovered grant, token, task or checkpoint becomes authority.

## Ownership and interfaces

Foundation owns fixed coverage, exact metadata validation and explicit gap reporting. Recovery evidence collection, encrypted backup custody, artifact digest verification, restore retention and service/operator identity enforcement belong to the named owners. L remains responsible for its separate memory boundary. A protected collector must corroborate artifact existence, integrity and capture/verification times before returning available; a filename, row count or successful API ping is insufficient.

Input is exactly {authContext:{serviceToken}}. verifyRecoveryOperator receives {authContext,foundationAppId:'shine.veteran-care',purpose:'veteran-care.recovery-inventory'} and returns exactly {verified,foundationAppId,purpose,servicePrincipalId,revision,validUntil}; principal ID is a bounded vc-recovery-* server identity. It must authenticate the real service and current operator policy independently. Operator metadata must match and remain unexpired through collection.

getCurrentRecoveryInventoryRevision({foundationAppId}) returns exactly {foundationAppId,revision}. getRecoveryAssetEvidence receives exactly {foundationAppId,inventoryRevision,assetId,owner,sourceBoundary,recoveryMethod} and returns those fields plus {status,evidenceMode,artifactRef,sha256,capturedAt,verifiedAt}, or null for missing. Status is available/missing/unverified; non-available rows carry null artifact/digest/timestamps. Evidence mode is live/synthetic/unknown, with unknown forbidden for available. The protected collector must ensure generation consistency across all assets; changes increment generation rather than silently mix snapshots.

Constructor recoveryTargets maps every fixed asset ID to an independently approved positive maximum backup age in milliseconds, or explicit null if unapproved. These are metadata freshness limits, not measured recovery time or a guaranteed recovery point. The tests' targets are synthetic examples; no operational target is approved here. Runtime outputs contain protected artifact IDs/digests but no archive URLs, signed links, raw dumps, tokens, key material or clinical content. They belong only in trusted operator tooling, never public/browser/model output.

The inventory is read-only. It cannot download backups, resolve credentials, execute restore, reissue keys, overwrite production or change consent. Point-in-time revision/operator checks do not hold a distributed snapshot lock. Actual backup coverage, approved targets, recovery-time measurements, live operator/collector wiring and isolated restore proof remain open. Layers 37/38 own isolated restore evidence and revocation continuity; layer 39 owns exact release/rollback evidence. Existing Foundation recovery-authorisation contracts are not changed or credited again.

## Evidence

12 focused synthetic tests cover immutable complete metadata without restore certification; each absent asset; unknown targets and unverified rows; binding/private-field refusal; malformed/future/reversed dates; exact backup-age boundary; generation change/operator withdrawal; operator identity/purpose/expiry; outages/accessors/caller overrides; captured targets/input and explicit modes; collection-time expiry/clock regression; and saved inventory coverage with all evidence uninspected.

419/419 local onboarding/runtime tests passed, including the joined synthetic AI/L proof. Diff check passed. Registered in Foundation CI; Foundation and independent Defence checks must pass before merge. A fixture labelled live tests mode preservation only; it supplies no live backup or restore evidence.

Next: layer 37, isolated database restore.
