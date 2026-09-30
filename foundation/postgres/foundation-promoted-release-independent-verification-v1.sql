-- Foundation Layer 70: independent verification of owner-reported promotion-trust evidence.
-- Owner evidence is admission to measure again. It is never an input to the
-- canonical recovery verdict and can never close an incident or mutate release truth.

create table foundation.foundation_promoted_release_owner_evidence_verifications (
  verification_sequence bigint generated always as identity primary key,
  verification_id uuid not null unique default gen_random_uuid(),
  evidence_return_id uuid not null unique
    references foundation.foundation_promoted_release_owner_evidence_returns(evidence_return_id),
  handoff_id uuid not null
    references foundation.foundation_promoted_release_owner_handoffs(handoff_id),
  response_id uuid not null
    references foundation.foundation_promoted_release_owner_handoff_responses(response_id),
  incident_event_id uuid not null
    references foundation.foundation_promoted_release_incident_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  owner_reported_outcome text not null
    check (
      owner_reported_outcome in (
        'resolved','improved','unchanged','worsened','inconclusive'
      )
    ),
  source_evidence_return_sha256 text not null
    check (source_evidence_return_sha256 ~ '^[a-f0-9]{64}$'),
  canonical_source_truth_state text not null,
  canonical_source_truth_fingerprint text
    check (
      canonical_source_truth_fingerprint is null
      or canonical_source_truth_fingerprint ~ '^[a-f0-9]{32}$'
    ),
  promotion_closure_state text not null,
  promoted_release_state text not null,
  promoted_release_available boolean not null,
  promoted_release_sha256 text
    check (
      promoted_release_sha256 is null
      or promoted_release_sha256 ~ '^[a-f0-9]{64}$'
    ),
  trust_state text not null,
  incident_state text not null,
  verification_state text not null
    check (verification_state in ('recovered','impaired','indeterminate')),
  owner_claim_alignment text not null
    check (owner_claim_alignment in ('agrees','disagrees','inconclusive')),
  verification_proof jsonb not null
    check (jsonb_typeof(verification_proof)='object'),
  verification_proof_sha256 text not null
    check (verification_proof_sha256 ~ '^[a-f0-9]{64}$'),
  verified_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.foundation_promoted_release_owner_evidence_verifications
  enable row level security;

create policy foundation_runtime_promoted_release_evidence_verifications_select
on foundation.foundation_promoted_release_owner_evidence_verifications
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_promoted_release_owner_evidence_verifications
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.foundation_promoted_release_owner_evidence_verifications
  to foundation_runtime,service_role;

create index foundation_promoted_release_evidence_verifications_handoff_idx
  on foundation.foundation_promoted_release_owner_evidence_verifications(
    handoff_id,verified_at desc,verification_sequence desc
  );

create index foundation_promoted_release_evidence_verifications_response_idx
  on foundation.foundation_promoted_release_owner_evidence_verifications(
    response_id,verified_at desc,verification_sequence desc
  );

create index foundation_promoted_release_evidence_verifications_incident_idx
  on foundation.foundation_promoted_release_owner_evidence_verifications(
    incident_event_id,verified_at desc,verification_sequence desc
  );

create trigger foundation_promoted_release_evidence_verifications_append_only
before update or delete
on foundation.foundation_promoted_release_owner_evidence_verifications
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.evaluate_foundation_promoted_release_independent_recovery_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer70_evaluate$
declare
  v_canonical jsonb;
  v_closure jsonb;
  v_promoted jsonb;
  v_trust jsonb;
  v_incident jsonb;
  v_state text;
  v_reason text;
  v_recovered boolean := false;
  v_indeterminate boolean := false;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_observation_max_age_seconds<60
     or p_observation_max_age_seconds>3600 then
    raise exception 'promoted-release-independent-recovery-input-invalid';
  end if;

  v_canonical :=
    foundation.get_foundation_canonical_source_truth_v1(
      p_environment,p_as_of
    );

  v_closure :=
    foundation.get_foundation_release_promotion_closure_status_v1(
      p_environment,p_as_of
    );

  v_promoted :=
    foundation.get_foundation_promoted_release_v1(
      p_environment,p_as_of
    );

  v_trust :=
    foundation.get_foundation_promoted_release_observation_summary_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_incident :=
    foundation.get_foundation_promoted_release_incident_summary_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_recovered :=
    v_canonical->>'state'='pass'
    and v_closure->>'state'='closed'
    and v_closure->>'releaseClosed'='true'
    and v_closure->>'integrityVerified'='true'
    and v_closure->>'receiptCurrent'='true'
    and v_promoted->>'state'='promoted'
    and v_promoted->>'available'='true'
    and v_promoted->>'promotionClosureState'='closed'
    and v_promoted->>'promotedReleaseSha256' ~ '^[a-f0-9]{64}$'
    and v_trust->>'state'='normal'
    and v_trust->>'observationFresh'='true'
    and v_trust->>'observationMatchesLive'='true'
    and v_incident->>'state'='normal'
    and coalesce((v_incident->>'activeIncidentCount')::integer,0)=0
    and coalesce((v_incident->>'watchCount')::integer,0)=0;

  v_indeterminate :=
    v_canonical->>'state' is null
    or v_closure->>'state' is null
    or v_promoted->>'state' is null
    or v_trust->>'state' is null
    or v_incident->>'state' is null
    or v_trust->>'state'='unknown'
    or v_trust->>'observationFresh'='false';

  if v_recovered then
    v_state := 'recovered';
    v_reason := 'independent-promotion-recovery-confirmed';
  elsif v_indeterminate then
    v_state := 'indeterminate';
    v_reason := 'independent-promotion-evidence-indeterminate';
  else
    v_state := 'impaired';
    v_reason := 'independent-promotion-still-impaired';
  end if;

  return jsonb_build_object(
    'foundationPromotedReleaseIndependentRecoveryEvaluation',
      'shine-foundation/promoted-release-independent-recovery-evaluation-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'verificationState',v_state,
    'reasonCode',v_reason,
    'canonicalRecoveryObserved',v_state='recovered',
    'checks',jsonb_build_object(
      'canonicalSourceTruthPass',v_canonical->>'state'='pass',
      'promotionClosureClosed',
        v_closure->>'state'='closed'
        and v_closure->>'releaseClosed'='true'
        and v_closure->>'integrityVerified'='true'
        and v_closure->>'receiptCurrent'='true',
      'promotedReleaseAvailable',
        v_promoted->>'state'='promoted'
        and v_promoted->>'available'='true',
      'liveObservationNormal',
        v_trust->>'state'='normal'
        and v_trust->>'observationFresh'='true'
        and v_trust->>'observationMatchesLive'='true',
      'incidentLifecycleNormal',
        v_incident->>'state'='normal'
        and coalesce((v_incident->>'activeIncidentCount')::integer,0)=0
        and coalesce((v_incident->>'watchCount')::integer,0)=0
    ),
    'canonicalSourceTruth',v_canonical,
    'promotionClosure',v_closure,
    'promotedRelease',v_promoted,
    'promotionTrust',v_trust,
    'incident',v_incident,
    'ownerEvidenceUsedAsCanonicalInput',false,
    'ownerOutcomeAcceptedAsPromotionTrust',false,
    'incidentClosurePerformed',false,
    'mutatesAuthoritativeTruth',false
  );
end;
$layer70_evaluate$;

revoke all on function foundation.evaluate_foundation_promoted_release_independent_recovery_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_foundation_promoted_release_independent_recovery_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.run_promoted_release_owner_evidence_verification_v1(
  p_evidence_return_id uuid,
  p_verified_at timestamptz default now(),
  p_max_evidence_age_seconds integer default 900,
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer70_verify$
declare
  v_evidence foundation.foundation_promoted_release_owner_evidence_returns%rowtype;
  v_existing foundation.foundation_promoted_release_owner_evidence_verifications%rowtype;
  v_evidence_status jsonb;
  v_independent jsonb;
  v_alignment text;
  v_doc jsonb;
  v_doc_hash text;
  v_verification_id uuid;
begin
  if p_evidence_return_id is null then
    raise exception 'promoted-release-evidence-verification-id-required';
  end if;

  if p_verified_at is null
     or p_verified_at<now()-interval '5 minutes'
     or p_verified_at>now()+interval '5 minutes' then
    raise exception 'promoted-release-evidence-verification-time-invalid';
  end if;

  if p_max_evidence_age_seconds<60
     or p_max_evidence_age_seconds>3600 then
    raise exception 'promoted-release-evidence-verification-max-age-invalid';
  end if;

  if p_observation_max_age_seconds<60
     or p_observation_max_age_seconds>3600 then
    raise exception 'promoted-release-evidence-verification-observer-age-invalid';
  end if;

  select * into v_evidence
  from foundation.foundation_promoted_release_owner_evidence_returns
  where evidence_return_id=p_evidence_return_id;

  if v_evidence.evidence_return_id is null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceVerification',
        'shine-foundation/promoted-release-owner-evidence-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-evidence-not-found',
      'independentVerification',true,
      'ownerOutcomeAcceptedAsPromotionTrust',false,
      'sourceEvidenceUsedAsTriggerOnly',true,
      'incidentClosurePerformed',false,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  select * into v_existing
  from foundation.foundation_promoted_release_owner_evidence_verifications
  where evidence_return_id=v_evidence.evidence_return_id;

  if v_existing.verification_id is not null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceVerification',
        'shine-foundation/promoted-release-owner-evidence-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'verificationId',v_existing.verification_id,
      'evidenceReturnId',v_existing.evidence_return_id,
      'verificationState',v_existing.verification_state,
      'ownerReportedOutcome',v_existing.owner_reported_outcome,
      'ownerClaimAlignment',v_existing.owner_claim_alignment,
      'verificationProofSha256',v_existing.verification_proof_sha256,
      'independentVerification',true,
      'ownerOutcomeAcceptedAsPromotionTrust',false,
      'sourceEvidenceUsedAsTriggerOnly',true,
      'incidentClosurePerformed',false,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  v_evidence_status :=
    foundation.get_foundation_promoted_release_owner_evidence_status_v1(
      v_evidence.handoff_id,p_verified_at
    );

  if v_evidence_status->>'state'<>'current'
     or coalesce(v_evidence_status->>'integrityVerified','false')<>'true'
     or v_evidence_status->>'evidenceReturnId'
        is distinct from v_evidence.evidence_return_id::text then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceVerification',
        'shine-foundation/promoted-release-owner-evidence-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-evidence-not-current',
      'sourceEvidenceState',v_evidence_status->>'state',
      'independentVerification',true,
      'ownerOutcomeAcceptedAsPromotionTrust',false,
      'sourceEvidenceUsedAsTriggerOnly',true,
      'incidentClosurePerformed',false,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  if v_evidence.returned_at
       < p_verified_at-make_interval(secs=>p_max_evidence_age_seconds)
     or v_evidence.returned_at>p_verified_at+interval '5 minutes' then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceVerification',
        'shine-foundation/promoted-release-owner-evidence-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-evidence-too-old',
      'evidenceReturnedAt',v_evidence.returned_at,
      'maxEvidenceAgeSeconds',p_max_evidence_age_seconds,
      'independentVerification',true,
      'ownerOutcomeAcceptedAsPromotionTrust',false,
      'sourceEvidenceUsedAsTriggerOnly',true,
      'incidentClosurePerformed',false,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  -- Crucial trust boundary: no owner-supplied outcome, fact, reference or
  -- recommendation is passed into the independent canonical evaluation.
  v_independent :=
    foundation.evaluate_foundation_promoted_release_independent_recovery_v1(
      v_evidence.environment,
      p_verified_at,
      p_observation_max_age_seconds
    );

  v_alignment := case
    when v_independent->>'verificationState'='indeterminate'
      or v_evidence.owner_reported_outcome='inconclusive'
      then 'inconclusive'
    when v_independent->>'verificationState'='recovered'
      and v_evidence.owner_reported_outcome in ('resolved','improved')
      then 'agrees'
    when v_independent->>'verificationState'='recovered'
      and v_evidence.owner_reported_outcome in ('unchanged','worsened')
      then 'disagrees'
    when v_independent->>'verificationState'='impaired'
      and v_evidence.owner_reported_outcome='resolved'
      then 'disagrees'
    when v_independent->>'verificationState'='impaired'
      and v_evidence.owner_reported_outcome in ('unchanged','worsened')
      then 'agrees'
    else 'inconclusive'
  end;

  v_doc := jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceVerification',
      'shine-foundation/promoted-release-owner-evidence-verification-v1',
    'schemaVersion','1.0.0',
    'evidenceReturnId',v_evidence.evidence_return_id,
    'handoffId',v_evidence.handoff_id,
    'responseId',v_evidence.response_id,
    'incidentEventId',v_evidence.incident_event_id,
    'environment',v_evidence.environment,
    'sourceEvidenceReturnSha256',v_evidence.evidence_return_sha256,
    'sourceEvidenceStateAtAdmission','current',
    'ownerReportedOutcome',v_evidence.owner_reported_outcome,
    'ownerClaimAlignment',v_alignment,
    'ownerOutcomeAcceptedAsPromotionTrust',false,
    'sourceEvidenceUsedAsTriggerOnly',true,
    'independentVerification',true,
    'independentEvaluationFunction',
      'foundation.evaluate_foundation_promoted_release_independent_recovery_v1',
    'verificationState',v_independent->>'verificationState',
    'verificationReasonCode',v_independent->>'reasonCode',
    'canonicalRecoveryObserved',
      v_independent->'canonicalRecoveryObserved',
    'canonicalSourceTruthState',
      v_independent#>>'{canonicalSourceTruth,state}',
    'canonicalSourceTruthFingerprint',
      v_independent#>>'{canonicalSourceTruth,evidenceFingerprint}',
    'promotionClosureState',
      v_independent#>>'{promotionClosure,state}',
    'promotedReleaseState',
      v_independent#>>'{promotedRelease,state}',
    'promotedReleaseAvailable',
      v_independent#>'{promotedRelease,available}',
    'promotedReleaseSha256',
      v_independent#>>'{promotedRelease,promotedReleaseSha256}',
    'trustState',v_independent#>>'{promotionTrust,state}',
    'incidentState',v_independent#>>'{incident,state}',
    'independentChecks',v_independent->'checks',
    'incidentClosurePerformed',false,
    'promotionTrustChangedByVerification',false,
    'releaseTruthMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'verifiedAt',p_verified_at
  );

  v_doc_hash := encode(
    extensions.digest(
      convert_to(v_doc::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.foundation_promoted_release_owner_evidence_verifications(
    evidence_return_id,
    handoff_id,
    response_id,
    incident_event_id,
    environment,
    owner_reported_outcome,
    source_evidence_return_sha256,
    canonical_source_truth_state,
    canonical_source_truth_fingerprint,
    promotion_closure_state,
    promoted_release_state,
    promoted_release_available,
    promoted_release_sha256,
    trust_state,
    incident_state,
    verification_state,
    owner_claim_alignment,
    verification_proof,
    verification_proof_sha256,
    verified_at
  )
  values (
    v_evidence.evidence_return_id,
    v_evidence.handoff_id,
    v_evidence.response_id,
    v_evidence.incident_event_id,
    v_evidence.environment,
    v_evidence.owner_reported_outcome,
    v_evidence.evidence_return_sha256,
    coalesce(v_independent#>>'{canonicalSourceTruth,state}','unknown'),
    nullif(v_independent#>>'{canonicalSourceTruth,evidenceFingerprint}',''),
    coalesce(v_independent#>>'{promotionClosure,state}','unknown'),
    coalesce(v_independent#>>'{promotedRelease,state}','unknown'),
    coalesce((v_independent#>>'{promotedRelease,available}')::boolean,false),
    nullif(v_independent#>>'{promotedRelease,promotedReleaseSha256}',''),
    coalesce(v_independent#>>'{promotionTrust,state}','unknown'),
    coalesce(v_independent#>>'{incident,state}','unknown'),
    v_independent->>'verificationState',
    v_alignment,
    v_doc,
    v_doc_hash,
    p_verified_at
  )
  returning verification_id into v_verification_id;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceVerification',
      'shine-foundation/promoted-release-owner-evidence-verification-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'verificationId',v_verification_id,
    'evidenceReturnId',v_evidence.evidence_return_id,
    'ownerReportedOutcome',v_evidence.owner_reported_outcome,
    'verificationState',v_independent->>'verificationState',
    'ownerClaimAlignment',v_alignment,
    'canonicalRecoveryObserved',
      v_independent->'canonicalRecoveryObserved',
    'verificationProofSha256',v_doc_hash,
    'independentVerification',true,
    'ownerOutcomeAcceptedAsPromotionTrust',false,
    'sourceEvidenceUsedAsTriggerOnly',true,
    'incidentClosurePerformed',false,
    'promotionTrustChangedByVerification',false,
    'releaseTruthMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer70_verify$;

revoke all on function foundation.run_promoted_release_owner_evidence_verification_v1(
  uuid,timestamptz,integer,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_promoted_release_owner_evidence_verification_v1(
  uuid,timestamptz,integer,integer
) to service_role;


create or replace function foundation.get_promoted_release_owner_evidence_verification_status_v1(
  p_evidence_return_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer70_status$
declare
  v_row foundation.foundation_promoted_release_owner_evidence_verifications%rowtype;
  v_evidence foundation.foundation_promoted_release_owner_evidence_returns%rowtype;
  v_expected_hash text;
  v_source_state text := 'unknown';
  v_state text;
begin
  select * into v_row
  from foundation.foundation_promoted_release_owner_evidence_verifications
  where evidence_return_id=p_evidence_return_id;

  if v_row.verification_id is null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceVerificationStatus',
        'shine-foundation/promoted-release-owner-evidence-verification-status-v1',
      'schemaVersion','1.0.0',
      'state','pending',
      'evidenceReturnId',p_evidence_return_id,
      'independentVerification',true,
      'ownerOutcomeAcceptedAsPromotionTrust',false,
      'incidentClosurePerformed',false,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  v_expected_hash := encode(
    extensions.digest(
      convert_to(v_row.verification_proof::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select * into v_evidence
  from foundation.foundation_promoted_release_owner_evidence_returns
  where evidence_return_id=v_row.evidence_return_id;

  if v_evidence.evidence_return_id is not null then
    v_source_state := coalesce(
      foundation.get_foundation_promoted_release_owner_evidence_status_v1(
        v_evidence.handoff_id,now()
      )->>'state',
      'unknown'
    );
  end if;

  v_state := case
    when v_expected_hash is distinct from v_row.verification_proof_sha256
      then 'invalid'
    when v_evidence.evidence_return_id is null
      then 'invalid'
    when v_evidence.evidence_return_sha256
         is distinct from v_row.source_evidence_return_sha256
      then 'invalid'
    when v_evidence.handoff_id is distinct from v_row.handoff_id
      or v_evidence.response_id is distinct from v_row.response_id
      or v_evidence.incident_event_id is distinct from v_row.incident_event_id
      then 'invalid'
    else 'completed'
  end;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceVerificationStatus',
      'shine-foundation/promoted-release-owner-evidence-verification-status-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'verificationId',v_row.verification_id,
    'evidenceReturnId',v_row.evidence_return_id,
    'sourceEvidenceCurrentState',v_source_state,
    'sourceEvidenceReturnSha256',v_row.source_evidence_return_sha256,
    'ownerReportedOutcome',v_row.owner_reported_outcome,
    'ownerClaimAlignment',v_row.owner_claim_alignment,
    'verificationState',v_row.verification_state,
    'canonicalSourceTruthState',v_row.canonical_source_truth_state,
    'canonicalSourceTruthFingerprint',v_row.canonical_source_truth_fingerprint,
    'promotionClosureState',v_row.promotion_closure_state,
    'promotedReleaseState',v_row.promoted_release_state,
    'promotedReleaseAvailable',v_row.promoted_release_available,
    'promotedReleaseSha256',v_row.promoted_release_sha256,
    'trustState',v_row.trust_state,
    'incidentState',v_row.incident_state,
    'integrityVerified',v_state='completed',
    'verificationProofSha256',v_row.verification_proof_sha256,
    'independentVerification',true,
    'ownerOutcomeAcceptedAsPromotionTrust',false,
    'sourceEvidenceUsedAsTriggerOnly',true,
    'incidentClosurePerformed',false,
    'promotionTrustChangedByVerification',false,
    'releaseTruthMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'verifiedAt',v_row.verified_at
  );
end;
$layer70_status$;

revoke all on function foundation.get_promoted_release_owner_evidence_verification_status_v1(
  uuid
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_promoted_release_owner_evidence_verification_status_v1(
  uuid
) to foundation_runtime,service_role;
