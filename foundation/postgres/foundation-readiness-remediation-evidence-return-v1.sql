-- Foundation Layer 52: Defence remediation evidence return.
-- Allows only the addressed Defence runtime to return one immutable investigation
-- evidence packet for a current, integrity-verified, accepted remediation handoff.
-- Evidence return never changes readiness, approves work, or executes remediation.

create table foundation.readiness_dependency_remediation_evidence_returns(
  evidence_return_sequence bigint generated always as identity primary key,
  evidence_return_id uuid not null unique default gen_random_uuid(),
  handoff_id uuid not null unique
    references foundation.readiness_dependency_remediation_handoffs(handoff_id),
  response_id uuid not null unique
    references foundation.readiness_dependency_remediation_handoff_responses(response_id),
  proposal_id uuid not null
    references foundation.readiness_dependency_remediation_proposals(proposal_id),
  readiness_incident_event_id uuid not null
    references foundation.foundation_readiness_incident_events(event_id),
  environment text not null,
  owner_component text not null,
  dependency_service_id text not null,
  owner_reported_outcome text not null
    check(owner_reported_outcome in ('resolved','improved','unchanged','worsened','inconclusive')),
  summary text not null
    check(char_length(summary) between 1 and 2000),
  observed_facts jsonb not null
    check(jsonb_typeof(observed_facts)='array')
    check(jsonb_array_length(observed_facts) between 1 and 50),
  evidence_refs jsonb not null default '[]'::jsonb
    check(jsonb_typeof(evidence_refs)='array')
    check(jsonb_array_length(evidence_refs)<=32),
  recommended_next_step text
    check(recommended_next_step is null or char_length(recommended_next_step)<=1000),
  handoff_sha256 text not null check(handoff_sha256 ~ '^[a-f0-9]{64}$'),
  response_sha256 text not null check(response_sha256 ~ '^[a-f0-9]{64}$'),
  proposal_sha256 text not null check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
  condition_fingerprint text not null check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
  routing_fingerprint text not null check(routing_fingerprint ~ '^[a-f0-9]{32}$'),
  evidence_return jsonb not null check(jsonb_typeof(evidence_return)='object'),
  evidence_return_sha256 text not null check(evidence_return_sha256 ~ '^[a-f0-9]{64}$'),
  returned_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.readiness_dependency_remediation_evidence_returns enable row level security;

create policy foundation_runtime_readiness_evidence_returns_select
on foundation.readiness_dependency_remediation_evidence_returns
for select to foundation_runtime using(true);

revoke all on foundation.readiness_dependency_remediation_evidence_returns
  from public,anon,authenticated,foundation_gateway,service_role,shine_defence_runtime;
grant select on foundation.readiness_dependency_remediation_evidence_returns
  to foundation_runtime,service_role;

create index readiness_remediation_evidence_returns_proposal_idx
  on foundation.readiness_dependency_remediation_evidence_returns(proposal_id);
create index readiness_remediation_evidence_returns_incident_idx
  on foundation.readiness_dependency_remediation_evidence_returns(readiness_incident_event_id);

create trigger readiness_remediation_evidence_returns_append_only
before update or delete on foundation.readiness_dependency_remediation_evidence_returns
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.return_readiness_dependency_remediation_evidence_v1(
  p_handoff_id uuid,
  p_owner_reported_outcome text,
  p_summary text,
  p_observed_facts jsonb,
  p_evidence_refs jsonb default '[]'::jsonb,
  p_recommended_next_step text default null,
  p_returned_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer52_return$
declare
  h foundation.readiness_dependency_remediation_handoffs%rowtype;
  r foundation.readiness_dependency_remediation_handoff_responses%rowtype;
  existing foundation.readiness_dependency_remediation_evidence_returns%rowtype;
  hs jsonb;
  rs jsonb;
  doc jsonb;
  doc_hash text;
  eid uuid;
begin
  if p_handoff_id is null then
    raise exception 'readiness-evidence-return-handoff-required';
  end if;

  if p_owner_reported_outcome not in ('resolved','improved','unchanged','worsened','inconclusive') then
    raise exception 'readiness-evidence-return-outcome-invalid';
  end if;

  if p_summary is null
     or btrim(p_summary)=''
     or char_length(p_summary)>2000 then
    raise exception 'readiness-evidence-return-summary-invalid';
  end if;

  if p_observed_facts is null
     or jsonb_typeof(p_observed_facts)<>'array'
     or jsonb_array_length(p_observed_facts)<1
     or jsonb_array_length(p_observed_facts)>50
     or exists(
       select 1
       from jsonb_array_elements(p_observed_facts) x(value)
       where jsonb_typeof(x.value)<>'string'
          or btrim(x.value#>>'{}')=''
          or char_length(x.value#>>'{}')>500
     ) then
    raise exception 'readiness-evidence-return-observed-facts-invalid';
  end if;

  if p_evidence_refs is null
     or jsonb_typeof(p_evidence_refs)<>'array'
     or jsonb_array_length(p_evidence_refs)>32
     or exists(
       select 1
       from jsonb_array_elements(p_evidence_refs) x(value)
       where jsonb_typeof(x.value)<>'string'
          or btrim(x.value#>>'{}')=''
          or char_length(x.value#>>'{}')>1000
     ) then
    raise exception 'readiness-evidence-return-refs-invalid';
  end if;

  if p_recommended_next_step is not null
     and char_length(p_recommended_next_step)>1000 then
    raise exception 'readiness-evidence-return-next-step-too-large';
  end if;

  if p_returned_at<now()-interval '5 minutes'
     or p_returned_at>now()+interval '5 minutes' then
    raise exception 'readiness-evidence-return-time-invalid';
  end if;

  select * into h
  from foundation.readiness_dependency_remediation_handoffs
  where handoff_id=p_handoff_id;

  if h.handoff_id is null then
    return jsonb_build_object(
      'foundationReadinessEvidenceReturn',
        'shine-foundation/readiness-remediation-evidence-return-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-handoff-not-found',
      'requiresIndependentRetest',true,
      'readinessChanged',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  if h.owner_component<>'universe'
     or h.dependency_service_id<>'foundation.defence' then
    raise exception 'readiness-evidence-return-not-addressed-to-defence';
  end if;

  hs:=foundation.get_readiness_dependency_remediation_handoff_status_v1(h.handoff_id);

  if hs->>'state'<>'current'
     or hs->>'integrityVerified'<>'true' then
    return jsonb_build_object(
      'foundationReadinessEvidenceReturn',
        'shine-foundation/readiness-remediation-evidence-return-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-handoff-not-current',
      'handoffState',hs->>'state',
      'requiresIndependentRetest',true,
      'readinessChanged',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  rs:=foundation.get_readiness_dependency_remediation_handoff_response_status_v1(h.handoff_id);

  if rs->>'state'<>'accepted'
     or coalesce(rs->>'integrityVerified','false')<>'true'
     or coalesce(rs->>'acknowledgesOwnership','false')<>'true' then
    return jsonb_build_object(
      'foundationReadinessEvidenceReturn',
        'shine-foundation/readiness-remediation-evidence-return-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-owner-acceptance-required',
      'responseState',rs->>'state',
      'requiresIndependentRetest',true,
      'readinessChanged',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  select * into r
  from foundation.readiness_dependency_remediation_handoff_responses
  where handoff_id=h.handoff_id
    and response_state='accepted';

  if r.response_id is null then
    raise exception 'readiness-evidence-return-accepted-response-missing';
  end if;

  select * into existing
  from foundation.readiness_dependency_remediation_evidence_returns
  where handoff_id=h.handoff_id;

  if existing.evidence_return_id is not null then
    return jsonb_build_object(
      'foundationReadinessEvidenceReturn',
        'shine-foundation/readiness-remediation-evidence-return-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'evidenceReturnId',existing.evidence_return_id,
      'handoffId',existing.handoff_id,
      'ownerReportedOutcome',existing.owner_reported_outcome,
      'evidenceReturnSha256',existing.evidence_return_sha256,
      'requiresIndependentRetest',true,
      'readinessChanged',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  doc:=jsonb_build_object(
    'readinessDependencyRemediationEvidenceReturn',
      'shine-foundation/readiness-dependency-remediation-evidence-return-v1',
    'schemaVersion','1.0.0',
    'handoffId',h.handoff_id,
    'responseId',r.response_id,
    'proposalId',h.proposal_id,
    'readinessIncidentEventId',h.readiness_incident_event_id,
    'environment',h.environment,
    'ownerComponent',h.owner_component,
    'dependencyServiceId',h.dependency_service_id,
    'ownerReportedOutcome',p_owner_reported_outcome,
    'summary',btrim(p_summary),
    'observedFacts',p_observed_facts,
    'evidenceRefs',p_evidence_refs,
    'recommendedNextStep',p_recommended_next_step,
    'handoffSha256',h.handoff_sha256,
    'responseSha256',r.response_sha256,
    'proposalSha256',h.proposal_sha256,
    'conditionFingerprint',h.condition_fingerprint,
    'routingFingerprint',h.routing_fingerprint,
    'requiresIndependentRetest',true,
    'readinessChanged',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'returnedAt',p_returned_at
  );

  doc_hash:=encode(
    extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.readiness_dependency_remediation_evidence_returns(
    handoff_id,response_id,proposal_id,readiness_incident_event_id,
    environment,owner_component,dependency_service_id,owner_reported_outcome,
    summary,observed_facts,evidence_refs,recommended_next_step,
    handoff_sha256,response_sha256,proposal_sha256,condition_fingerprint,
    routing_fingerprint,evidence_return,evidence_return_sha256,returned_at
  )
  values(
    h.handoff_id,r.response_id,h.proposal_id,h.readiness_incident_event_id,
    h.environment,h.owner_component,h.dependency_service_id,p_owner_reported_outcome,
    btrim(p_summary),p_observed_facts,p_evidence_refs,p_recommended_next_step,
    h.handoff_sha256,r.response_sha256,h.proposal_sha256,h.condition_fingerprint,
    h.routing_fingerprint,doc,doc_hash,p_returned_at
  )
  returning evidence_return_id into eid;

  return jsonb_build_object(
    'foundationReadinessEvidenceReturn',
      'shine-foundation/readiness-remediation-evidence-return-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'evidenceReturnId',eid,
    'handoffId',h.handoff_id,
    'responseId',r.response_id,
    'ownerReportedOutcome',p_owner_reported_outcome,
    'evidenceReturnSha256',doc_hash,
    'requiresIndependentRetest',true,
    'readinessChanged',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer52_return$;

revoke all on function foundation.return_readiness_dependency_remediation_evidence_v1(
  uuid,text,text,jsonb,jsonb,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role;
grant execute on function foundation.return_readiness_dependency_remediation_evidence_v1(
  uuid,text,text,jsonb,jsonb,text,timestamptz
) to shine_defence_runtime;


create or replace function foundation.get_readiness_dependency_remediation_evidence_return_status_v1(
  p_handoff_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer52_status$
declare
  e foundation.readiness_dependency_remediation_evidence_returns%rowtype;
  hs jsonb;
  rs jsonb;
  expected_hash text;
  state text;
begin
  hs:=foundation.get_readiness_dependency_remediation_handoff_status_v1(p_handoff_id);
  rs:=foundation.get_readiness_dependency_remediation_handoff_response_status_v1(p_handoff_id);

  select * into e
  from foundation.readiness_dependency_remediation_evidence_returns
  where handoff_id=p_handoff_id;

  if e.evidence_return_id is null then
    return jsonb_build_object(
      'foundationReadinessEvidenceReturnStatus',
        'shine-foundation/readiness-remediation-evidence-return-status-v1',
      'schemaVersion','1.0.0',
      'state',case
        when hs->>'state'<>'current' then 'stale'
        when rs->>'state'='accepted' then 'pending'
        else 'not-accepted'
      end,
      'handoffId',p_handoff_id,
      'handoffState',hs->>'state',
      'responseState',rs->>'state',
      'requiresIndependentRetest',true,
      'readinessChanged',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false
    );
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(e.evidence_return::text,'UTF8'),'sha256'),
    'hex'
  );

  state:=case
    when expected_hash is distinct from e.evidence_return_sha256 then 'invalid'
    when hs->>'state'<>'current' then 'stale'
    when rs->>'state'<>'accepted' then 'stale'
    else 'current'
  end;

  return jsonb_build_object(
    'foundationReadinessEvidenceReturnStatus',
      'shine-foundation/readiness-remediation-evidence-return-status-v1',
    'schemaVersion','1.0.0',
    'state',state,
    'handoffId',e.handoff_id,
    'evidenceReturnId',e.evidence_return_id,
    'responseId',e.response_id,
    'ownerReportedOutcome',e.owner_reported_outcome,
    'summary',e.summary,
    'observedFacts',e.observed_facts,
    'evidenceRefs',e.evidence_refs,
    'recommendedNextStep',e.recommended_next_step,
    'handoffState',hs->>'state',
    'responseState',rs->>'state',
    'integrityVerified',expected_hash=e.evidence_return_sha256,
    'evidenceReturnSha256',e.evidence_return_sha256,
    'requiresIndependentRetest',true,
    'readinessChanged',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'returnedAt',e.returned_at
  );
end;
$layer52_status$;

revoke all on function foundation.get_readiness_dependency_remediation_evidence_return_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_dependency_remediation_evidence_return_status_v1(uuid)
  to foundation_runtime,service_role,shine_defence_runtime;
