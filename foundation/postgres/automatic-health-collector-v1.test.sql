begin;

do $$
declare
  v_target uuid;
  v_req uuid;
  v_health jsonb;
  i integer;
begin
  select target_id into v_target
  from foundation.current_service_health_probe_target
  where service_id='foundation.gateway'
    and environment='production';

  if v_target is null then
    raise exception 'expected Foundation Gateway probe target';
  end if;

  for i in 1..3 loop
    v_req := foundation.record_service_health_probe_request_v1(
      'foundation.gateway','production',v_target,900000+i,
      'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/foundation-gateway/health',
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
    'foundation.gateway','production',now()
  );

  select foundation.get_service_health_v1('foundation.gateway','production') into v_health;
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
  where service_id='foundation.gateway'
    and environment='production';

  v_req := foundation.record_service_health_probe_request_v1(
    'foundation.gateway','production',v_target,900010,
    'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/foundation-gateway/health',
    now()+interval '1 second',
    'test:collector-request:degraded',
    '{}'::jsonb
  );

  perform foundation.record_service_health_probe_result_v1(
    v_req,500,false,null,false,
    now()+interval '2 seconds',
    150,null,
    'test:collector-result:degraded',
    '{}'::jsonb
  );

  perform foundation.refresh_service_health_from_probes_v1(
    'foundation.gateway','production',now()+interval '3 seconds'
  );

  select foundation.get_service_health_v1('foundation.gateway','production') into v_health;
  if v_health->>'healthState' <> 'degraded' then
    raise exception 'one failing probe among four should degrade: %',v_health;
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
  where service_id='foundation.gateway'
    and environment='production';

  for i in 1..2 loop
    v_req := foundation.record_service_health_probe_request_v1(
      'foundation.gateway','production',v_target,900010+i,
      'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/foundation-gateway/health',
      now()+make_interval(secs=>3+i),
      'test:collector-request:unhealthy:'||i,
      '{}'::jsonb
    );

    perform foundation.record_service_health_probe_result_v1(
      v_req,500,false,null,false,
      now()+make_interval(secs=>5+i),
      160,null,
      'test:collector-result:unhealthy:'||i,
      '{}'::jsonb
    );
  end loop;

  perform foundation.refresh_service_health_from_probes_v1(
    'foundation.gateway','production',now()+interval '8 seconds'
  );

  select foundation.get_service_health_v1('foundation.gateway','production') into v_health;
  if v_health->>'healthState' <> 'unhealthy' then
    raise exception 'three failing probes among six should be unhealthy: %',v_health;
  end if;
  if not (v_health->'reasonCodes' ? 'critical-5xx-rate') then
    raise exception 'critical probe failures should be explained: %',v_health;
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
  where service_id='foundation.gateway'
    and environment='production';

  v_req := foundation.record_service_health_probe_request_v1(
    'foundation.gateway','production',v_target,900099,
    'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/foundation-gateway/health',
    now(),
    'test:collector-request:idempotent',
    '{}'::jsonb
  );

  if foundation.record_service_health_probe_request_v1(
    'foundation.gateway','production',v_target,900099,
    'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/foundation-gateway/health',
    now(),
    'test:collector-request:idempotent',
    '{}'::jsonb
  ) <> v_req then
    raise exception 'request replay must return the existing request id';
  end if;

  v_seq := foundation.record_service_health_probe_result_v1(
    v_req,200,false,null,true,now(),100,null,
    'test:collector-result:idempotent','{}'::jsonb
  );

  if foundation.record_service_health_probe_result_v1(
    v_req,200,false,null,true,now(),100,null,
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
