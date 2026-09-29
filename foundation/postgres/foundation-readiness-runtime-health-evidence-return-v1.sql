-- Foundation Layer 58: Shine-core runtime-health investigation evidence return.
-- Allows the accepted Shine-core owner to return one immutable investigation evidence
-- packet. Owner evidence is a claim/input only; it never becomes canonical health or
-- readiness truth and grants no mutation, closure, rebind or remediation authority.

create table foundation.readiness_runtime_health_investigation_evidence_returns(
  evidence_return_sequence bigint generated always as identity primary key,
  evidence_return_id uuid not null unique default gen_random_uuid(),
  proposal_id uuid not null unique
    references foundation.readiness_runtime_health_investigation_proposals(proposal_id),
  response_id uuid not null unique
    references foundation.readiness_runtime_health_investigation_responses(response_id),
  readiness_incident_event_id uuid not null
    references foundation.foundation_readiness_incident_events(event_id),
  environment text not null,
  service_id text not null references foundation.service_registry(service_id),
  owner_component text not null,
  owner_reported_outcome text not null
    check(owner_reported_outcome in ('resolved','improved','unchanged','worsened','inconclusive')),
  owner_reported_health_state text not null
    check(owner_reported_health_state in ('healthy','degraded','unhealthy','unknown')),
  summary text not null check(char_length(summary) between 1 and 2000),
  observed_facts jsonb not null check(jsonb_typeof(observed_facts)='array'),
  evidence_refs jsonb not null check(jsonb_typeof(evidence_refs)='array'),
  recommended_next_step text check(
    recommended_next_step is null or char_length(recommended_next_step)<=1000
  ),
  proposal_sha256 text not null check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
  response_sha256 text not null check(response_sha256 ~ '^[a-f0-9]{64}$'),
  condition_fingerprint text not null check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
  evidence_return jsonb not null check(jsonb_typeof(evidence_return)='object'),
  evidence_return_sha256 text not null check(evidence_return_sha256 ~ '^[a-f0-9]{64}$'),
  returned_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.readiness_runtime_health_investigation_evidence_returns
  enable row level security;

create policy service_role_runtime_health_evidence_returns_select
on foundation.readiness_runtime_health_investigation_evidence_returns
for select to service_role using(true);

revoke all on foundation.readiness_runtime_health_investigation_evidence_returns
  from public,anon,authenticated,foundation_gateway,foundation_runtime,
       shine_core_control_plane,shine_defence_runtime,service_role;
grant select on foundation.readiness_runtime_health_investigation_evidence_returns
  to service_role;

create index readiness_runtime_health_evidence_returns_incident_idx
  on foundation.readiness_runtime_health_investigation_evidence_returns(
    readiness_incident_event_id,returned_at desc
  );

create index readiness_runtime_health_evidence_returns_service_idx
  on foundation.readiness_runtime_health_investigation_evidence_returns(
    service_id,environment,returned_at desc
  );

create trigger readiness_runtime_health_investigation_evidence_returns_append_only
before update or delete on foundation.readiness_runtime_health_investigation_evidence_returns
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.return_readiness_runtime_health_investigation_evidence_v1(
  p_proposal_id uuid,
  p_owner_reported_outcome text,
  p_owner_reported_health_state text,
  p_summary text,
  p_observed_facts jsonb,
  p_evidence_refs jsonb,
  p_recommended_next_step text default null,
  p_returned_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer58_return$
declare
  p foundation.readiness_runtime_health_investigation_proposals%rowtype;
  r foundation.readiness_runtime_health_investigation_responses%rowtype;
  existing foundation.readiness_runtime_health_investigation_evidence_returns%rowtype;
  ps jsonb;
  rs jsonb;
  doc jsonb;
  doc_hash text;
  eid uuid;
  bad_count integer;
begin
  if p_proposal_id is null then
    raise exception 'runtime-health-investigation-evidence-proposal-required';
  end if;

  if p_owner_reported_outcome not in (
    'resolved','improved','unchanged','worsened','inconclusive'
  ) then
    raise exception 'runtime-health-investigation-evidence-outcome-invalid';
  end if;

  if p_owner_reported_health_state not in (
    'healthy','degraded','unhealthy','unknown'
  ) then
    raise exception 'runtime-health-investigation-evidence-health-state-invalid';
  end if;

  if p_summary is null
     or char_length(btrim(p_summary))<1
     or char_length(p_summary)>2000 then
    raise exception 'runtime-health-investigation-evidence-summary-invalid';
  end if;

  if p_observed_facts is null
     or jsonb_typeof(p_observed_facts)<>'array'
     or jsonb_array_length(p_observed_facts)<1
     or jsonb_array_length(p_observed_facts)>50 then
    raise exception 'runtime-health-investigation-evidence-facts-invalid';
  end if;

  select count(*) into bad_count
  from jsonb_array_elements(p_observed_facts) x(value)
  where jsonb_typeof(x.value)<>'string'
     or char_length(btrim(x.value#>>'{}'))<1
     or char_length(x.value#>>'{}')>500;

  if bad_count>0 then
    raise exception 'runtime-health-investigation-evidence-fact-invalid';
  end if;

  if p_evidence_refs is null
     or jsonb_typeof(p_evidence_refs)<>'array'
     or jsonb_array_length(p_evidence_refs)<1
     or jsonb_array_length(p_evidence_refs)>32 then
    raise exception 'runtime-health-investigation-evidence-refs-invalid';
  end if;

  select count(*) into bad_count
  from jsonb_array_elements(p_evidence_refs) x(value)
  where jsonb_typeof(x.value)<>'string'
     or char_length(btrim(x.value#>>'{}'))<1
     or char_length(x.value#>>'{}')>1000;

  if bad_count>0 then
    raise exception 'runtime-health-investigation-evidence-ref-invalid';
  end if;

  if p_recommended_next_step is not null
     and char_length(p_recommended_next_step)>1000 then
    raise exception 'runtime-health-investigation-evidence-next-step-invalid';
  end if;

  if p_returned_at<now()-interval '5 minutes'
     or p_returned_at>now()+interval '5 minutes' then
    raise exception 'runtime-health-investigation-evidence-time-invalid';
  end if;

  select * into p
  from foundation.readiness_runtime_health_investigation_proposals
  where proposal_id=p_proposal_id;

  if p.proposal_id is null then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationEvidenceReturn',
        'shine-foundation/readiness-runtime-health-investigation-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','runtime-health-investigation-proposal-not-found',
      'requiresIndependentRetest',true,
      'ownerEvidenceIsCanonicalHealth',false,
      'readinessChangedByOwnerEvidence',false,
      'healthChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  if p.service_id<>'foundation.gateway'
     or p.owner_component<>'shine-core' then
    raise exception 'runtime-health-investigation-evidence-not-addressed-to-shine-core';
  end if;

  select * into existing
  from foundation.readiness_runtime_health_investigation_evidence_returns
  where proposal_id=p.proposal_id;

  if existing.evidence_return_id is not null then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationEvidenceReturn',
        'shine-foundation/readiness-runtime-health-investigation-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'evidenceReturnId',existing.evidence_return_id,
      'proposalId',existing.proposal_id,
      'responseId',existing.response_id,
      'ownerReportedOutcome',existing.owner_reported_outcome,
      'ownerReportedHealthState',existing.owner_reported_health_state,
      'evidenceReturnSha256',existing.evidence_return_sha256,
      'requiresIndependentRetest',true,
      'ownerEvidenceIsCanonicalHealth',false,
      'readinessChangedByOwnerEvidence',false,
      'healthChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  ps:=foundation.get_readiness_runtime_health_investigation_proposal_status_v1(
    p.proposal_id
  );

  if ps->>'state'<>'current'
     or coalesce(ps->>'integrityVerified','false')<>'true' then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationEvidenceReturn',
        'shine-foundation/readiness-runtime-health-investigation-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','runtime-health-investigation-proposal-not-current',
      'proposalState',ps->>'state',
      'requiresIndependentRetest',true,
      'ownerEvidenceIsCanonicalHealth',false,
      'readinessChangedByOwnerEvidence',false,
      'healthChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  rs:=foundation.get_readiness_runtime_health_investigation_response_status_v1(
    p.proposal_id
  );

  if rs->>'state'<>'accepted'
     or coalesce(rs->>'integrityVerified','false')<>'true' then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationEvidenceReturn',
        'shine-foundation/readiness-runtime-health-investigation-evidence-return-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','runtime-health-investigation-owner-not-accepted',
      'responseState',rs->>'state',
      'requiresIndependentRetest',true,
      'ownerEvidenceIsCanonicalHealth',false,
      'readinessChangedByOwnerEvidence',false,
      'healthChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  select * into r
  from foundation.readiness_runtime_health_investigation_responses
  where proposal_id=p.proposal_id;

  if r.response_id is null
     or r.response_state<>'accepted'
     or r.proposal_sha256 is distinct from p.proposal_sha256
     or r.condition_fingerprint is distinct from p.condition_fingerprint
     or r.response_sha256 is distinct from rs->>'responseSha256' then
    raise exception 'runtime-health-investigation-evidence-response-binding-invalid';
  end if;

  doc:=jsonb_build_object(
    'readinessRuntimeHealthInvestigationEvidenceReturn',
      'shine-foundation/readiness-runtime-health-investigation-evidence-return-v1',
    'schemaVersion','1.0.0',
    'proposalId',p.proposal_id,
    'responseId',r.response_id,
    'readinessIncidentEventId',p.readiness_incident_event_id,
    'environment',p.environment,
    'serviceId',p.service_id,
    'ownerComponent',p.owner_component,
    'ownerReportedOutcome',p_owner_reported_outcome,
    'ownerReportedHealthState',p_owner_reported_health_state,
    'summary',p_summary,
    'observedFacts',p_observed_facts,
    'evidenceRefs',p_evidence_refs,
    'recommendedNextStep',p_recommended_next_step,
    'proposalSha256',p.proposal_sha256,
    'responseSha256',r.response_sha256,
    'conditionFingerprint',p.condition_fingerprint,
    'ownerEvidenceIsCanonicalHealth',false,
    'ownerHealthClaimOnly',true,
    'requiresIndependentRetest',true,
    'readinessChangedByOwnerEvidence',false,
    'healthChangedByOwnerEvidence',false,
    'incidentClosurePerformed',false,
    'runtimeMutationAuthorityGranted',false,
    'healthPolicyMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'safeModeBypassAuthorityGranted',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'returnedAt',p_returned_at
  );

  doc_hash:=encode(
    extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.readiness_runtime_health_investigation_evidence_returns(
    proposal_id,response_id,readiness_incident_event_id,environment,service_id,
    owner_component,owner_reported_outcome,owner_reported_health_state,summary,
    observed_facts,evidence_refs,recommended_next_step,proposal_sha256,
    response_sha256,condition_fingerprint,evidence_return,evidence_return_sha256,
    returned_at
  )
  values(
    p.proposal_id,r.response_id,p.readiness_incident_event_id,p.environment,
    p.service_id,p.owner_component,p_owner_reported_outcome,
    p_owner_reported_health_state,p_summary,p_observed_facts,p_evidence_refs,
    p_recommended_next_step,p.proposal_sha256,r.response_sha256,
    p.condition_fingerprint,doc,doc_hash,p_returned_at
  )
  returning evidence_return_id into eid;

  return jsonb_build_object(
    'foundationReadinessRuntimeHealthInvestigationEvidenceReturn',
      'shine-foundation/readiness-runtime-health-investigation-evidence-return-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'evidenceReturnId',eid,
    'proposalId',p.proposal_id,
    'responseId',r.response_id,
    'ownerReportedOutcome',p_owner_reported_outcome,
    'ownerReportedHealthState',p_owner_reported_health_state,
    'evidenceReturnSha256',doc_hash,
    'requiresIndependentRetest',true,
    'ownerEvidenceIsCanonicalHealth',false,
    'ownerHealthClaimOnly',true,
    'readinessChangedByOwnerEvidence',false,
    'healthChangedByOwnerEvidence',false,
    'incidentClosurePerformed',false,
    'runtimeMutationAuthorityGranted',false,
    'healthPolicyMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'safeModeBypassAuthorityGranted',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false
  );
end;
$layer58_return$;

revoke all on function foundation.return_readiness_runtime_health_investigation_evidence_v1(
  uuid,text,text,text,jsonb,jsonb,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       service_role,shine_defence_runtime;
grant execute on function foundation.return_readiness_runtime_health_investigation_evidence_v1(
  uuid,text,text,text,jsonb,jsonb,text,timestamptz
) to shine_core_control_plane;


create or replace function foundation.get_readiness_runtime_health_investigation_evidence_return_status_v1(
  p_proposal_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer58_status$
declare
  ps jsonb;
  rs jsonb;
  e foundation.readiness_runtime_health_investigation_evidence_returns%rowtype;
  expected_hash text;
  state text;
begin
  ps:=foundation.get_readiness_runtime_health_investigation_proposal_status_v1(
    p_proposal_id
  );

  rs:=foundation.get_readiness_runtime_health_investigation_response_status_v1(
    p_proposal_id
  );

  select * into e
  from foundation.readiness_runtime_health_investigation_evidence_returns
  where proposal_id=p_proposal_id;

  if e.evidence_return_id is null then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationEvidenceReturnStatus',
        'shine-foundation/readiness-runtime-health-investigation-evidence-return-status-v1',
      'schemaVersion','1.0.0',
      'state',case
        when ps->>'state'='current' and rs->>'state'='accepted' then 'pending'
        when ps->>'state'<>'current' or rs->>'state'='stale' then 'stale'
        else 'not-accepted'
      end,
      'proposalId',p_proposal_id,
      'proposalState',ps->>'state',
      'responseState',rs->>'state',
      'requiresIndependentRetest',true,
      'ownerEvidenceIsCanonicalHealth',false,
      'readinessChangedByOwnerEvidence',false,
      'healthChangedByOwnerEvidence',false,
      'incidentClosurePerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(e.evidence_return::text,'UTF8'),'sha256'),
    'hex'
  );

  state:=case
    when expected_hash is distinct from e.evidence_return_sha256 then 'invalid'
    when rs->>'integrityVerified' is distinct from 'true' then 'invalid'
    when ps->>'state'<>'current' or rs->>'state'<>'accepted' then 'stale'
    when e.response_sha256 is distinct from rs->>'responseSha256' then 'invalid'
    else 'current'
  end;

  return jsonb_build_object(
    'foundationReadinessRuntimeHealthInvestigationEvidenceReturnStatus',
      'shine-foundation/readiness-runtime-health-investigation-evidence-return-status-v1',
    'schemaVersion','1.0.0',
    'state',state,
    'evidenceReturnId',e.evidence_return_id,
    'proposalId',e.proposal_id,
    'responseId',e.response_id,
    'ownerReportedOutcome',e.owner_reported_outcome,
    'ownerReportedHealthState',e.owner_reported_health_state,
    'proposalState',ps->>'state',
    'responseState',rs->>'state',
    'integrityVerified',state<>'invalid',
    'evidenceReturnSha256',e.evidence_return_sha256,
    'requiresIndependentRetest',true,
    'ownerEvidenceIsCanonicalHealth',false,
    'ownerHealthClaimOnly',true,
    'readinessChangedByOwnerEvidence',false,
    'healthChangedByOwnerEvidence',false,
    'incidentClosurePerformed',false,
    'runtimeMutationAuthorityGranted',false,
    'healthPolicyMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'safeModeBypassAuthorityGranted',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'returnedAt',e.returned_at
  );
end;
$layer58_status$;

revoke all on function foundation.get_readiness_runtime_health_investigation_evidence_return_status_v1(uuid)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_readiness_runtime_health_investigation_evidence_return_status_v1(uuid)
  to shine_core_control_plane,service_role;
