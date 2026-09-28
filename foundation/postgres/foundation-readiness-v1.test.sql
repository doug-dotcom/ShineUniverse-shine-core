begin;

-- Establish a clean exact-source deployment for the readiness fixture.
insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://test/functions/foundation-gateway',
  'layer30-a',
  repeat('a',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  now()+interval '1 second',
  'test:layer30:deployment-expectation:a',
  'Layer 30 readiness fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://test/functions/foundation-gateway',
  'layer30-a',
  repeat('a',64),
  'active','unknown',
  now()+interval '1 second',
  'manual-verified',
  'test:layer30:deployment-observation:a',
  'Layer 30 readiness fixture.',
  '{"test":true}'::jsonb
);

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer30-a',
  now()-interval '5 minutes',
  now()+interval '2 seconds',
  100,0,0,20,25,
  0,'manual-verified',
  'test:layer30:health:a',
  'Healthy Layer 30 fixture.',
  '{"test":true}'::jsonb,
  now()+interval '2 seconds'
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '30000000-0000-4000-8000-000000000001'::uuid,
  '1.0.0','production','pass',
  now()+interval '3 seconds',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer30:defence:pass',
  now()+interval '3 seconds'
);

do $layer30_ready_audit$
declare
  v_policy jsonb;
  v_audit uuid := '30000000-0000-4000-8000-000000000101'::uuid;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/consent','production',now()+interval '4 seconds'
  ) into v_policy;

  if v_policy->>'policyState' <> 'admit' then
    raise exception 'ready fixture policy should admit: %',v_policy;
  end if;

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'policy','POST','/v1/grants/consent','production',
    v_policy,null,null,null,now()+interval '4 seconds'
  );

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'outcome','POST','/v1/grants/consent','production',
    null,401,'unauthenticated',null,now()+interval '5 seconds'
  );
end;
$layer30_ready_audit$;


do $layer30_ready$
declare
  v jsonb;
  v_first jsonb;
  v_second jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '6 seconds'
  ) into v;

  if v->>'readinessState' <> 'ready' then
    raise exception 'healthy aligned control plane should be ready: %',v;
  end if;

  if v->>'safeMode' <> 'normal'
     or v->>'privilegedOperationsMode' <> 'normal'
     or v->>'workerOperationsMode' <> 'normal' then
    raise exception 'ready modes should be normal: %',v;
  end if;

  if (v#>>'{checks,operationAudit,currentRuntimeCompleteTraceCount}')::integer < 1 then
    raise exception 'ready state requires current-runtime audit proof: %',v;
  end if;

  select foundation.record_foundation_readiness_observation_v1(
    'production',now()+interval '6 seconds'
  ) into v_first;

  select foundation.record_foundation_readiness_observation_v1(
    'production',now()+interval '7 seconds'
  ) into v_second;

  if v_first->>'status' <> 'recorded' then
    raise exception 'first readiness observation should record: %',v_first;
  end if;

  if v_second->>'status' <> 'unchanged' then
    raise exception 'unchanged readiness should deduplicate: %',v_second;
  end if;
end;
$layer30_ready$;


-- Warning Defence posture degrades the guard dependency without failing it closed.
insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '30000000-0000-4000-8000-000000000002'::uuid,
  '1.0.0','production','warning',
  now()+interval '10 seconds',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer30:defence:warning',
  now()+interval '10 seconds'
);

do $layer30_degraded$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '11 seconds'
  ) into v;

  if v->>'readinessState' <> 'degraded' then
    raise exception 'warning guard dependency should degrade readiness: %',v;
  end if;

  if v->>'privilegedOperationsMode' <> 'degraded'
     or v->>'workerOperationsMode' <> 'degraded' then
    raise exception 'degraded state should expose degraded modes: %',v;
  end if;
end;
$layer30_degraded$;


-- Failed guard dependency deliberately restricts privileged scopes while core remains healthy.
insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '30000000-0000-4000-8000-000000000003'::uuid,
  '1.0.0','production','fail',
  now()+interval '20 seconds',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer30:defence:fail',
  now()+interval '20 seconds'
);

