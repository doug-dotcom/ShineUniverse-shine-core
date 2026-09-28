begin;

insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,required_for_core,lifecycle
) values (
  'test.collector.layer23',
  'Layer 23 Collector Test',
  'shine-core',
  'internal-service',
  false,
  'active'
);

insert into foundation.service_health_probe_targets(
  service_id,environment,target_version,target_url,
  expected_service,expected_status,expected_schema_version,
  timeout_milliseconds,enabled,evidence_ref
) values (
  'test.collector.layer23','production','1.0.0',
  'https://example.com/health',
  'test-service','ok','1.0.0',
  10000,true,'test:collector-target:v1'
);

insert into foundation.service_health_policies(
  service_id,environment,policy_version,evaluation_window_seconds,max_evidence_age_seconds,
  min_request_count,warning_5xx_rate,critical_5xx_rate,warning_p95_ms,critical_p95_ms,
  warning_runtime_error_count,critical_runtime_error_count,evidence_ref
) values (
  'test.collector.layer23','production','1.0.0',
  3600,600,
  3,0.10,0.50,5000,10000,
  99,100,'test:collector-health-policy:v1'
);

do $$
declare
  v_target uuid;
  v_req uuid;
  v_health jsonb;
  i integer;
begin
  select target_id into v_target
  from foundation.current_service_health_probe_target
  where service_id='test.collector.layer23'
    and environment='production';

  if v_target is null then
    raise exception 'expected isolated collector probe target';
  end if;

  for i in 1..3 loop
    v_req := foundation.record_service_health_probe_request_v1(
      'test.collector.layer23','production',v_target,990000+i,
      'https://example.com/health',
      now()-make_interval(mins=>4-i),
      'test:collector-request:healthy:'||i,
      jsonb_build_object('test',true)
    );

    perform foundation.record_service_health_probe_result_v1(
      v_req,200,false,null,true,
      now()-make_interval(mins=>3-i),
      100+i*10,null,
      'test:collector-result:healthy:'||i,
      jsonb_build_object('test',true)
    );
  end loop;

  perform foundation.refresh_service_health_from_probes_v1(
    'test.collector.layer23','production',clock_timestamp()
  );

  select foundation.get_service_health_v1('test.collector.layer23','production') into v_health;
  if v_health->>'healthState' <> 'healthy' then
    raise exception 'three successful fresh probes should be healthy: %',v_health;
  end if;
end;
$$;

do $$
declare
  v_target uuid;
  v_req uuid;
  v_health jsonb;
begin
  select target_id into v_target
  from foundation.current_service_health_probe_target
  where service_id='test.collector.layer23'
    and environment='production';

  v_req := foundation.record_service_health_probe_request_v1(
    'test.collector.layer23','production',v_target,990010,
    'https://example.com/health',
    clock_timestamp(),
    'test:collector-request:degraded',
    '{}'::jsonb
  );

  perform foundation.record_service_health_probe_result_v1(
    v_req,500,false,null,false,
    clock_timestamp()+interval '1 second',
    150,null,
    'test:collector-result:degraded',
    '{}'::jsonb
  );

  perform foundation.refresh_service_health_from_probes_v1(
    'test.collector.layer23','production',clock_timestamp()+interval '2 seconds'
  );

  select foundation.get_service_health_v1('test.collector.layer23','production') into v_health;
  if v_health->>'healthState' <> 'degraded' then
    raise exception 'one failing probe among four should degrade: %',v_health;
  end if;
  if not (v_health->'reasonCodes' ? 'elevated-5xx-rate') then
    raise exception 'degraded probe failure rate should be explicit: %',v_health;
  end if;
end;
$$;

do $$
declare
  v_target uuid;
  v_req uuid;
  v_health jsonb;
  i integer;
begin
  select target_id into v_target
  from foundation.current_service_health_probe_target
  where service_id='test.collector.layer23'
    and environment='production';

  for i in 1..2 loop
    v_req := foundation.record_service_health_probe_request_v1(
      'test.collector.layer23','production',v_target,990010+i,
      'https://example.com/health',
      clock_timestamp()+make_interval(secs=>i),
      'test:collector-request:unhealthy:'||i,
      '{}'::jsonb
    );

    perform foundation.record_service_health_probe_result_v1(
      v_req,500,false,null,false,
      clock_timestamp()+make_interval(secs=>2+i),
      160,null,
      'test:collector-result:unhealthy:'||i,
      '{}'::jsonb
    );
  end loop;

  perform foundation.refresh_service_health_from_probes_v1(
    'test.collector.layer23','production',clock_timestamp()+interval '5 seconds'
  );

  select foundation.get_service_health_v1('test.collector.layer23','production') into v_health;
  if v_health->>'healthState' <> 'unhealthy' then
    raise exception 'three failing probes among six should be unhealthy: %',v_health;
  end if;
  if not (v_health->'reasonCodes' ? 'critical-5xx-rate') then
    raise exception 'critical probe failure rate should be explicit: %',v_health;
  end if;
end;
$$;

do $$
declare
  v_target uuid;
  v_req uuid;
  v_seq bigint;
begin
  select target_id into v_target
  from foundation.current_service_health_probe_target
  where service_id='test.collector.layer23'
    and environment='production';

  v_req := foundation.record_service_health_probe_request_v1(
    'test.collector.layer23','production',v_target,990099,
    'https://example.com/health',
    clock_timestamp(),
    'test:collector-request:idempotent',
    '{}'::jsonb
  );

  if foundation.record_service_health_probe_request_v1(
    'test.collector.layer23','production',v_target,990099,
    'https://example.com/health',
    clock_timestamp(),
    'test:collector-request:idempotent',
    '{}'::jsonb
  ) <> v_req then
    raise exception 'request replay must return the existing request id';
  end if;

  v_seq := foundation.record_service_health_probe_result_v1(
    v_req,200,false,null,true,clock_timestamp(),100,null,
    'test:collector-result:idempotent','{}'::jsonb
  );

  if foundation.record_service_health_probe_result_v1(
    v_req,200,false,null,true,clock_timestamp(),100,null,
    'test:collector-result:idempotent','{}'::jsonb
  ) <> v_seq then
    raise exception 'result replay must return the existing sequence';
  end if;
end;
$$;

do $$
begin
  begin
    update foundation.service_health_probe_results
    set contract_ok=false
    where evidence_ref='test:collector-result:idempotent';
    raise exception 'append-only probe result update unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;

  if has_table_privilege('anon','foundation.service_health_probe_results','SELECT') then
    raise exception 'anon must not read probe results';
  end if;

  if has_function_privilege(
    'foundation_runtime',
    'foundation.record_service_health_probe_result_v1(uuid,integer,boolean,text,boolean,timestamptz,numeric,text,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must not append probe results';
  end if;
end;
$$;

rollback;
