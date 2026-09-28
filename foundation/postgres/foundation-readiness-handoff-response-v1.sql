-- Foundation Layer 49: explicit owner acknowledgement of remediation handoffs.
-- Only the addressed Defence runtime may respond. Response grants no execution authority.

create table foundation.readiness_dependency_remediation_handoff_responses(
  response_sequence bigint generated always as identity primary key,
  response_id uuid not null unique default gen_random_uuid(),
  handoff_id uuid not null unique
    references foundation.readiness_dependency_remediation_handoffs(handoff_id),
  proposal_id uuid not null
    references foundation.readiness_dependency_remediation_proposals(proposal_id),
  readiness_incident_event_id uuid not null
    references foundation.foundation_readiness_incident_events(event_id),
  environment text not null,
  owner_component text not null,
  dependency_service_id text not null,
  response_state text not null
    check(response_state in ('accepted','rejected','clarification-requested')),
  reason_code text not null
    check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  response_note text,
  handoff_sha256 text not null check(handoff_sha256 ~ '^[a-f0-9]{64}$'),
  proposal_sha256 text not null check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
  condition_fingerprint text not null check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
  routing_fingerprint text not null check(routing_fingerprint ~ '^[a-f0-9]{32}$'),
  response jsonb not null check(jsonb_typeof(response)='object'),
  response_sha256 text not null check(response_sha256 ~ '^[a-f0-9]{64}$'),
  responded_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check(response_note is null or char_length(response_note)<=2000)
);

alter table foundation.readiness_dependency_remediation_handoff_responses enable row level security;

create policy foundation_runtime_readiness_handoff_responses_select
on foundation.readiness_dependency_remediation_handoff_responses
for select to foundation_runtime using(true);

revoke all on foundation.readiness_dependency_remediation_handoff_responses
  from public,anon,authenticated,foundation_gateway,service_role,shine_defence_runtime;
grant select on foundation.readiness_dependency_remediation_handoff_responses
  to foundation_runtime,service_role,shine_defence_runtime;

create index readiness_handoff_responses_proposal_idx
  on foundation.readiness_dependency_remediation_handoff_responses(proposal_id);
create index readiness_handoff_responses_incident_idx
  on foundation.readiness_dependency_remediation_handoff_responses(readiness_incident_event_id);

