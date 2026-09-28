-- Foundation Layer 48: readiness remediation ownership routing and handoff.
-- Converts a current Layer-47 proposal into a deterministic, non-executing owner packet.

create table foundation.readiness_dependency_remediation_handoffs(
  handoff_sequence bigint generated always as identity primary key,
  handoff_id uuid not null unique default gen_random_uuid(),
  environment text not null,
  proposal_id uuid not null
    references foundation.readiness_dependency_remediation_proposals(proposal_id),
  readiness_incident_event_id uuid not null
    references foundation.foundation_readiness_incident_events(event_id),
  condition_fingerprint text not null
    check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
  proposal_sha256 text not null
    check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
  routing_fingerprint text not null
    check(routing_fingerprint ~ '^[a-f0-9]{32}$'),
  owner_component text not null,
  dependency_service_id text not null,
  routed_scopes jsonb not null check(jsonb_typeof(routed_scopes)='array'),
  handoff jsonb not null check(jsonb_typeof(handoff)='object'),
  handoff_sha256 text not null check(handoff_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  unique(proposal_id,owner_component,dependency_service_id,routing_fingerprint)
);

alter table foundation.readiness_dependency_remediation_handoffs enable row level security;

create policy foundation_runtime_readiness_remediation_handoffs_select
on foundation.readiness_dependency_remediation_handoffs
for select to foundation_runtime using(true);

revoke all on foundation.readiness_dependency_remediation_handoffs
  from public,anon,authenticated,foundation_gateway,service_role;
grant select on foundation.readiness_dependency_remediation_handoffs
  to foundation_runtime,service_role;

create index readiness_dependency_remediation_handoffs_proposal_idx
  on foundation.readiness_dependency_remediation_handoffs(
    proposal_id,created_at desc,handoff_sequence desc
  );

create index readiness_dependency_remediation_handoffs_incident_idx
  on foundation.readiness_dependency_remediation_handoffs(readiness_incident_event_id);

create trigger readiness_dependency_remediation_handoffs_append_only
before update or delete on foundation.readiness_dependency_remediation_handoffs
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.generate_readiness_dependency_remediation_handoff_v1(
  p_proposal_id uuid,
  p_created_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer48_generate$
declare
  p foundation.readiness_dependency_remediation_proposals%rowtype;
  proposal_status jsonb;
  route_count integer := 0;
  mapped_scope_count integer := 0;
  expected_scope_count integer := 0;
  v_routing_fingerprint text;
  result jsonb := '[]'::jsonb;
  rec record;
  existing foundation.readiness_dependency_remediation_handoffs%rowtype;
  doc jsonb;
  doc_hash text;
  hid uuid;
begin
  if p_proposal_id is null then
    raise exception 'readiness-remediation-handoff-proposal-required';
  end if;

  select * into p
  from foundation.readiness_dependency_remediation_proposals
  where proposal_id=p_proposal_id;

  if p.proposal_id is null then
    return jsonb_build_object(
      'foundationReadinessRemediationHandoffResponse',
        'shine-foundation/readiness-remediation-handoff-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-proposal-not-found',
      'executionAuthorityGranted',false,
      'approvalGranted',false
    );
  end if;

  proposal_status :=
    foundation.get_readiness_dependency_proposal_status_v1(p.proposal_id);

  if proposal_status->>'state'<>'current'
     or proposal_status->>'integrityVerified'<>'true' then
    return jsonb_build_object(
      'foundationReadinessRemediationHandoffResponse',
        'shine-foundation/readiness-remediation-handoff-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reasonCode','readiness-remediation-proposal-not-current',
      'proposalState',proposal_status->>'state',
      'executionAuthorityGranted',false,
      'approvalGranted',false
    );
  end if;

  expected_scope_count := jsonb_array_length(p.affected_scopes);

  select count(distinct scope)
  into mapped_scope_count
  from (
    select s.value as scope
    from jsonb_array_elements_text(p.affected_scopes) s(value)
    join foundation.current_service_dependencies d
      on d.dependent_service_id='foundation.gateway'
     and d.environment=p.environment
     and d.impact_scope=s.value
     and d.active
    join foundation.service_registry r
      on r.service_id=d.dependency_service_id
     and r.lifecycle='active'
     and nullif(r.owner_component,'') is not null
  ) m;

  if mapped_scope_count<>expected_scope_count then
    raise exception 'readiness-remediation-handoff-owner-coverage-incomplete';
  end if;

  select md5(
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'scope',d.impact_scope,
          'dependencyServiceId',d.dependency_service_id,
          'dependencyType',d.dependency_type,
          'failureMode',d.failure_mode,
          'ownerComponent',r.owner_component
        )
        order by d.impact_scope,d.dependency_service_id,r.owner_component
      ),
      '[]'::jsonb
    )::text
  )
  into v_routing_fingerprint
  from jsonb_array_elements_text(p.affected_scopes) s(value)
  join foundation.current_service_dependencies d
    on d.dependent_service_id='foundation.gateway'
   and d.environment=p.environment
   and d.impact_scope=s.value
   and d.active
  join foundation.service_registry r
    on r.service_id=d.dependency_service_id
   and r.lifecycle='active';

  for rec in
    select
      r.owner_component,
      d.dependency_service_id,
      d.dependency_type,
      d.failure_mode,
      jsonb_agg(distinct d.impact_scope order by d.impact_scope) as routed_scopes
    from jsonb_array_elements_text(p.affected_scopes) s(value)
    join foundation.current_service_dependencies d
      on d.dependent_service_id='foundation.gateway'
     and d.environment=p.environment
     and d.impact_scope=s.value
     and d.active
    join foundation.service_registry r
      on r.service_id=d.dependency_service_id
     and r.lifecycle='active'
    group by r.owner_component,d.dependency_service_id,d.dependency_type,d.failure_mode
    order by r.owner_component,d.dependency_service_id
  loop
    route_count := route_count + 1;

    select * into existing
    from foundation.readiness_dependency_remediation_handoffs h
    where h.proposal_id=p.proposal_id
      and h.owner_component=rec.owner_component
      and h.dependency_service_id=rec.dependency_service_id
      and h.routing_fingerprint=v_routing_fingerprint
    order by handoff_sequence desc
    limit 1;

    if existing.handoff_id is not null then
      result := result || jsonb_build_array(
        jsonb_build_object(
          'status','existing',
          'handoffId',existing.handoff_id,
          'ownerComponent',existing.owner_component,
          'dependencyServiceId',existing.dependency_service_id,
          'routedScopes',existing.routed_scopes,
          'handoffSha256',existing.handoff_sha256
        )
      );
      continue;
    end if;

    doc:=jsonb_build_object(
      'readinessDependencyRemediationHandoff',
        'shine-foundation/readiness-dependency-remediation-handoff-v1',
      'schemaVersion','1.0.0',
      'environment',p.environment,
      'proposalId',p.proposal_id,
      'proposalSha256',p.proposal_sha256,
      'readinessIncidentEventId',p.readiness_incident_event_id,
      'conditionFingerprint',p.condition_fingerprint,
      'ownerComponent',rec.owner_component,
      'dependencyServiceId',rec.dependency_service_id,
      'dependencyType',rec.dependency_type,
      'failureMode',rec.failure_mode,
      'routedScopes',rec.routed_scopes,
      'routingFingerprint',v_routing_fingerprint,
      'requestedWork',jsonb_build_array(
        'inspect-current-defence-and-dependency-evidence',
        'identify-root-cause-for-routed-scopes',
        'prepare-upstream-remediation-change',
        'return-fresh-evidence-to-foundation-readiness-retest'
      ),
      'prohibitedWork',jsonb_build_array(
        'mutate-foundation-release-identity',
        'mutate-foundation-registry-projection',
        'bypass-foundation-safe-mode',
        'execute-unapproved-upstream-change'
      ),
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'executesAction',false,
      'createdAt',p_created_at
    );

    doc_hash:=encode(
      extensions.digest(convert_to(doc::text,'UTF8'),'sha256'),
      'hex'
    );

    insert into foundation.readiness_dependency_remediation_handoffs(
      environment,proposal_id,readiness_incident_event_id,condition_fingerprint,
      proposal_sha256,routing_fingerprint,owner_component,dependency_service_id,
      routed_scopes,handoff,handoff_sha256,created_at
    )
    values(
      p.environment,p.proposal_id,p.readiness_incident_event_id,
      p.condition_fingerprint,p.proposal_sha256,v_routing_fingerprint,
      rec.owner_component,rec.dependency_service_id,rec.routed_scopes,
      doc,doc_hash,p_created_at
    )
    returning handoff_id into hid;

    result := result || jsonb_build_array(
      jsonb_build_object(
        'status','generated',
        'handoffId',hid,
        'ownerComponent',rec.owner_component,
        'dependencyServiceId',rec.dependency_service_id,
        'routedScopes',rec.routed_scopes,
        'handoffSha256',doc_hash
      )
    );
  end loop;

  return jsonb_build_object(
    'foundationReadinessRemediationHandoffResponse',
      'shine-foundation/readiness-remediation-handoff-response-v1',
    'schemaVersion','1.0.0',
    'status','ready',
    'proposalId',p.proposal_id,
    'conditionFingerprint',p.condition_fingerprint,
    'routingFingerprint',v_routing_fingerprint,
    'ownerRouteCount',route_count,
    'handoffs',result,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer48_generate$;

revoke all on function foundation.generate_readiness_dependency_remediation_handoff_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.generate_readiness_dependency_remediation_handoff_v1(
  uuid,timestamptz
) to service_role;


create or replace function foundation.get_readiness_dependency_remediation_handoff_status_v1(
  p_handoff_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer48_status$
declare
  h foundation.readiness_dependency_remediation_handoffs%rowtype;
  pstate jsonb;
  expected_hash text;
  current_routing_fingerprint text;
  state text;
begin
  select * into h
  from foundation.readiness_dependency_remediation_handoffs
  where handoff_id=p_handoff_id;

  if h.handoff_id is null then
    return jsonb_build_object('state','not-found','usable',false);
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(h.handoff::text,'UTF8'),'sha256'),
    'hex'
  );

  pstate:=foundation.get_readiness_dependency_proposal_status_v1(h.proposal_id);

  select md5(
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'scope',d.impact_scope,
          'dependencyServiceId',d.dependency_service_id,
          'dependencyType',d.dependency_type,
          'failureMode',d.failure_mode,
          'ownerComponent',r.owner_component
        )
        order by d.impact_scope,d.dependency_service_id,r.owner_component
      ),
      '[]'::jsonb
    )::text
  )
  into current_routing_fingerprint
  from foundation.readiness_dependency_remediation_proposals p
  cross join jsonb_array_elements_text(p.affected_scopes) s(value)
  join foundation.current_service_dependencies d
    on d.dependent_service_id='foundation.gateway'
   and d.environment=p.environment
   and d.impact_scope=s.value
   and d.active
  join foundation.service_registry r
    on r.service_id=d.dependency_service_id
   and r.lifecycle='active'
  where p.proposal_id=h.proposal_id;

  state:=case
    when expected_hash is distinct from h.handoff_sha256 then 'invalid'
    when pstate->>'state'<>'current' then 'stale'
    when current_routing_fingerprint is distinct from h.routing_fingerprint then 'stale'
    else 'current'
  end;

  return jsonb_build_object(
    'foundationReadinessRemediationHandoffStatus',
      'shine-foundation/readiness-remediation-handoff-status-v1',
    'schemaVersion','1.0.0',
    'state',state,
    'usable',state='current',
    'handoffId',h.handoff_id,
    'proposalId',h.proposal_id,
    'ownerComponent',h.owner_component,
    'dependencyServiceId',h.dependency_service_id,
    'routedScopes',h.routed_scopes,
    'proposalState',pstate->>'state',
    'routingFingerprint',h.routing_fingerprint,
    'currentRoutingFingerprint',current_routing_fingerprint,
    'integrityVerified',expected_hash=h.handoff_sha256,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
end;
$layer48_status$;

revoke all on function foundation.get_readiness_dependency_remediation_handoff_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_dependency_remediation_handoff_status_v1(uuid)
  to foundation_runtime,service_role;
