-- Foundation Layer 57: Shine-core runtime-health owner inbox and acknowledgement.
-- Converts current Layer-56 investigation proposals into a bounded owner workflow.
-- A dedicated no-login, no-inherit capability role is used because foundation_gateway
-- intentionally inherits foundation_runtime. The unhealthy execution surface must not
-- inherit owner acknowledgement authority.

do $layer57_role$
begin
  if not exists(select 1 from pg_roles where rolname='shine_core_control_plane') then
    create role shine_core_control_plane
      nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls;
  else
    alter role shine_core_control_plane
      nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls;
  end if;
end;
$layer57_role$;

grant usage on schema foundation to shine_core_control_plane;

-- Match the established Foundation privileged-capability pattern: postgres may
-- explicitly SET ROLE into this no-inherit capability; Gateway is never a member.
grant shine_core_control_plane to postgres;

-- Tighten Layer-56 owner visibility: use verified inbox/status APIs instead of
-- direct proposal-ledger SELECT from the owner principal.
revoke select on foundation.readiness_runtime_health_investigation_proposals
  from foundation_runtime;


create table foundation.readiness_runtime_health_investigation_responses(
  response_sequence bigint generated always as identity primary key,
  response_id uuid not null unique default gen_random_uuid(),
  proposal_id uuid not null unique
    references foundation.readiness_runtime_health_investigation_proposals(proposal_id),
  readiness_incident_event_id uuid not null
    references foundation.foundation_readiness_incident_events(event_id),
  environment text not null,
  service_id text not null references foundation.service_registry(service_id),
  owner_component text not null,
  response_state text not null
    check(response_state in ('accepted','rejected','clarification-requested')),
  reason_code text not null
    check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  response_note text,
  proposal_sha256 text not null check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
  condition_fingerprint text not null check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
  response jsonb not null check(jsonb_typeof(response)='object'),
  response_sha256 text not null check(response_sha256 ~ '^[a-f0-9]{64}$'),
  responded_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check(response_note is null or char_length(response_note)<=2000)
);

alter table foundation.readiness_runtime_health_investigation_responses
  enable row level security;

-- Policy exists as defence in depth, but foundation_runtime receives no direct
-- table SELECT grant. Reads are through bounded status/inbox functions only.
create policy shine_core_control_plane_runtime_health_responses_select
on foundation.readiness_runtime_health_investigation_responses
for select to shine_core_control_plane using(true);

revoke all on foundation.readiness_runtime_health_investigation_responses
  from public,anon,authenticated,foundation_gateway,foundation_runtime,
       shine_defence_runtime,service_role;
grant select on foundation.readiness_runtime_health_investigation_responses
  to service_role;

create index readiness_runtime_health_responses_incident_idx
  on foundation.readiness_runtime_health_investigation_responses(
    readiness_incident_event_id,responded_at desc
  );

create index readiness_runtime_health_responses_service_idx
  on foundation.readiness_runtime_health_investigation_responses(
    service_id,environment,responded_at desc
  );

