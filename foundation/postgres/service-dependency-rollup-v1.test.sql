begin;

-- Layer 24 depends on Layer 22 health semantics. Seed a fresh healthy Gateway
-- window explicitly so this test proves dependency roll-up behaviour rather
-- than accidentally testing the missing-health-evidence state.
insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,
  window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,
  avg_latency_ms,p95_latency_ms,runtime_error_count,
  evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','71',
  now()-interval '3 minutes',now(),
  3,0,0,
  100,150,0,
  'manual-verified',
  'test:layer24:gateway-healthy',
  'Synthetic fresh healthy Gateway evidence for dependency roll-up acceptance.',
  '{"test":true}'::jsonb,
  now()
);

do $$
declare
  v jsonb;
begin
  select foundation.get_dependency_graph_health_v1('production') into v;
  if v->>'state' <> 'pass' then
    raise exception 'production dependency graph should begin acyclic: %',v;
  end if;

  select foundation.get_service_dependency_rollup_v1(
    'foundation.gateway','production',now()
  ) into v;
  if v->>'effectiveState' <> 'operational' or v->>'safeMode' <> 'normal' then
    raise exception 'healthy Gateway + passing Defence should be operational: %',v;
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
  now()+interval '20 minutes',
  '{"test":true}'::jsonb,
  'test:layer24:defence-warning',
  now()+interval '10 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_dependency_rollup_v1(
    'foundation.gateway','production',now()+interval '11 seconds'
  ) into v;

  if v->>'effectiveState' <> 'degraded' then
    raise exception 'warning Defence posture should degrade guarded scope: %',v;
  end if;

  if not (v->'degradedScopes' ? 'protected-operations') then
    raise exception 'degraded guarded scope should be explicit: %',v;
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
  now()+interval '20 minutes',
  '{"test":true}'::jsonb,
  'test:layer24:defence-fail',
  now()+interval '20 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_dependency_rollup_v1(
    'foundation.gateway','production',now()+interval '21 seconds'
  ) into v;

  if v->>'effectiveState' <> 'guarded' or v->>'safeMode' <> 'guarded' then
    raise exception 'failed Defence posture should fail closed only guarded scope: %',v;
  end if;

  if not (v->'guardedScopes' ? 'protected-operations') then
    raise exception 'fail-closed scope should be explicit: %',v;
  end if;
end;
$$;


insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,
  required_for_core,lifecycle,metadata
)
values
(
  'test.layer24.hard',
  'Layer 24 Hard Dependency',
  'shine-core',
  'internal-service',
  'test/layer24-hard',
  false,
  'active',
  '{}'::jsonb
),
(
  'test.layer24.upper',
  'Layer 24 Upper Service',
  'shine-core',
  'internal-service',
  'test/layer24-upper',
  false,
  'active',
  '{}'::jsonb
);

insert into foundation.service_state_sources(
  service_id,environment,source_version,source_kind,source_config,
  effective_at,evidence_ref,evidence_note
)
values (
  'test.layer24.hard','production','1.0.0','defence-posture','{}'::jsonb,
  now(),'test:layer24:hard-source','test state source'
);

insert into foundation.service_dependencies(
  dependent_service_id,dependency_service_id,environment,dependency_version,
  dependency_type,impact_scope,failure_mode,description,active,
  effective_at,evidence_ref,evidence_note
)
values
(
  'foundation.gateway','test.layer24.hard','production','1.0.0',
  'hard','core-runtime','block',
  'Test hard dependency.',true,
  now(),'test:layer24:hard-edge','test only'
),
(
  'test.layer24.upper','foundation.gateway','production','1.0.0',
  'soft','upper-feature','degrade',
  'Test transitive dependent.',true,
  now(),'test:layer24:upper-edge','test only'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_dependency_rollup_v1(
    'foundation.gateway','production',now()+interval '21 seconds'
  ) into v;

  if v->>'effectiveState' <> 'blocked' then
    raise exception 'failed hard dependency should block dependent service: %',v;
  end if;

  if not (v->'blockedScopes' ? 'core-runtime') then
    raise exception 'blocked hard scope should be explicit: %',v;
  end if;

  select foundation.get_service_blast_radius_v1(
    'foundation.defence','production'
  ) into v;

  if (v->>'affectedCount')::integer < 2 then
    raise exception 'Defence blast radius should include Gateway and transitive upper service: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'affected') x
    where x->>'serviceId'='foundation.gateway'
      and x->>'potentialImpact'='guarded'
  ) then
    raise exception 'Gateway should be guarded in Defence blast radius: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'affected') x
    where x->>'serviceId'='test.layer24.upper'
      and x->>'potentialImpact'='degraded'
  ) then
    raise exception 'soft transitive dependent should degrade in blast radius: %',v;
  end if;
end;
$$;


insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,required_for_core,lifecycle,metadata
)
values
('test.layer24.cycle-a','Cycle A','shine-core','internal-service',false,'active','{}'::jsonb),
('test.layer24.cycle-b','Cycle B','shine-core','internal-service',false,'active','{}'::jsonb);

insert into foundation.service_dependencies(
  dependent_service_id,dependency_service_id,environment,dependency_version,
  dependency_type,impact_scope,failure_mode,description,active,
  effective_at,evidence_ref
)
values
(
  'test.layer24.cycle-a','test.layer24.cycle-b','test-cycle','1.0.0',
  'hard','runtime','block','Cycle test A to B.',true,now(),'test:cycle:a-b'
),
(
  'test.layer24.cycle-b','test.layer24.cycle-a','test-cycle','1.0.0',
  'hard','runtime','block','Cycle test B to A.',true,now(),'test:cycle:b-a'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_dependency_graph_health_v1('test-cycle') into v;
  if v->>'state' <> 'fail' or (v->>'cycleCount')::integer < 1 then
    raise exception 'dependency cycles must be surfaced explicitly: %',v;
  end if;
end;
$$;


do $$
begin
  begin
    update foundation.service_dependencies
    set description='mutation should fail'
    where evidence_ref='test:layer24:hard-edge';
    raise exception 'append-only dependency mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;

  if has_table_privilege('anon','foundation.service_dependencies','SELECT') then
    raise exception 'anon must not read dependency graph';
  end if;

  if has_table_privilege('authenticated','foundation.service_state_sources','SELECT') then
    raise exception 'authenticated must not read state source configuration';
  end if;

  if not has_function_privilege(
    'foundation_runtime',
    'foundation.get_service_dependency_rollup_v1(text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must execute dependency rollup';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.get_service_blast_radius_v1(text,text)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute blast radius reader';
  end if;
end;
$$;

rollback;
