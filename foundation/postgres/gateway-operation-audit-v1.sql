-- Foundation Layer 29: canonical privileged-operation audit truth.
-- Two-event append-only audit chain: policy before route execution, outcome after response.

create table foundation.gateway_operation_audit_events (
  audit_event_sequence bigint generated always as identity primary key,
  audit_event_id uuid not null unique default gen_random_uuid(),
  operation_audit_id uuid not null,
  phase text not null check (phase in ('policy','outcome')),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  runtime_version text,
  deployment_evidence_ref text,
  deployment_source_ref text,
  artifact_sha256 text
    check (artifact_sha256 is null or artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  route_symbol text not null,
  http_method text not null check (http_method in ('POST')),
  path_template text not null check (path_template like '/%'),
  operation_key text not null
    check (operation_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  risk_class text not null,
  effect_class text not null check (effect_class in ('write','execute','credential')),
  policy_state text not null
    check (policy_state in ('admit','admit-degraded','deny','unavailable','worker-only')),
  policy_reason_code text not null,
  policy_evidence_ref text,
  impact_scope text,
  dependency_evidence jsonb not null default '[]'::jsonb
    check (jsonb_typeof(dependency_evidence)='array'),
  execution_guard_ref text not null,
  http_status integer
    check (http_status is null or http_status between 100 and 599),
  outcome_class text
    check (outcome_class is null or outcome_class in (
      'completed',
      'policy-denied',
      'policy-unavailable',
      'authentication-rejected',
      'authorization-or-guard-denied',
      'validation-rejected',
      'not-found',
      'conflict',
      'route-unavailable',
      'other'
    )),
  response_reason_code text,
  domain_request_id text
    check (domain_request_id is null or char_length(domain_request_id) between 1 and 128),
  occurred_at timestamptz not null,
  previous_event_hash text
    check (previous_event_hash is null or previous_event_hash ~ '^[a-fA-F0-9]{64}$'),
  event_hash text not null unique
    check (event_hash ~ '^[a-fA-F0-9]{64}$'),
  recorded_at timestamptz not null default now(),
  unique(operation_audit_id,phase),
  check (
    (phase='policy' and http_status is null and outcome_class is null and previous_event_hash is null)
    or
    (phase='outcome' and http_status is not null and outcome_class is not null and previous_event_hash is not null)
  )
);

alter table foundation.gateway_operation_audit_events enable row level security;

create policy foundation_runtime_gateway_operation_audit_events_select
on foundation.gateway_operation_audit_events
for select
to foundation_runtime
using (true);

revoke all on foundation.gateway_operation_audit_events from public,anon,authenticated,foundation_gateway;
grant select on foundation.gateway_operation_audit_events to foundation_runtime;
grant select,insert on foundation.gateway_operation_audit_events to service_role;

create index gateway_operation_audit_events_attempt_idx
  on foundation.gateway_operation_audit_events(operation_audit_id,audit_event_sequence);

create index gateway_operation_audit_events_operation_idx
  on foundation.gateway_operation_audit_events(environment,operation_key,occurred_at desc);

create index gateway_operation_audit_events_open_idx
  on foundation.gateway_operation_audit_events(environment,occurred_at)
  where phase='policy';

create trigger gateway_operation_audit_events_append_only
before update or delete on foundation.gateway_operation_audit_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.record_gateway_operation_audit_event_v1(
  p_operation_audit_id uuid,
  p_phase text,
  p_http_method text,
  p_path text,
  p_environment text default 'production',
  p_policy jsonb default null,
  p_http_status integer default null,
  p_response_reason_code text default null,
  p_domain_request_id text default null,
  p_occurred_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer29$
declare
  v_route foundation.gateway_operation_contracts%rowtype;
  v_existing foundation.gateway_operation_audit_events%rowtype;
  v_policy_event foundation.gateway_operation_audit_events%rowtype;
  v_observation foundation.service_deployment_observations%rowtype;
  v_expectation foundation.service_deployment_expectations%rowtype;
  v_policy_state text;
  v_policy_reason text;
  v_policy_evidence text;
  v_impact_scope text;
  v_dependency_evidence jsonb := '[]'::jsonb;
  v_execution_guard text;
  v_runtime_version text;
  v_deployment_evidence text;
  v_source_ref text;
  v_artifact_sha text;
  v_outcome_class text;
  v_previous_hash text;
  v_event_hash text;
  v_canonical text;
begin
  if p_operation_audit_id is null then
    raise exception 'operation-audit-id-required';
  end if;

  if p_phase not in ('policy','outcome') then
    raise exception 'operation-audit-phase-invalid';
  end if;

  if upper(coalesce(p_http_method,'')) <> 'POST'
     or p_path is null
     or p_path not like '/%' then
    raise exception 'operation-audit-route-invalid';
  end if;

  select * into v_route
  from foundation.current_gateway_operation_contracts c
  where c.service_id='foundation.gateway'
    and c.environment=p_environment
    and c.http_method='POST'
    and (
      p_path=c.path_template
      or p_path like '%/foundation-gateway' || c.path_template
    )
  limit 1;

  if v_route.operation_contract_id is null or v_route.effect_class='read' then
    raise exception 'operation-audit-route-not-privileged';
  end if;

  select * into v_existing
  from foundation.gateway_operation_audit_events
  where operation_audit_id=p_operation_audit_id
    and phase=p_phase;

  if p_phase='policy' then
    if p_policy is null or jsonb_typeof(p_policy)<>'object' then
      raise exception 'operation-audit-policy-required';
    end if;

    if coalesce(p_policy->>'operationKey','') <> v_route.operation_key then
      raise exception 'operation-audit-policy-operation-mismatch';
    end if;

    v_policy_state := p_policy->>'policyState';
    v_policy_reason := p_policy->>'reasonCode';
    v_policy_evidence := p_policy#>>'{policy,policyEvidenceRef}';
    v_impact_scope := p_policy#>>'{policy,impactScope}';
    v_dependency_evidence := coalesce(
      p_policy#>'{policy,admission,dependencyEvidence}',
      '[]'::jsonb
    );
    v_execution_guard := p_policy#>>'{policy,executionGuardRef}';

    if v_policy_state not in ('admit','admit-degraded','deny','unavailable','worker-only')
       or v_policy_reason is null
       or v_execution_guard is null then
      raise exception 'operation-audit-policy-invalid';
    end if;

    if jsonb_typeof(v_dependency_evidence)<>'array'
       or jsonb_array_length(v_dependency_evidence)>20 then
      raise exception 'operation-audit-dependency-evidence-invalid';
    end if;

    if v_existing.audit_event_id is not null then
      if v_existing.route_symbol=v_route.route_symbol
         and v_existing.policy_state=v_policy_state
         and v_existing.policy_reason_code=v_policy_reason
         and coalesce(v_existing.policy_evidence_ref,'')=coalesce(v_policy_evidence,'') then
        return jsonb_build_object(
          'status','replayed',
          'operationAuditId',p_operation_audit_id,
          'phase',p_phase,
          'eventHash',v_existing.event_hash
        );
      end if;
      raise exception 'operation-audit-replay-conflict';
    end if;

    select * into v_observation
    from foundation.current_service_deployment_observations
    where service_id='foundation.gateway'
      and environment=p_environment;

    select * into v_expectation
    from foundation.current_service_deployment_expectations
    where service_id='foundation.gateway'
      and environment=p_environment;

    v_runtime_version := v_observation.runtime_version;
    v_deployment_evidence := v_observation.evidence_ref;
    v_source_ref := v_expectation.source_ref;
    v_artifact_sha := v_observation.artifact_sha256;
    v_previous_hash := null;
  else
    if p_http_status is null or p_http_status<100 or p_http_status>599 then
      raise exception 'operation-audit-http-status-required';
    end if;

    select * into v_policy_event
    from foundation.gateway_operation_audit_events
    where operation_audit_id=p_operation_audit_id
      and phase='policy';

    if v_policy_event.audit_event_id is null then
      raise exception 'operation-audit-policy-event-missing';
    end if;

    if v_policy_event.route_symbol<>v_route.route_symbol then
      raise exception 'operation-audit-route-mismatch';
    end if;

    if v_existing.audit_event_id is not null then
      if v_existing.http_status=p_http_status
         and coalesce(v_existing.response_reason_code,'')=coalesce(p_response_reason_code,'')
         and coalesce(v_existing.domain_request_id,'')=coalesce(p_domain_request_id,'') then
        return jsonb_build_object(
          'status','replayed',
          'operationAuditId',p_operation_audit_id,
          'phase',p_phase,
          'eventHash',v_existing.event_hash
        );
      end if;
      raise exception 'operation-audit-replay-conflict';
    end if;

    v_policy_state := v_policy_event.policy_state;
    v_policy_reason := v_policy_event.policy_reason_code;
    v_policy_evidence := v_policy_event.policy_evidence_ref;
    v_impact_scope := v_policy_event.impact_scope;
    v_dependency_evidence := v_policy_event.dependency_evidence;
    v_execution_guard := v_policy_event.execution_guard_ref;
    v_runtime_version := v_policy_event.runtime_version;
    v_deployment_evidence := v_policy_event.deployment_evidence_ref;
    v_source_ref := v_policy_event.deployment_source_ref;
    v_artifact_sha := v_policy_event.artifact_sha256;
    v_previous_hash := v_policy_event.event_hash;

    v_outcome_class := case
      when v_policy_state='deny' then 'policy-denied'
      when v_policy_state='unavailable' then 'policy-unavailable'
      when p_http_status between 200 and 299 then 'completed'
      when p_http_status=401 then 'authentication-rejected'
      when p_http_status=403 then 'authorization-or-guard-denied'
      when p_http_status in (400,413,415,422) then 'validation-rejected'
      when p_http_status=404 then 'not-found'
      when p_http_status=409 then 'conflict'
      when p_http_status>=500 then 'route-unavailable'
      else 'other'
    end;
  end if;

  if p_domain_request_id is not null and char_length(p_domain_request_id)>128 then
    raise exception 'operation-audit-domain-request-id-too-long';
  end if;

  v_canonical := pg_catalog.concat_ws(
    '|',
    p_operation_audit_id::text,
    p_phase,
    'foundation.gateway',
    p_environment,
    coalesce(v_runtime_version,''),
    coalesce(v_deployment_evidence,''),
    coalesce(v_source_ref,''),
    coalesce(v_artifact_sha,''),
    v_route.route_symbol,
    'POST',
    v_route.path_template,
    v_route.operation_key,
    v_route.risk_class,
    v_route.effect_class,
    v_policy_state,
    v_policy_reason,
    coalesce(v_policy_evidence,''),
    coalesce(v_impact_scope,''),
    v_dependency_evidence::text,
    v_execution_guard,
    coalesce(p_http_status::text,''),
    coalesce(v_outcome_class,''),
    coalesce(p_response_reason_code,''),
    coalesce(p_domain_request_id,''),
    p_occurred_at::text,
    coalesce(v_previous_hash,'')
  );

  v_event_hash := pg_catalog.encode(
    extensions.digest(v_canonical,'sha256'),
    'hex'
  );

  insert into foundation.gateway_operation_audit_events(
    operation_audit_id,phase,service_id,environment,
    runtime_version,deployment_evidence_ref,deployment_source_ref,artifact_sha256,
    route_symbol,http_method,path_template,operation_key,risk_class,effect_class,
    policy_state,policy_reason_code,policy_evidence_ref,impact_scope,
    dependency_evidence,execution_guard_ref,
    http_status,outcome_class,response_reason_code,domain_request_id,
    occurred_at,previous_event_hash,event_hash
  )
  values (
    p_operation_audit_id,p_phase,'foundation.gateway',p_environment,
    v_runtime_version,v_deployment_evidence,v_source_ref,v_artifact_sha,
    v_route.route_symbol,'POST',v_route.path_template,v_route.operation_key,
    v_route.risk_class,v_route.effect_class,
    v_policy_state,v_policy_reason,v_policy_evidence,v_impact_scope,
    v_dependency_evidence,v_execution_guard,
    p_http_status,v_outcome_class,p_response_reason_code,p_domain_request_id,
    p_occurred_at,v_previous_hash,v_event_hash
  );

  return jsonb_build_object(
    'status','recorded',
    'operationAuditId',p_operation_audit_id,
    'phase',p_phase,
    'eventHash',v_event_hash
  );
end;
$layer29$;

revoke all on function foundation.record_gateway_operation_audit_event_v1(
  uuid,text,text,text,text,jsonb,integer,text,text,timestamptz
) from public,anon,authenticated,foundation_runtime;
grant execute on function foundation.record_gateway_operation_audit_event_v1(
  uuid,text,text,text,text,jsonb,integer,text,text,timestamptz
) to foundation_gateway,service_role;


create or replace function foundation.get_gateway_operation_audit_trace_v1(
  p_operation_audit_id uuid
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $layer29$
declare
  v_events jsonb;
  v_request_id text;
  v_request_uuid uuid;
  v_domain jsonb := '[]'::jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'sequence',audit_event_sequence,
    'eventId',audit_event_id,
    'phase',phase,
    'runtimeVersion',runtime_version,
    'deploymentEvidenceRef',deployment_evidence_ref,
    'deploymentSourceRef',deployment_source_ref,
    'artifactSha256',artifact_sha256,
    'routeSymbol',route_symbol,
    'method',http_method,
    'path',path_template,
    'operationKey',operation_key,
    'riskClass',risk_class,
    'effectClass',effect_class,
    'policyState',policy_state,
    'policyReasonCode',policy_reason_code,
    'policyEvidenceRef',policy_evidence_ref,
    'impactScope',impact_scope,
    'dependencyEvidence',dependency_evidence,
    'executionGuardRef',execution_guard_ref,
    'httpStatus',http_status,
    'outcomeClass',outcome_class,
    'responseReasonCode',response_reason_code,
    'domainRequestId',domain_request_id,
    'occurredAt',occurred_at,
    'previousEventHash',previous_event_hash,
    'eventHash',event_hash
  ) order by audit_event_sequence),'[]'::jsonb),
  max(domain_request_id) filter (where domain_request_id is not null)
  into v_events,v_request_id
  from foundation.gateway_operation_audit_events
  where operation_audit_id=p_operation_audit_id;

  if jsonb_array_length(v_events)=0 then
    return jsonb_build_object(
      'gatewayOperationAuditTraceResponse','shine-foundation/gateway-operation-audit-trace-response-v1',
      'schemaVersion','1.0.0',
      'operationAuditId',p_operation_audit_id,
      'status','not-found',
      'events','[]'::jsonb,
      'domainEvidence','[]'::jsonb
    );
  end if;

  if v_request_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_request_uuid := v_request_id::uuid;

    select coalesce(jsonb_agg(e order by e->>'occurredAt'),'[]'::jsonb)
    into v_domain
    from (
      select jsonb_build_object(
        'source','access_audit_events','eventId',a.event_id::text,
        'outcome',a.decision,'reasonCode',a.reason_code,'occurredAt',a.occurred_at
      ) as e
      from foundation.access_audit_events a where a.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','grant_consent_events','eventId',g.consent_id::text,
        'outcome',g.outcome,'reasonCode',g.reason_code,'occurredAt',g.occurred_at
      )
      from foundation.grant_consent_events g where g.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','grant_revocation_events','eventId',g.event_id::text,
        'outcome',g.outcome,'reasonCode',g.reason_code,'occurredAt',g.occurred_at
      )
      from foundation.grant_revocation_events g where g.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','identity_claim_events','eventId',i.claim_id::text,
        'outcome',i.outcome,'reasonCode',i.reason_code,'occurredAt',i.occurred_at
      )
      from foundation.identity_claim_events i where i.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','integration_client_grant_events','eventId',g.event_id::text,
        'outcome',g.outcome,'reasonCode',g.reason_code,'occurredAt',g.occurred_at
      )
      from foundation.integration_client_grant_events g where g.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','integration_client_link_events','eventId',l.event_id::text,
        'outcome',l.outcome,'reasonCode',l.reason_code,'occurredAt',l.occurred_at
      )
      from foundation.integration_client_link_events l where l.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','integration_context_snapshot_events','eventId',c.event_id::text,
        'outcome',c.event_type,'reasonCode',c.reason_code,'occurredAt',c.occurred_at
      )
      from foundation.integration_context_snapshot_events c where c.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','concierge_execution_events','eventId',c.event_id::text,
        'outcome',c.event_type,'reasonCode',c.reason_code,'occurredAt',c.occurred_at
      )
      from foundation.concierge_execution_events c where c.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','concierge_outcome_events','eventId',c.event_id::text,
        'outcome',c.outcome,'reasonCode',c.reason_code,'occurredAt',c.occurred_at
      )
      from foundation.concierge_outcome_events c where c.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','concierge_cancellation_events','eventId',c.event_id::text,
        'outcome','cancelled','reasonCode',c.reason_code,'occurredAt',c.cancelled_at
      )
      from foundation.concierge_cancellation_events c where c.request_id=v_request_uuid
      union all
      select jsonb_build_object(
        'source','integration_link_request_events','eventId',l.event_id::text,
        'outcome',l.event_type,'reasonCode',null,'occurredAt',l.occurred_at
      )
      from foundation.integration_link_request_events l where l.request_id=v_request_uuid
    ) q;
  end if;

  return jsonb_build_object(
    'gatewayOperationAuditTraceResponse','shine-foundation/gateway-operation-audit-trace-response-v1',
    'schemaVersion','1.0.0',
    'operationAuditId',p_operation_audit_id,
    'status','ok',
    'events',v_events,
    'domainEvidence',v_domain
  );
