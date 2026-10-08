# VC readiness layer 33 — checkpoint failure

Baseline: cc2a6cd7a23f6d99e127d2f60e2eb866da0f4875 (layer 32 merged).
After merge: 33/40 complete; 7 remaining (17.5%).

## Behaviour

createVeteranCareCheckpointFailureGate composes the actual layer-32 resume gate and saves a new revision of its current server-owned checkpoint. Session, Companion user/link, consent, existing retry identity, task, recipient and unchanged checkpoint checks must succeed first. The candidate preserves all selection and operation identifiers; only revision advances by one and expiry is bounded by the freshly checked result deadline. Caller progress rows, revision overrides, credentials in storage, cached private results and permission assertions are refused.

The protected commit must atomically compare the expected revision before replacing the row. Foundation requires an exact committed acknowledgement and then an independent authoritative current-row readback matching every candidate field. Missing, conflicting, malformed, stale or changed acknowledgements/readbacks, expired deadlines, clock regression, overflow and adapter outages never report durableProgressConfirmed. A write timeout may have committed; it returns writeOutcome unconfirmed without an automatic retry or rollback. An uncertain save must not be reported as a definitely failed database write.

The prepared private read is discarded on both success and failure. No content or continuation callback is released. Success returns checkpoint-confirmed with frozen checkpoint ID/revision/stage/deadline metadata, durableProgressConfirmed true and requiresFreshResumeCheck true. Both outcomes keep resumePermitted false and modelDisclosurePermitted false. A confirmed progress row is never authority; subsequent work enters the existing fresh resume gate.

## Ownership and interfaces

Foundation owns strict acknowledgement/readback validation and fail-closed progress reporting. VC Integrations owns commitResumeCheckpoint({expectedRevision,checkpoint}) and authoritative getCurrentResumeCheckpoint storage. Commit returns exactly {status:'committed',checkpoint} only after durable atomic compare-and-swap success; a conflict or storage uncertainty must not return committed. Checkpoint fields retain layer-32's exact schema. Storage must prevent concurrent stale overwrites and protect resource identity metadata. No grants, tokens, private text, links or saved results are written.

Orchestration owns checkpoint save scheduling, task lifecycle, uncertainty reconciliation and operator presentation. The old checkpoint may remain unchanged after a failed save; any later use still requires layer-32 current authority checks. This layer does not revoke an old checkpoint, invent a replacement retry identity, claim exactly-once execution, provide leases or roll back an ambiguous write. Concurrent matching saves use the same expected revision; the adapter must allow at most one transition. Fresh checks are point-in-time and hold no distributed authority lock. Readback can already be superseded, in which case confirmation is withheld.

This source contract does not deploy storage or a checkpoint endpoint. Durable database compare-and-swap, authoritative readback consistency, live failure injection and actual scheduler wiring remain open. The gate performs a private selected read to exercise current authority, then suppresses its content; it supplies no business mutation or model continuation.

## Evidence

12 focused synthetic adapter tests cover confirmed save without disclosure; write failure with no retry; false/missing/mismatched/extra-field acknowledgements; acknowledgement without stored-row parity; timeout after a simulated committed write; readback outage/accessor refusal and redaction; cancelled task/withdrawn consent/missing retry before any write; expired/regressing/invalid clock; expiry during commit; revision overflow and caller authority refusal; competing compare-and-swap saves; and captured input selection.

383/383 local onboarding/runtime tests passed, including the joined synthetic AI/L proof. Diff check passed. Registered in Foundation CI; Foundation and independent Defence checks must pass before merge. All failure and durability evidence here uses synthetic in-memory adapters, not a live database.

Next: layer 34, credential references.