create trigger readiness_handoff_responses_append_only
before update or delete on foundation.readiness_dependency_remediation_handoff_responses
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.respond_readiness_dependency_remediation_handoff_v1(
  p_handoff_id uuid,
  p_response_state text,
  p_reason_code text,
  p_response_note text default null,
  p_responded_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer49_respond$
declare
  h foundation.readiness_dependency_remediation_handoffs%rowtype;
  hs jsonb;
  existing foundation.readiness_dependency_remediation_handoff_responses%rowtype;
  doc jsonb;
  doc_hash text;
  rid uuid;
begin
  if p_handoff_id is null then
    raise exception 'readiness-handoff-response-handoff-required';
  end if;

  if p_response_state not in ('accepted','rejected','clarification-requested') then
    raise exception 'readiness-handoff-response-state-invalid';
  end if;

  if p_reason_code is null
     or p_reason_code !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'readiness-handoff-response-reason-invalid';
  end if;

  if p_response_note is not null and char_length(p_response_note)>2000 then
    raise exception 'readiness-handoff-response-note-too-large';
  end if;

  if p_responded_at<now()-interval '5 minutes'
     or p_responded_at>now()+interval '5 minutes' then
    raise exception 'readiness-handoff-response-time-invalid';
  end if;

  select * into h
  from foundation.readiness_dependency_remediation_handoffs
  where handoff_id=p_handoff_id;

  if h.handoff_id is null then
    return jsonb_build_object(
      'foundationReadinessHandoffResponse','shine-foundation/readiness-handoff-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-handoff-not-found',
      'executionAuthorityGranted',false
    );
  end if;

  if h.dependency_service_id<>'foundation.defence'
     or h.owner_component<>'universe' then
    raise exception 'readiness-handoff-response-not-addressed-to-defence';
  end if;

  hs:=foundation.get_readiness_dependency_remediation_handoff_status_v1(h.handoff_id);

  if hs->>'state'<>'current'
     or hs->>'integrityVerified'<>'true' then
    return jsonb_build_object(
      'foundationReadinessHandoffResponse','shine-foundation/readiness-handoff-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-handoff-not-current',
      'handoffState',hs->>'state',
      'executionAuthorityGranted',false
    );
  end if;

  select * into existing
  from foundation.readiness_dependency_remediation_handoff_responses
  where handoff_id=h.handoff_id;

  if existing.response_id is not null then
    return jsonb_build_object(
      'foundationReadinessHandoffResponse','shine-foundation/readiness-handoff-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'responseId',existing.response_id,
      'responseState',existing.response_state,
      'responseSha256',existing.response_sha256,
      'executionAuthorityGranted',false
    );
  end if;

  doc:=jsonb_build_object(
    'readinessDependencyRemediationHandoffResponse',
      'shine-foundation/readiness-dependency-remediation-handoff-response-v1',
    'schemaVersion','1.0.0',
    'handoffId',h.handoff_id,
    'proposalId',h.proposal_id,
    'readinessIncidentEventId',h.readiness_incident_event_id,
    'environment',h.environment,
    'ownerComponent',h.owner_component,
    'dependencyServiceId',h.dependency_service_id,
    'responseState',p_response_state,
    'reasonCode',p_reason_code,
    'responseNote',p_response_note,
    'handoffSha256',h.handoff_sha256,
    'proposalSha256',h.proposal_sha256,
    'conditionFingerprint',h.condition_fingerprint,
    'routingFingerprint',h.routing_fingerprint,
    'acknowledgesOwnership',p_response_state='accepted',
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'respondedAt',p_responded_at
  );

  doc_hash:=encode(
    extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.readiness_dependency_remediation_handoff_responses(
    handoff_id,proposal_id,readiness_incident_event_id,environment,
    owner_component,dependency_service_id,response_state,reason_code,response_note,
    handoff_sha256,proposal_sha256,condition_fingerprint,routing_fingerprint,
    response,response_sha256,responded_at
  )
  values(
    h.handoff_id,h.proposal_id,h.readiness_incident_event_id,h.environment,
    h.owner_component,h.dependency_service_id,p_response_state,p_reason_code,p_response_note,
    h.handoff_sha256,h.proposal_sha256,h.condition_fingerprint,h.routing_fingerprint,
    doc,doc_hash,p_responded_at
  )
  returning response_id into rid;

  return jsonb_build_object(
    'foundationReadinessHandoffResponse','shine-foundation/readiness-handoff-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'responseId',rid,
    'handoffId',h.handoff_id,
    'responseState',p_response_state,
    'responseSha256',doc_hash,
    'acknowledgesOwnership',p_response_state='accepted',
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer49_respond$;

revoke all on function foundation.respond_readiness_dependency_remediation_handoff_v1(
  uuid,text,text,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role;
grant execute on function foundation.respond_readiness_dependency_remediation_handoff_v1(
  uuid,text,text,text,timestamptz
) to shine_defence_runtime;


create or replace function foundation.get_readiness_dependency_remediation_handoff_response_status_v1(
  p_handoff_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer49_status$
declare
  hstate jsonb;
  r foundation.readiness_dependency_remediation_handoff_responses%rowtype;
  expected_hash text;
  state text;
begin
  hstate:=foundation.get_readiness_dependency_remediation_handoff_status_v1(p_handoff_id);

  select * into r
  from foundation.readiness_dependency_remediation_handoff_responses
  where handoff_id=p_handoff_id;

  if r.response_id is null then
    return jsonb_build_object(
      'foundationReadinessHandoffResponseStatus',
        'shine-foundation/readiness-handoff-response-status-v1',
      'schemaVersion','1.0.0',
      'state',case when hstate->>'state'='current' then 'pending' else 'stale' end,
      'handoffId',p_handoff_id,
      'handoffState',hstate->>'state',
      'executionAuthorityGranted',false
    );
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(r.response::text,'UTF8'),'sha256'),
    'hex'
  );

  state:=case
    when expected_hash is distinct from r.response_sha256 then 'invalid'
    when hstate->>'state'<>'current' then 'stale'
    else r.response_state
  end;

  return jsonb_build_object(
    'foundationReadinessHandoffResponseStatus',
      'shine-foundation/readiness-handoff-response-status-v1',
    'schemaVersion','1.0.0',
    'state',state,
    'handoffId',r.handoff_id,
    'responseId',r.response_id,
    'responseState',r.response_state,
    'reasonCode',r.reason_code,
    'responseNote',r.response_note,
    'handoffState',hstate->>'state',
    'integrityVerified',expected_hash=r.response_sha256,
    'acknowledgesOwnership',r.response_state='accepted',
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false,
    'respondedAt',r.responded_at
  );
end;
$layer49_status$;

revoke all on function foundation.get_readiness_dependency_remediation_handoff_response_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_dependency_remediation_handoff_response_status_v1(uuid)
  to foundation_runtime,service_role,shine_defence_runtime;