end;
$layer29$;

revoke all on function foundation.get_gateway_operation_audit_trace_v1(uuid)
  from public,anon,authenticated;
grant execute on function foundation.get_gateway_operation_audit_trace_v1(uuid)
  to foundation_runtime,foundation_gateway;


create or replace function foundation.get_gateway_operation_audit_health_v1(
  p_environment text default 'production',
  p_stale_after_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $layer29$
declare
  v_policy_count integer;
  v_outcome_count integer;
  v_open_count integer;
  v_broken_chain integer;
  v_state text;
begin
  if p_stale_after_seconds<30 or p_stale_after_seconds>86400 then
    raise exception 'audit-health-stale-window-invalid';
  end if;

  select count(*) filter (where phase='policy'),
         count(*) filter (where phase='outcome')
  into v_policy_count,v_outcome_count
  from foundation.gateway_operation_audit_events
  where environment=p_environment
    and occurred_at>=now()-interval '24 hours';

  select count(*) into v_open_count
  from foundation.gateway_operation_audit_events p
  where p.environment=p_environment
    and p.phase='policy'
    and p.occurred_at<now()-make_interval(secs=>p_stale_after_seconds)
    and not exists (
      select 1 from foundation.gateway_operation_audit_events o
      where o.operation_audit_id=p.operation_audit_id
        and o.phase='outcome'
    );

  select count(*) into v_broken_chain
  from foundation.gateway_operation_audit_events o
  left join foundation.gateway_operation_audit_events p
    on p.operation_audit_id=o.operation_audit_id
   and p.phase='policy'
  where o.environment=p_environment
    and o.phase='outcome'
    and (
      p.audit_event_id is null
      or o.previous_event_hash<>p.event_hash
    );

  v_state := case
    when v_broken_chain>0 then 'fail'
    when v_open_count>0 then 'degraded'
    when v_policy_count=0 then 'unknown'
    else 'pass'
  end;

  return jsonb_build_object(
    'gatewayOperationAuditHealthResponse','shine-foundation/gateway-operation-audit-health-response-v1',
    'schemaVersion','1.0.0',
    'serviceId','foundation.gateway',
    'environment',p_environment,
    'state',v_state,
    'policyEventCount24h',v_policy_count,
    'outcomeEventCount24h',v_outcome_count,
    'openTraceCount',v_open_count,
    'brokenChainCount',v_broken_chain,
    'staleAfterSeconds',p_stale_after_seconds
  );
end;
$layer29$;

revoke all on function foundation.get_gateway_operation_audit_health_v1(text,integer)
  from public,anon,authenticated;
grant execute on function foundation.get_gateway_operation_audit_health_v1(text,integer)
  to foundation_runtime,foundation_gateway;
