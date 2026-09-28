begin;

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','74',
  now()-interval '5 minutes',now()+interval '1 second',
  5,0,0,10,20,0,
  'manual-verified','test:layer27:gateway-health',
  'Layer 27 policy fixture: healthy Gateway.',
  '{"test":true}'::jsonb,now()
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  gen_random_uuid(),'1.0.0','production','pass',
  now()+interval '2 seconds',now()+interval '30 minutes',
  '{"test":true}'::jsonb,'test:layer27:defence-pass',now()+interval '2 seconds'
);

do $$
declare
  v jsonb;
  v_scopes integer;
begin
  select foundation.get_gateway_operation_policy_coverage_v1('production') into v;
  if v->>'state' <> 'pass' then
    raise exception 'production operation policy coverage should pass: %',v;
  end if;
  if (v->>'privilegedOperationCount')::integer <> 24
     or (v->>'coveredOperationCount')::integer <> 24 then
    raise exception 'all 24 privileged route contracts must have policy coverage: %',v;
  end if;
  if (v->>'dependencyAdmissionPolicyCount')::integer <> 21
     or (v->>'workerOnlyPolicyCount')::integer <> 2 then
    raise exception 'expected 21 admission + 2 worker-only policies: %',v;
  end if;
  if (v->>'missingAdmissionBindingCount')::integer <> 0
     or (v->>'missingDependencyScopeCount')::integer <> 0 then
    raise exception 'all policy bindings and scopes must resolve: %',v;
  end if;

  select count(distinct impact_scope) into v_scopes
  from foundation.current_service_dependencies
  where dependent_service_id='foundation.gateway'
    and dependency_service_id='foundation.defence'
    and environment='production'
    and active=true;

  if v_scopes <> 6 then
    raise exception 'Gateway -> Defence should expose six policy scopes, got %',v_scopes;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.evaluate_gateway_operation_policy_v1(
    'access.evaluate','production',now()+interval '3 seconds'
  ) into v;
  if v->>'policyState' <> 'admit' then
    raise exception 'access.evaluate should admit under pass posture: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'concierge.execute','production',now()+interval '3 seconds'
  ) into v;
  if v->>'policyState' <> 'admit'
     or v->>'impactScope' <> 'protected-operations' then
    raise exception 'concierge execute should share protected scope admission: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'grant.consent','production',now()+interval '3 seconds'
  ) into v;
  if v->>'policyState' <> 'admit'
     or v->>'impactScope' <> 'permission-operations' then
    raise exception 'grant consent should resolve permission scope: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'integration.delegation.refresh','production',now()+interval '3 seconds'
  ) into v;
  if v->>'policyState' <> 'admit'
     or v->>'impactScope' <> 'credential-operations' then
    raise exception 'delegation refresh should resolve credential scope: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'concierge.retry.claim','production',now()+interval '3 seconds'
  ) into v;
  if v->>'policyState' <> 'worker-only' then
    raise exception 'retry claim must remain worker-only: %',v;
  end if;
end;
$$;


insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  gen_random_uuid(),'1.0.0','production','warning',
  now()+interval '10 seconds',now()+interval '30 minutes',
  '{"test":true}'::jsonb,'test:layer27:defence-warning',now()+interval '10 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_gateway_operation_policy_v1(
    'grant.revoke','production',now()+interval '11 seconds'
  ) into v;
  if v->>'policyState' <> 'admit-degraded'
     or v->>'reasonCode' <> 'dependency-degraded' then
    raise exception 'permission mutation should admit degraded on Defence warning: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'integration.context.publish','production',now()+interval '11 seconds'
  ) into v;
  if v->>'policyState' <> 'admit-degraded'
     or v->>'impactScope' <> 'context-operations' then
    raise exception 'context publish should admit degraded on Defence warning: %',v;
  end if;
end;
$$;


insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  gen_random_uuid(),'1.0.0','production','fail',
  now()+interval '20 seconds',now()+interval '30 minutes',
  '{"test":true}'::jsonb,'test:layer27:defence-fail',now()+interval '20 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_gateway_operation_policy_v1(
    'identity.claim','production',now()+interval '21 seconds'
  ) into v;
  if v->>'policyState' <> 'deny'
     or v->>'reasonCode' <> 'dependency-guarded' then
    raise exception 'identity mutation must fail closed on Defence fail: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'integration.device-link.exchange','production',now()+interval '21 seconds'
  ) into v;
  if v->>'policyState' <> 'deny'
     or v->>'impactScope' <> 'credential-operations' then
    raise exception 'credential operation must fail closed on Defence fail: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'concierge.cancel','production',now()+interval '21 seconds'
  ) into v;
  if v->>'policyState' <> 'deny'
     or v->>'impactScope' <> 'control-operations' then
    raise exception 'control mutation must fail closed on Defence fail: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'concierge.retry.claim','production',now()+interval '21 seconds'
  ) into v;
  if v->>'policyState' <> 'worker-only' then
    raise exception 'worker policy should remain worker-only independent of Defence posture: %',v;
  end if;
end;
$$;


insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','test-policy-gap','1.0.0','testPolicyGapPath','POST','/test/policy-gap',
  'test.policy-gap','permission-write','write','user','service-guard',
  'foundation.revoke_access_grant_v1','test:layer27:policy-gap',now()
);

do $$
declare
  v jsonb;
begin
  select foundation.get_gateway_operation_policy_coverage_v1('test-policy-gap') into v;
  if v->>'state' <> 'fail' or (v->>'missingPolicyCount')::integer <> 1 then
    raise exception 'missing privileged operation policy must fail coverage: %',v;
  end if;
end;
$$;


do $$
begin
  begin
    update foundation.gateway_operation_policies
    set execution_guard_ref='mutated'
    where service_id='foundation.gateway'
      and environment='production'
      and operation_key='grant.consent';
    raise exception 'append-only operation policy update unexpectedly succeeded';
  exception
    when sqlstate '55000' then null;
  end;

  if has_table_privilege('anon','foundation.gateway_operation_policies','SELECT') then
    raise exception 'anon must not read operation policies';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.evaluate_gateway_operation_policy_v1(text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute operation policy broker';
  end if;
end;
$$;


set local role foundation_gateway;
select foundation.evaluate_gateway_operation_policy_v1(
  'grant.consent','production',now()+interval '21 seconds'
);
select foundation.evaluate_gateway_operation_policy_v1(
  'concierge.retry.claim','production',now()+interval '21 seconds'
);
reset role;

rollback;