create trigger readiness_runtime_health_investigation_responses_append_only
before update or delete on foundation.readiness_runtime_health_investigation_responses
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.respond_readiness_runtime_health_investigation_v1(
  p_proposal_id uuid,
  p_response_state text,
  p_reason_code text,
  p_response_note text default null,
  p_responded_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer57_respond$
declare
  p foundation.readiness_runtime_health_investigation_proposals%rowtype;
  ps jsonb;
  existing foundation.readiness_runtime_health_investigation_responses%rowtype;
  doc jsonb;
  doc_hash text;
  rid uuid;
begin
  if p_proposal_id is null then
    raise exception 'runtime-health-investigation-response-proposal-required';
  end if;

  if p_response_state not in ('accepted','rejected','clarification-requested') then
    raise exception 'runtime-health-investigation-response-state-invalid';
  end if;

  if p_reason_code is null
     or p_reason_code !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'runtime-health-investigation-response-reason-invalid';
  end if;

  if p_response_note is not null and char_length(p_response_note)>2000 then
    raise exception 'runtime-health-investigation-response-note-too-large';
  end if;

  if p_responded_at<now()-interval '5 minutes'
     or p_responded_at>now()+interval '5 minutes' then
    raise exception 'runtime-health-investigation-response-time-invalid';
  end if;

  select * into p
  from foundation.readiness_runtime_health_investigation_proposals
  where proposal_id=p_proposal_id;

  if p.proposal_id is null then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationResponse',
        'shine-foundation/readiness-runtime-health-investigation-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','runtime-health-investigation-proposal-not-found',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  if p.service_id<>'foundation.gateway'
     or p.owner_component<>'shine-core' then
    raise exception 'runtime-health-investigation-response-not-addressed-to-shine-core';
  end if;

  ps:=foundation.get_readiness_runtime_health_investigation_proposal_status_v1(
    p.proposal_id
  );

  if ps->>'state'<>'current'
     or coalesce(ps->>'integrityVerified','false')<>'true' then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationResponse',
        'shine-foundation/readiness-runtime-health-investigation-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','runtime-health-investigation-proposal-not-current',
      'proposalState',ps->>'state',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  select * into existing
  from foundation.readiness_runtime_health_investigation_responses
  where proposal_id=p.proposal_id;

  if existing.response_id is not null then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationResponse',
        'shine-foundation/readiness-runtime-health-investigation-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'responseId',existing.response_id,
      'proposalId',existing.proposal_id,
      'responseState',existing.response_state,
      'responseSha256',existing.response_sha256,
      'acknowledgesInvestigationOwnership',
        existing.response_state='accepted',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  doc:=jsonb_build_object(
    'readinessRuntimeHealthInvestigationResponse',
      'shine-foundation/readiness-runtime-health-investigation-response-v1',
    'schemaVersion','1.0.0',
    'proposalId',p.proposal_id,
    'readinessIncidentEventId',p.readiness_incident_event_id,
    'environment',p.environment,
    'serviceId',p.service_id,
    'ownerComponent',p.owner_component,
    'responseState',p_response_state,
    'reasonCode',p_reason_code,
    'responseNote',p_response_note,
    'proposalSha256',p.proposal_sha256,
    'conditionFingerprint',p.condition_fingerprint,
    'acknowledgesInvestigationOwnership',p_response_state='accepted',
    'investigationAuthorityOnly',p_response_state='accepted',
    'runtimeMutationAuthorityGranted',false,
    'healthPolicyMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'safeModeBypassAuthorityGranted',false,
    'readinessChanged',false,
    'incidentClosurePerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'respondedAt',p_responded_at
  );

  doc_hash:=encode(
    extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.readiness_runtime_health_investigation_responses(
    proposal_id,readiness_incident_event_id,environment,service_id,
    owner_component,response_state,reason_code,response_note,
    proposal_sha256,condition_fingerprint,response,response_sha256,responded_at
  )
  values(
    p.proposal_id,p.readiness_incident_event_id,p.environment,p.service_id,
    p.owner_component,p_response_state,p_reason_code,p_response_note,
    p.proposal_sha256,p.condition_fingerprint,doc,doc_hash,p_responded_at
  )
  returning response_id into rid;

  return jsonb_build_object(
    'foundationReadinessRuntimeHealthInvestigationResponse',
      'shine-foundation/readiness-runtime-health-investigation-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'responseId',rid,
    'proposalId',p.proposal_id,
    'responseState',p_response_state,
    'responseSha256',doc_hash,
    'acknowledgesInvestigationOwnership',p_response_state='accepted',
    'investigationAuthorityOnly',p_response_state='accepted',
    'runtimeMutationAuthorityGranted',false,
    'healthPolicyMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'safeModeBypassAuthorityGranted',false,
    'readinessChanged',false,
    'incidentClosurePerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false
  );
end;
$layer57_respond$;

revoke all on function foundation.respond_readiness_runtime_health_investigation_v1(
  uuid,text,text,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role,shine_defence_runtime;
grant execute on function foundation.respond_readiness_runtime_health_investigation_v1(
  uuid,text,text,text,timestamptz
) to shine_core_control_plane;


create or replace function foundation.get_readiness_runtime_health_investigation_response_status_v1(
  p_proposal_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer57_status$
declare
  ps jsonb;
  r foundation.readiness_runtime_health_investigation_responses%rowtype;
  expected_hash text;
  state text;
begin
  ps:=foundation.get_readiness_runtime_health_investigation_proposal_status_v1(
    p_proposal_id
  );

  select * into r
  from foundation.readiness_runtime_health_investigation_responses
  where proposal_id=p_proposal_id;

  if r.response_id is null then
    return jsonb_build_object(
      'foundationReadinessRuntimeHealthInvestigationResponseStatus',
        'shine-foundation/readiness-runtime-health-investigation-response-status-v1',
      'schemaVersion','1.0.0',
      'state',case when ps->>'state'='current' then 'pending' else 'stale' end,
      'proposalId',p_proposal_id,
      'proposalState',ps->>'state',
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesRemediation',false
    );
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(r.response::text,'UTF8'),'sha256'),
    'hex'
  );

  state:=case
    when expected_hash is distinct from r.response_sha256 then 'invalid'
    when ps->>'state'<>'current' then 'stale'
    else r.response_state
  end;

  return jsonb_build_object(
    'foundationReadinessRuntimeHealthInvestigationResponseStatus',
      'shine-foundation/readiness-runtime-health-investigation-response-status-v1',
    'schemaVersion','1.0.0',
    'state',state,
    'proposalId',r.proposal_id,
    'responseId',r.response_id,
    'responseState',r.response_state,
    'reasonCode',r.reason_code,
    'responseNote',r.response_note,
    'proposalState',ps->>'state',
    'integrityVerified',expected_hash=r.response_sha256,
    'acknowledgesInvestigationOwnership',r.response_state='accepted',
    'investigationAuthorityOnly',r.response_state='accepted',
    'runtimeMutationAuthorityGranted',false,
    'healthPolicyMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'safeModeBypassAuthorityGranted',false,
    'readinessChanged',false,
    'incidentClosurePerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false,
    'respondedAt',r.responded_at
  );
end;
$layer57_status$;

revoke all on function foundation.get_readiness_runtime_health_investigation_response_status_v1(uuid)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_readiness_runtime_health_investigation_response_status_v1(uuid)
  to shine_core_control_plane,service_role;


create or replace function foundation.get_readiness_runtime_health_owner_inbox_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer57_inbox$
declare
  rec record;
  proposal_state jsonb;
  response_state jsonb;
  items jsonb := '[]'::jsonb;
  pending_count integer := 0;
  visible_count integer := 0;
begin
  if p_environment is null or btrim(p_environment)='' then
    raise exception 'runtime-health-owner-inbox-environment-required';
  end if;

  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'runtime-health-owner-inbox-limit-invalid';
  end if;

  for rec in
    select p.*
    from foundation.readiness_runtime_health_investigation_proposals p
    where p.environment=p_environment
      and p.service_id='foundation.gateway'
      and p.owner_component='shine-core'
    order by p.proposal_sequence desc
  loop
    proposal_state:=
      foundation.get_readiness_runtime_health_investigation_proposal_status_v1(
        rec.proposal_id
      );

    if proposal_state->>'state'<>'current'
       or coalesce(proposal_state->>'integrityVerified','false')<>'true' then
      continue;
    end if;

    response_state:=
      foundation.get_readiness_runtime_health_investigation_response_status_v1(
        rec.proposal_id
      );

    if response_state->>'state'<>'pending' then
      continue;
    end if;

    pending_count:=pending_count+1;

    if visible_count<p_limit then
      items:=items || jsonb_build_array(
        jsonb_build_object(
          'proposalId',rec.proposal_id,
          'readinessIncidentEventId',rec.readiness_incident_event_id,
          'environment',rec.environment,
          'serviceId',rec.service_id,
          'ownerComponent',rec.owner_component,
          'severity',rec.severity,
          'healthState',rec.health_state,
          'healthReasonCodes',rec.health_reason_codes,
          'healthEvidenceRef',rec.health_evidence_ref,
          'runtimeVersion',rec.runtime_version,
          'proposal',rec.proposal,
          'proposalSha256',rec.proposal_sha256,
          'conditionFingerprint',rec.condition_fingerprint,
          'proposalState','current',
          'responseState','pending',
          'integrityVerified',true,
          'responderRole','shine_core_control_plane',
          'responseFunction',
            'foundation.respond_readiness_runtime_health_investigation_v1',
          'runtimeMutationAuthorityGranted',false,
          'healthPolicyMutationAuthorityGranted',false,
          'releaseRebindAuthorityGranted',false,
          'safeModeBypassAuthorityGranted',false,
          'approvalGranted',false,
          'executionAuthorityGranted',false,
          'executesRemediation',false,
          'createdAt',rec.created_at
        )
      );
      visible_count:=visible_count+1;
    end if;
  end loop;

  return jsonb_build_object(
    'foundationReadinessRuntimeHealthOwnerInbox',
      'shine-foundation/readiness-runtime-health-owner-inbox-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'serviceId','foundation.gateway',
    'ownerComponent','shine-core',
    'responderRole','shine_core_control_plane',
    'responseFunction',
      'foundation.respond_readiness_runtime_health_investigation_v1',
    'pendingCount',pending_count,
    'visibleCount',visible_count,
    'hasMore',pending_count>visible_count,
    'items',items,
    'runtimeMutationAuthorityGranted',false,
    'healthPolicyMutationAuthorityGranted',false,
    'releaseRebindAuthorityGranted',false,
    'safeModeBypassAuthorityGranted',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesRemediation',false
  );
end;
$layer57_inbox$;

revoke all on function foundation.get_readiness_runtime_health_owner_inbox_v1(text,integer)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role,shine_defence_runtime;
grant execute on function foundation.get_readiness_runtime_health_owner_inbox_v1(text,integer)
  to shine_core_control_plane;
