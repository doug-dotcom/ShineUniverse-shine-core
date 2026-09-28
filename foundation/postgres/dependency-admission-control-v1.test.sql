begin;

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','72',
  now()-interval '5 minutes',now()+interval '1 second',
  3,0,0,20,25,
  0,'manual-verified','test:layer25:gateway-health',
  'Layer 25 admission fixture: healthy Gateway.',
  '{"test":true}'::jsonb,
  now()
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  gen_random_uuid(),'1.0.0','production','pass',
  now()+interval '2 seconds',
  now()+interval '30 minutes',
  '{"test":true}'::jsonb,
  'test:layer25:defence-pass',
  now()+interval '2 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_service_admission_v1(
    'foundation.gateway','production','access.evaluate',now()+interval '3 seconds'
  ) into v;

  if v->>'admissionState' <> 'admit' then
    raise exception 'pass posture should admit protected operation: %',v;
  end if;
  if v->>'reasonCode' <> 'dependency-admission-clear' then
    raise exception 'clear admission reason should be explicit: %',v;
  end if;
end;
$$;


insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  gen_random_uuid(),'1.0.0','production','warning',
  now()+interval '10 seconds',
  now()+interval '30 minutes',
  '{"test":true}'::jsonb,
  'test:layer25:defence-warning',
  now()+interval '10 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_service_admission_v1(
    'foundation.gateway','production','access.evaluate',now()+interval '11 seconds'
  ) into v;

  if v->>'admissionState' <> 'admit-degraded' then
    raise exception 'warning posture should admit degraded: %',v;
  end if;
  if v->>'reasonCode' <> 'dependency-degraded' then
    raise exception 'degraded admission reason should be explicit: %',v;
  end if;
end;
$$;


insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  gen_random_uuid(),'1.0.0','production','fail',
  now()+interval '20 seconds',
  now()+interval '30 minutes',
  '{"test":true}'::jsonb,
  'test:layer25:defence-fail',
  now()+interval '20 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_service_admission_v1(
    'foundation.gateway','production','access.evaluate',now()+interval '21 seconds'
  ) into v;

  if v->>'admissionState' <> 'deny' then
    raise exception 'failed Defence guard should deny protected operation: %',v;
  end if;
  if v->>'reasonCode' <> 'dependency-guarded' then
    raise exception 'guard denial reason should be explicit: %',v;
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(v->'dependencyEvidence') x
    where x->>'serviceId'='foundation.defence'
      and x->>'impact'='guarded'
      and x->>'impactScope'='protected-operations'
  ) then
    raise exception 'guard denial must name dependency evidence: %',v;
  end if;
end;
$$;


insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,
  required_for_core,lifecycle,metadata
)
values (
  'test.layer25.hard',
  'Layer 25 Hard Dependency',
  'shine-core',
  'internal-service',
  'test/layer25-hard',
  false,
  'active',
  '{}'::jsonb
);

insert into foundation.service_state_sources(
  service_id,environment,source_version,source_kind,source_config,
  effective_at,evidence_ref,evidence_note
)
values (
  'test.layer25.hard','production','1.0.0','defence-posture','{}'::jsonb,
  now(),'test:layer25:hard-source','Hard dependency fixture.'
);

insert into foundation.service_dependencies(
  dependent_service_id,dependency_service_id,environment,dependency_version,
  dependency_type,impact_scope,failure_mode,description,active,
  effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','test.layer25.hard','production','1.0.0',
  'hard','protected-operations','block',
  'Layer 25 hard dependency fixture.',true,
  now(),'test:layer25:hard-edge','Test only.'
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_service_admission_v1(
    'foundation.gateway','production','access.evaluate',now()+interval '21 seconds'
  ) into v;

  if v->>'admissionState' <> 'deny' or v->>'reasonCode' <> 'dependency-blocked' then
    raise exception 'hard blocked dependency must take precedence: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.evaluate_service_admission_v1(
    'foundation.gateway','production','unbound.operation',now()
  ) into v;

  if v->>'admissionState' <> 'unavailable'
     or v->>'reasonCode' <> 'admission-binding-missing' then
    raise exception 'missing operation binding must fail safe: %',v;
  end if;
end;
$$;


do $$
begin
  begin
    update foundation.service_admission_bindings
    set impact_scope='other-scope'
    where evidence_ref='foundation:admission-binding:gateway:access-evaluate:v1';
    raise exception 'append-only admission binding mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;

  if has_table_privilege('anon','foundation.service_admission_bindings','SELECT') then
    raise exception 'anon must not read admission bindings';
  end if;

  if not has_function_privilege(
    'foundation_gateway',
    'foundation.evaluate_service_admission_v1(text,text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_gateway must execute admission evaluator';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.evaluate_service_admission_v1(text,text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute admission evaluator';
  end if;
end;
$$;

rollback;