do $layer30_restricted$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '21 seconds'
  ) into v;

  if v->>'readinessState' <> 'restricted' then
    raise exception 'failed guard dependency should restrict rather than kill healthy core: %',v;
  end if;

  if v->>'safeMode' <> 'guarded'
     or v->>'privilegedOperationsMode' <> 'guarded'
     or v->>'workerOperationsMode' <> 'normal' then
    raise exception 'restricted mode should guard privileged work but preserve workers: %',v;
  end if;

  if not (v->'reasonCodes' ? 'dependency-guarded') then
    raise exception 'restricted state should explain guarded dependency: %',v;
  end if;
end;
$layer30_restricted$;


-- Unhealthy core overrides guarded-mode availability.
insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer30-a',
  now()-interval '5 minutes',
  now()+interval '22 seconds',
  100,0,10,20,25,
  5,'manual-verified',
  'test:layer30:health:unhealthy',
  'Unhealthy Layer 30 fixture.',
  '{"test":true}'::jsonb,
  now()+interval '22 seconds'
);

do $layer30_not_ready$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '23 seconds'
  ) into v;

  if v->>'readinessState' <> 'not-ready' then
    raise exception 'unhealthy required core service should be not-ready: %',v;
  end if;

  if v->>'safeMode' <> 'blocked'
     or v->>'privilegedOperationsMode' <> 'blocked'
     or v->>'workerOperationsMode' <> 'blocked' then
    raise exception 'not-ready state should block core operation modes: %',v;
  end if;

  if not (v->'reasonCodes' ? 'runtime-unhealthy') then
    raise exception 'not-ready state should explain unhealthy runtime: %',v;
  end if;
end;
$layer30_not_ready$;


-- A brand-new runtime cannot inherit readiness from the runtime it replaced.
insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://test/functions/foundation-gateway',
  'layer30-b',
  repeat('b',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  now()+interval '30 seconds',
  'test:layer30:deployment-expectation:b',
  'Layer 30 new-runtime fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://test/functions/foundation-gateway',
  'layer30-b',
  repeat('b',64),
  'active','unknown',
  now()+interval '30 seconds',
  'manual-verified',
  'test:layer30:deployment-observation:b',
  'Layer 30 new-runtime fixture.',
  '{"test":true}'::jsonb
);

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer30-b',
  now()-interval '5 minutes',
  now()+interval '31 seconds',
  100,0,0,20,25,
  0,'manual-verified',
  'test:layer30:health:b',
  'Healthy new-runtime fixture with no audit proof yet.',
  '{"test":true}'::jsonb,
  now()+interval '31 seconds'
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '30000000-0000-4000-8000-000000000004'::uuid,
  '1.0.0','production','pass',
  now()+interval '32 seconds',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer30:defence:pass-b',
  now()+interval '32 seconds'
);

do $layer30_unknown$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '33 seconds'
  ) into v;

  if v->>'readinessState' <> 'unknown' then
    raise exception 'new runtime without its own audit proof must remain unknown: %',v;
  end if;

  if not (v->'reasonCodes' ? 'current-runtime-audit-proof-missing') then
    raise exception 'unknown state should explain missing current-runtime audit proof: %',v;
  end if;
end;
$layer30_unknown$;


do $layer30_security$
begin
  begin
    update foundation.foundation_readiness_observations
    set readiness_state='not-ready'
    where environment='production';
    raise exception 'append-only readiness mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;

  if has_table_privilege(
    'foundation_gateway',
    'foundation.foundation_readiness_observations',
    'INSERT'
  ) then
    raise exception 'foundation_gateway must not directly write readiness observations';
  end if;

  if not has_function_privilege(
    'foundation_runtime',
    'foundation.evaluate_foundation_readiness_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must evaluate readiness';
  end if;

  if has_function_privilege(
    'foundation_runtime',
    'foundation.record_foundation_readiness_observation_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must not record readiness observations';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.evaluate_foundation_readiness_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'anon must not evaluate readiness';
  end if;

  if has_table_privilege(
    'anon',
    'foundation.foundation_readiness_observations',
    'SELECT'
  ) then
    raise exception 'anon must not read readiness observations';
  end if;
end;
$layer30_security$;

rollback;
