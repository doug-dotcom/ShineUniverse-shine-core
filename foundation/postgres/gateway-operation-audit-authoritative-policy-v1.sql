-- Foundation Layer 29: make database route policy authoritative for audit.
-- Idempotent patch for existing Layer-29 deployments.

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
  v_authoritative_policy jsonb;
  v_supplied_policy jsonb;
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
    -- The database is the authority for policy evidence. Recompute the route
    -- decision at the caller-supplied timestamp so audit truth does not depend
    -- on JSON transport fidelity from Edge/Postgres.js.
    v_authoritative_policy := foundation.evaluate_gateway_route_policy_v1(
      'POST',
      p_path,
      p_environment,
      p_occurred_at
    );

    if v_authoritative_policy is null
       or jsonb_typeof(v_authoritative_policy)<>'object'
       or coalesce(v_authoritative_policy->>'operationKey','')<>v_route.operation_key then
      raise exception 'operation-audit-authoritative-policy-unavailable';
    end if;

    -- A supplied snapshot is useful as a consistency assertion, but is not
    -- required to create canonical audit evidence. Some drivers may return or
    -- transport jsonb as a JSON string, so normalise that representation too.
    v_supplied_policy := p_policy;
    if v_supplied_policy is not null and jsonb_typeof(v_supplied_policy)='string' then
      begin
        v_supplied_policy := (v_supplied_policy #>> '{}')::jsonb;
      exception when others then
        raise exception 'operation-audit-policy-snapshot-invalid';
      end;
    end if;

    if v_supplied_policy is not null then
      if jsonb_typeof(v_supplied_policy)<>'object'
         or coalesce(v_supplied_policy->>'operationKey','')<>v_route.operation_key then
        raise exception 'operation-audit-policy-snapshot-invalid';
      end if;

      if coalesce(v_supplied_policy->>'policyState','')
           <>coalesce(v_authoritative_policy->>'policyState','')
         or coalesce(v_supplied_policy->>'reasonCode','')
           <>coalesce(v_authoritative_policy->>'reasonCode','') then
        raise exception 'operation-audit-policy-snapshot-mismatch';
      end if;
    end if;

    p_policy := v_authoritative_policy;

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

