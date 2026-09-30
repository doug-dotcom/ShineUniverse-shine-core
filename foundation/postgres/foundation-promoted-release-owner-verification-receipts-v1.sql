-- Foundation Layer 71: read-only Shine Core receipts for independent promotion-trust verification.
-- The owner may see Foundation's verified conclusion for its own handoff, but receives
-- no raw proof-ledger access and no authority to alter the conclusion.

create or replace function foundation.get_foundation_promoted_release_owner_verification_receipts_v1(
  p_environment text default 'production',
  p_limit integer default 25,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer71_receipts$
declare
  v_rec record;
  v_verification_status jsonb;
  v_handoff_status jsonb;
  v_response_status jsonb;
  v_evidence_status jsonb;
  v_items jsonb := '[]'::jsonb;
  v_receipt_count integer := 0;
  v_visible_count integer := 0;
  v_invalid_count integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'promoted-release-owner-verification-receipts-environment-invalid';
  end if;

  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'promoted-release-owner-verification-receipts-limit-invalid';
  end if;

  if p_as_of is null then
    raise exception 'promoted-release-owner-verification-receipts-time-invalid';
  end if;

  for v_rec in
    select
      h.handoff_id,
      h.incident_event_id,
      h.environment,
      h.owner_service_id,
      h.owner_component,
      h.cause_class,
      h.source_domain,
      h.response_plan_fingerprint,
      h.handoff_sha256,
      h.created_at as handoff_created_at,
      e.evidence_return_id,
      e.owner_reported_outcome,
      e.evidence_return_sha256,
      e.returned_at,
      v.verification_id,
      v.canonical_source_truth_state,
      v.canonical_source_truth_fingerprint,
      v.promotion_closure_state,
      v.promoted_release_state,
      v.promoted_release_available,
      v.promoted_release_sha256,
      v.trust_state,
      v.incident_state,
      v.verification_state,
      v.owner_claim_alignment,
      v.verification_proof_sha256,
      v.verified_at
    from foundation.foundation_promoted_release_owner_handoffs h
    join foundation.foundation_promoted_release_owner_evidence_returns e
      on e.handoff_id=h.handoff_id
    join foundation.foundation_promoted_release_owner_evidence_verifications v
      on v.evidence_return_id=e.evidence_return_id
    where h.environment=p_environment
      and h.owner_service_id='foundation.gateway'
      and h.owner_component='shine-core'
    order by v.verification_sequence desc
  loop
    v_verification_status :=
      foundation.get_promoted_release_owner_evidence_verification_status_v1(
        v_rec.evidence_return_id
      );

    if v_verification_status->>'state'<>'completed'
       or coalesce(v_verification_status->>'integrityVerified','false')<>'true'
       or v_verification_status->>'verificationId'
            is distinct from v_rec.verification_id::text then
      v_invalid_count := v_invalid_count+1;
      continue;
    end if;

    v_receipt_count := v_receipt_count+1;

    if v_visible_count<p_limit then
      v_handoff_status :=
        foundation.get_foundation_promoted_release_owner_handoff_status_v1(
          v_rec.handoff_id,p_as_of
        );

      v_response_status :=
        foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
          v_rec.handoff_id,p_as_of
        );

      v_evidence_status :=
        foundation.get_foundation_promoted_release_owner_evidence_status_v1(
          v_rec.handoff_id,p_as_of
        );

      v_items := v_items || jsonb_build_array(
        jsonb_build_object(
          'handoffId',v_rec.handoff_id,
          'incidentEventId',v_rec.incident_event_id,
          'environment',v_rec.environment,
          'ownerServiceId',v_rec.owner_service_id,
          'ownerComponent',v_rec.owner_component,
          'causeClass',v_rec.cause_class,
          'sourceDomain',v_rec.source_domain,
          'handoffState',coalesce(v_handoff_status->>'state','unknown'),
          'acknowledgementState',coalesce(v_response_status->>'state','unknown'),
          'evidenceState',coalesce(v_evidence_status->>'state','unknown'),
          'historical',
            coalesce(v_handoff_status->>'state','unknown')<>'current',
          'responsePlanFingerprint',v_rec.response_plan_fingerprint,
          'handoffSha256',v_rec.handoff_sha256,
          'evidenceReturnId',v_rec.evidence_return_id,
          'ownerReportedOutcome',v_rec.owner_reported_outcome,
          'evidenceReturnSha256',v_rec.evidence_return_sha256,
          'evidenceReturnedAt',v_rec.returned_at,
          'verificationId',v_rec.verification_id,
          'verificationState',v_rec.verification_state,
          'ownerClaimAlignment',v_rec.owner_claim_alignment,
          'canonicalSourceTruthState',v_rec.canonical_source_truth_state,
          'canonicalSourceTruthFingerprint',v_rec.canonical_source_truth_fingerprint,
          'promotionClosureState',v_rec.promotion_closure_state,
          'promotedReleaseState',v_rec.promoted_release_state,
          'promotedReleaseAvailable',v_rec.promoted_release_available,
          'promotedReleaseSha256',v_rec.promoted_release_sha256,
          'trustState',v_rec.trust_state,
          'incidentState',v_rec.incident_state,
          'verificationProofSha256',v_rec.verification_proof_sha256,
          'verifiedAt',v_rec.verified_at,
          'receiptState','verified',
          'integrityVerified',true,
          'ownerOutcomeAcceptedAsPromotionTrust',false,
          'incidentClosurePerformed',false,
          'promotionTrustChangedByReceipt',false,
          'releaseTruthMutationPerformed',false,
          'approvalGranted',false,
          'executionAuthorityGranted',false,
          'executesAction',false
        )
      );

      v_visible_count := v_visible_count+1;
    end if;
  end loop;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerVerificationReceipts',
      'shine-foundation/promoted-release-owner-verification-receipts-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'ownerServiceId','foundation.gateway',
    'ownerComponent','shine-core',
    'readerRole','shine_core_control_plane',
    'receiptCount',v_receipt_count,
    'visibleCount',v_visible_count,
    'invalidCount',v_invalid_count,
    'hasMore',v_receipt_count>v_visible_count,
    'items',v_items,
    'ownerOutcomeAcceptedAsPromotionTrust',false,
    'incidentClosurePerformed',false,
    'promotionTrustChangedByReceipt',false,
    'releaseTruthMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer71_receipts$;

revoke all on function foundation.get_foundation_promoted_release_owner_verification_receipts_v1(
  text,integer,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       service_role,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_owner_verification_receipts_v1(
  text,integer,timestamptz
) to shine_core_control_plane;
