# VC readiness — layer 13: stale-grant cache rejection

8 October 2026, Brisbane. Source baseline 908d3d0c2e748f599971091c3647352565fe6090.
After successful merge: 13/40 source-verified Foundation producer layers; 27 remain (67.5%). Live consumer acceptance is separate.

## Enables Veteran Care

createVeteranCareFreshPermissionEvaluator composes the existing identity/session/exact resource/purpose/finite grant evaluator with mandatory independent current permission-revision checks. A cached active grant snapshot cannot return allow if its revision differs from current authoritative state. Missing, malformed, cross-owner/app or unavailable revision evidence also withholds permission; no cached-allow fallback.

Context must include permissionSnapshot {appId,ownerShineId,revision}, with exact three plain data fields, matching the verified request and a nonnegative safe integer revision.
Mandatory getCurrentPermissionRevision({appId,ownerShineId}) returns the same exact tuple from independent uncached authoritative state on every evaluation. Equal revisions permit normal grant evaluation; either direction of mismatch rejects the snapshot. A timestamp, feed acknowledgement, pending-age hint or device clock cannot substitute.
Named factory fixes the freshness hook and retains the mandatory expiry policy; caller configuration cannot override it. Previous named factories retain their narrower contracts and do not certify freshness.

## Consumer projection requirements

permissionSnapshot must be stamped with the complete coherent context when produced; it must not be relabelled with a newer revision after loading cached grants. Current authority must be independent of that cache. Relevant grant issue/revocation/permission changes must advance the authoritative revision atomically with their state; revisions must not be recycled or regress. The consumer must define and persist the revision domain, including any other authority fields represented by that permission context. Existing projections are not automatically compliant; no SQL or consumer adapter is changed here.
This wrapper captures bounded plain JSON data before awaiting current revision. Nested grants and snapshot stamps cannot mutate into an allow during that await. Non-data accessors, cycles, sparse/custom arrays, excessive depth/node counts and arrays beyond 100 entries withhold permission. Projection should normalise data; undefined, functions, Date instances and custom objects are excluded.
Success still has executionPerformed false and the approved grant deadline. Freshness is point-in-time admission, not a signed execution ticket. A change after the current revision read remains an operation/delivery recheck obligation (row 14). Do not store or replay a prior allow as authority.

## Reconciliation and ownership

Existing uncached permission-context calls and grant lifecycle rules remain reused. Existing revocation health default is 900 seconds observe-only; it is not equivalent to revision equality and does not close this VC gap. No generic SQL, gateway or revocation policy changed.
Foundation owns the additive freshness evaluator plus an optional trusted freshness hook in veteran-care-permission-v1.mjs. Branch foundation/vc-readiness-layer-13. Fresh-main workflow adds only the new suite.
VC Integrations & Security owns coherent snapshot stamping, independently persisted current revision, atomic advancement, consumer wiring, actual cache behaviour and hosted withdrawal acceptance.
Shine AI owns its consumer/context caches and model/caller controls. Passing this Foundation guard does not certify AI cache invalidation or private retrieval. No VC/AI files, credentials or database/Auth/Storage writes.

Reviewed current Foundation permission source and revocation-freshness-policy-v1.sql. VC tree 32b7627f5d347f914089925de60cbd6ed6c75be6; room-interface blob f7c9593f09a6a8eb7c531c942bf27f63d6dd85d4 is unchanged from the previously read ownership contract. AI e38b95769442bca90315e2719e6b7f5288aeec74 is unchanged from prior review. Repository handover is discoverable coordination, not another room's acknowledgement.

## Verification and open gates

13 new synthetic tests passed; full local onboarding/runtime suite 192/192 passed; joined access proof 16/16 still passed.
Checks include same-evaluator allow then cached-active refusal after revision change, revision regression, missing/forged/cross-owner/app tuples, current authority outage, ignored caller freshness, cached object and stamp mutation during await, preserved expiry/purpose/revocation rules, zero initial revision, input nonmutation, malformed/cyclic/accessor/sparse/oversized snapshots and fixed-hook constructor enforcement.
CI includes new suite; full Foundation and independent Defence success required before merge.
Open: real persisted revision domain/atomic producer, independent current projection, consumer cache wiring, hosted revocation and exact deployed acceptance. No live cache invalidation or consumer enforcement proof claimed.
Next: layer 14, in-flight permission recheck.
