-- Foundation Layer 69: Shine Core evidence return for promoted-release owner work.
-- Owner evidence is immutable claim/input only. It never changes canonical promotion
-- trust, closes incidents, grants approval or executes remediation.

create table foundation.foundation_promoted_release_owner_evidence_returns (
  evidence_return_sequence bigint generated always as identity primary key,
  evidence_return_id uuid not null unique default gen_random_uuid(),
  handoff_id uuid not null unique
    references foundation.foundation_promoted_release_owner_handoffs(handoff_id),
  response_id uuid not null unique
    references foundation.foundation_promoted_release_owner_handoff_responses(response_id),
  incident_event_id uuid not null
    references foundation.foundation_promoted_release_incident_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  owner_service_id text not null
    references foundation.service_registry(service_id),
  owner_component text not null,
  owner_reported_outcome text not null
    check (
      owner_reported_outcome in (
        'resolved','improved','unchanged','worsened','inconclusive'
      )
    ),
  summary text not null
    check (char_length(summary) between 1 and 2000),
  observed_facts jsonb not null
    check (jsonb_typeof(observed_facts)='array'),
  evidence_refs jsonb not null
    check (jsonb_typeof(evidence_refs)='array'),
  recommended_next_step text
    check (
      recommended_next_step is null
      or char_length(recommended_next_step)<=1000
    ),
  handoff_sha256 text not null
    check (handoff_sha256 ~ '^[a-f0-9]{64}$'),
  response_sha256 text not null
    check (response_sha256 ~ '^[a-f0-9]{64}$'),
  response_plan_fingerprint text not null
    check (response_plan_fingerprint ~ '^[a-f0-9]{64}$'),
  evidence_return jsonb not null
    check (jsonb_typeof(evidence_return)='object'),
  evidence_return_sha256 text not null
    check (evidence_return_sha256 ~ '^[a-f0-9]{64}$'),
  returned_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.foundation_promoted_release_owner_evidence_returns
  enable row level security;

create policy service_role_promoted_release_owner_evidence_select
on foundation.foundation_promoted_release_owner_evidence_returns
for select
to service_role
using (true);

revoke all on foundation.foundation_promoted_release_owner_evidence_returns
  from public,anon,authenticated,foundation_gateway,foundation_runtime,
       shine_core_control_plane,shine_defence_runtime,service_role;
grant select on foundation.foundation_promoted_release_owner_evidence_returns
  to service_role;

create index foundation_promoted_release_owner_evidence_incident_idx
  on foundation.foundation_promoted_release_owner_evidence_returns(
    incident_event_id,returned_at desc,evidence_return_sequence desc
  );

create index foundation_promoted_release_owner_evidence_service_idx
  on foundation.foundation_promoted_release_owner_evidence_returns(
    owner_service_id,environment,returned_at desc,evidence_return_sequence desc
  );

create trigger foundation_promoted_release_owner_evidence_append_only
before update or delete
on foundation.foundation_promoted_release_owner_evidence_returns
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.return_foundation_promoted_release_owner_evidence_v1(
  p_handoff_id uuid,
  p_owner_reported_outcome text,
  p_summary text,
  p_observed_facts jsonb,
  p_evidence_refs jsonb,
  p_recommended_next_step text default null,
  p_returned_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer69_return$
declare
  v_handoff foundation.foundation_promoted_release_owner_handoffs%rowtype;
  v_response foundation.foundation_promoted_release_owner_handoff_responses%rowtype;
  v_existing foundation.foundation_promoted_release_owner_evidence_returns%rowtype;
  v_handoff_status jsonb;
  v_response_status jsonb;
  v_response_hash text;
  v_doc jsonb;
  v_doc_hash text;
  v_evidence_id uuid;
  v_bad_count integer;
begin
  if p_handoff_id is null then
    raise exception 'promoted-release-owner-evidence-handoff-required';
  end if;

  if p_owner_reported_outcome not in (
    'resolved','improved','unchanged','worsened','inconclusive'
  ) then
    raise exception 'promoted-release-owner-evidence-outcome-invalid';
  end if;

  if p_summary is null
     or char_length(btrim(p_summary))<1
     or char_length(p_summary)>2000 then
    raise exception 'promoted-release-owner-evidence-summary-invalid';
  end if;

  if p_observed_facts is null
     or jsonb_typeof(p_observed_facts)<>'array'
     or jsonb_array_length(p_observed_facts)<1
     or jsonb_array_length(p_observed_facts)>50 then
    raise exception 'promoted-release-owner-evidence-facts-invalid';
  end if;

  select count(*) into v_bad_count
  from jsonb_array_elements(p_observed_facts) x(value)
  where jsonb_typeof(x.value)<>'string'
     or char_length(btrim(x.value#>>'{}'))<1
     or char_length(x.value#>>'{}')>500;

  if v_bad_count>0 then
    raise exception 'promoted-release-owner-evidence-fact-invalid';
  end if;

  if p_evidence_refs is null
     or jsonb_typeof(p_evidence_refs)<>'array'
     or jsonb_array_length(p_evidence_refs)<1
     or jsonb_array_length(p_evidence_refs)>32 then
    raise exception 'promoted-release-owner-evidence-refs-invalid';
  end if;

  select count(*) into v_bad_count
  from jsonb_array_elements(p_evidence_refs) x(value)
  where jsonb_typeof(x.value)<>'string'
     or char_length(btrim(x.value#>>'{}'))<1
     or char_length(x.value#>>'{}')>1000;

  if v_bad_count>0 then
    raise exception 'promoted-release-owner-evidence-ref-invalid';
  end if;

  if p_recommended_next_step is not null
     and char_length(p_recommended_next_step)>1000 then
    raise exception 'promoted-release-owner-evidence-next-step-invalid';
  end if;

  if p_returned_at is null
     or p_returned_at<now()-interval '5 minutes'
     or p_returned_at>now()+interval '5 minutes' then
    raise exception 'promoted-release-owner-evidence-time-invalid';
  end if;

  select * into v_handoff
  from foundation.foundation_promoted_release_owner_handoffs
  where handoff_id=p_handoff_id;

  if v_handoff.handoff_id is null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceReturn',
        'shine-foundation/promoted-release-owner-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-handoff-not-found',
      'requiresIndependentVerification',true,
      'ownerEvidenceIsCanonicalPromotionTrust',false,
      'promotionTrustChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  if v_handoff.owner_service_id<>'foundation.gateway'
     or v_handoff.owner_component<>'shine-core' then
    raise exception 'promoted-release-owner-evidence-not-addressed-to-shine-core';
  end if;

  select * into v_existing
  from foundation.foundation_promoted_release_owner_evidence_returns
  where handoff_id=v_handoff.handoff_id;

  if v_existing.evidence_return_id is not null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceReturn',
        'shine-foundation/promoted-release-owner-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'evidenceReturnId',v_existing.evidence_return_id,
      'handoffId',v_existing.handoff_id,
      'responseId',v_existing.response_id,
      'ownerReportedOutcome',v_existing.owner_reported_outcome,
      'evidenceReturnSha256',v_existing.evidence_return_sha256,
      'requiresIndependentVerification',true,
      'ownerEvidenceIsCanonicalPromotionTrust',false,
      'ownerOutcomeClaimOnly',true,
      'promotionTrustChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_handoff_status :=
    foundation.get_foundation_promoted_release_owner_handoff_status_v1(
      v_handoff.handoff_id,p_returned_at
    );

  if v_handoff_status->>'state'<>'current'
     or coalesce(v_handoff_status->>'integrityVerified','false')<>'true'
     or coalesce(v_handoff_status->>'ownerRouteCurrent','false')<>'true' then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceReturn',
        'shine-foundation/promoted-release-owner-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-handoff-not-current',
      'handoffState',v_handoff_status->>'state',
      'requiresIndependentVerification',true,
      'ownerEvidenceIsCanonicalPromotionTrust',false,
      'promotionTrustChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_response_status :=
    foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
      v_handoff.handoff_id,p_returned_at
    );

  if v_response_status->>'state'<>'accepted'
     or coalesce(v_response_status->>'integrityVerified','false')<>'true'
     or coalesce(v_response_status->>'acknowledgesWorkOwnership','false')<>'true' then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceReturn',
        'shine-foundation/promoted-release-owner-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','promoted-release-owner-work-not-accepted',
      'responseState',v_response_status->>'state',
      'requiresIndependentVerification',true,
      'ownerEvidenceIsCanonicalPromotionTrust',false,
      'promotionTrustChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  select * into v_response
  from foundation.foundation_promoted_release_owner_handoff_responses
  where handoff_id=v_handoff.handoff_id;

  v_response_hash := case
    when v_response.response_id is null then null
    else encode(
      extensions.digest(
        convert_to(v_response.response::text,'UTF8'),
        'sha256'
      ),
      'hex'
    )
  end;

  if v_response.response_id is null
     or v_response.response_state<>'accepted'
     or v_response.response_sha256 is distinct from v_response_hash
     or v_response.response_id::text is distinct from
        v_response_status->>'responseId'
     or v_response.handoff_sha256 is distinct from v_handoff.handoff_sha256
     or v_response.response_plan_fingerprint is distinct from
        v_handoff.response_plan_fingerprint then
    raise exception 'promoted-release-owner-evidence-response-binding-invalid';
  end if;

  v_doc := jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidence',
      'shine-foundation/promoted-release-owner-evidence-v1',
    'schemaVersion','1.0.0',
    'handoffId',v_handoff.handoff_id,
    'responseId',v_response.response_id,
    'incidentEventId',v_handoff.incident_event_id,
    'environment',v_handoff.environment,
    'ownerServiceId',v_handoff.owner_service_id,
    'ownerComponent',v_handoff.owner_component,
    'ownerReportedOutcome',p_owner_reported_outcome,
    'summary',p_summary,
    'observedFacts',p_observed_facts,
    'evidenceRefs',p_evidence_refs,
    'recommendedNextStep',p_recommended_next_step,
    'handoffSha256',v_handoff.handoff_sha256,
    'responseSha256',v_response.response_sha256,
    'responsePlanFingerprint',v_handoff.response_plan_fingerprint,
    'ownerEvidenceIsCanonicalPromotionTrust',false,
    'ownerOutcomeClaimOnly',true,
    'requiresIndependentVerification',true,
    'promotionTrustChangedByOwnerEvidence',false,
    'incidentClosurePerformed',false,
    'layer38ApprovalGranted',false,
    'releaseTruthMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'incidentHistoryMutationAuthorityGranted',false,
    'runtimeMutationAuthorityGranted',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'returnedAt',p_returned_at
  );

  v_doc_hash := encode(
    extensions.digest(
      convert_to(v_doc::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.foundation_promoted_release_owner_evidence_returns(
    handoff_id,response_id,incident_event_id,environment,owner_service_id,
    owner_component,owner_reported_outcome,summary,observed_facts,evidence_refs,
    recommended_next_step,handoff_sha256,response_sha256,
    response_plan_fingerprint,evidence_return,evidence_return_sha256,returned_at
  )
  values(
    v_handoff.handoff_id,v_response.response_id,v_handoff.incident_event_id,
    v_handoff.environment,v_handoff.owner_service_id,v_handoff.owner_component,
    p_owner_reported_outcome,p_summary,p_observed_facts,p_evidence_refs,
    p_recommended_next_step,v_handoff.handoff_sha256,v_response.response_sha256,
    v_handoff.response_plan_fingerprint,v_doc,v_doc_hash,p_returned_at
  )
  returning evidence_return_id into v_evidence_id;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceReturn',
      'shine-foundation/promoted-release-owner-evidence-return-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'evidenceReturnId',v_evidence_id,
    'handoffId',v_handoff.handoff_id,
    'responseId',v_response.response_id,
    'ownerReportedOutcome',p_owner_reported_outcome,
    'evidenceReturnSha256',v_doc_hash,
    'requiresIndependentVerification',true,
    'ownerEvidenceIsCanonicalPromotionTrust',false,
    'ownerOutcomeClaimOnly',true,
    'promotionTrustChangedByOwnerEvidence',false,
    'incidentClosurePerformed',false,
    'layer38ApprovalGranted',false,
    'releaseTruthMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'incidentHistoryMutationAuthorityGranted',false,
    'runtimeMutationAuthorityGranted',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer69_return$;

revoke all on function foundation.return_foundation_promoted_release_owner_evidence_v1(
  uuid,text,text,jsonb,jsonb,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime,service_role;
grant execute on function foundation.return_foundation_promoted_release_owner_evidence_v1(
  uuid,text,text,jsonb,jsonb,text,timestamptz
) to shine_core_control_plane;


create or replace function foundation.get_foundation_promoted_release_owner_evidence_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer69_status$
declare
  v_handoff_status jsonb;
  v_response_status jsonb;
  v_evidence foundation.foundation_promoted_release_owner_evidence_returns%rowtype;
  v_response foundation.foundation_promoted_release_owner_handoff_responses%rowtype;
  v_expected_hash text;
  v_response_hash text;
  v_state text;
begin
  v_handoff_status :=
    foundation.get_foundation_promoted_release_owner_handoff_status_v1(
      p_handoff_id,p_as_of
    );

  v_response_status :=
    foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
      p_handoff_id,p_as_of
    );

  select * into v_evidence
  from foundation.foundation_promoted_release_owner_evidence_returns
  where handoff_id=p_handoff_id;

  if v_evidence.evidence_return_id is null then
    return jsonb_build_object(
      'foundationPromotedReleaseOwnerEvidenceStatus',
        'shine-foundation/promoted-release-owner-evidence-status-v1',
      'schemaVersion','1.0.0',
      'state',case
        when v_handoff_status->>'state'='current'
         and v_response_status->>'state'='accepted' then 'pending'
        when v_handoff_status->>'state'<>'current'
          or v_response_status->>'state'='stale' then 'stale'
        else 'not-accepted'
      end,
      'handoffId',p_handoff_id,
      'handoffState',v_handoff_status->>'state',
      'responseState',v_response_status->>'state',
      'requiresIndependentVerification',true,
      'ownerEvidenceIsCanonicalPromotionTrust',false,
      'promotionTrustChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  v_expected_hash := encode(
    extensions.digest(
      convert_to(v_evidence.evidence_return::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select * into v_response
  from foundation.foundation_promoted_release_owner_handoff_responses
  where response_id=v_evidence.response_id;

  v_response_hash := case
    when v_response.response_id is null then null
    else encode(
      extensions.digest(
        convert_to(v_response.response::text,'UTF8'),
        'sha256'
      ),
      'hex'
    )
  end;

  v_state := case
    when v_expected_hash is distinct from v_evidence.evidence_return_sha256
      then 'invalid'
    when v_response.response_id is null
      or v_response.response_sha256 is distinct from v_response_hash
      then 'invalid'
    when v_evidence.response_sha256 is distinct from v_response.response_sha256
      then 'invalid'
    when v_evidence.handoff_sha256 is distinct from v_response.handoff_sha256
      then 'invalid'
    when v_evidence.response_plan_fingerprint is distinct from
         v_response.response_plan_fingerprint
      then 'invalid'
    when v_handoff_status->>'state'<>'current'
      or v_response_status->>'state'<>'accepted'
      then 'stale'
    else 'current'
  end;

  return jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceStatus',
      'shine-foundation/promoted-release-owner-evidence-status-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'evidenceReturnId',v_evidence.evidence_return_id,
    'handoffId',v_evidence.handoff_id,
    'responseId',v_evidence.response_id,
    'ownerReportedOutcome',v_evidence.owner_reported_outcome,
    'handoffState',v_handoff_status->>'state',
    'responseState',v_response_status->>'state',
    'integrityVerified',v_state<>'invalid',
    'evidenceReturnSha256',v_evidence.evidence_return_sha256,
    'requiresIndependentVerification',true,
    'ownerEvidenceIsCanonicalPromotionTrust',false,
    'ownerOutcomeClaimOnly',true,
    'promotionTrustChangedByOwnerEvidence',false,
    'incidentClosurePerformed',false,
    'layer38ApprovalGranted',false,
    'releaseTruthMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'incidentHistoryMutationAuthorityGranted',false,
    'runtimeMutationAuthorityGranted',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'returnedAt',v_evidence.returned_at
  );
end;
$layer69_status$;

revoke all on function foundation.get_foundation_promoted_release_owner_evidence_status_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_owner_evidence_status_v1(
  uuid,timestamptz
) to foundation_runtime,service_role,shine_core_control_plane;
