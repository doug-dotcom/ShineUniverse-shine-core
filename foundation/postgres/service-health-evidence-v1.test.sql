begin;

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note
) values (
  'foundation.gateway','production','71',
  now()-interval '1 hour',now(),
  100,4,0,1200,2200,
  0,'manual-verified','test:gateway-health:healthy','healthy fixture'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_health_v1('foundation.gateway','production') into v;
  if v->>'healthState' <> 'healthy' then
    raise exception 'fresh low-error evidence should be healthy: %',v;
  end if;

  select foundation.get_service_state_v1('foundation.gateway','production') into v;
  if v->>'operationalState' <> 'operational' then
    raise exception 'aligned deployment + healthy evidence should be operational: %',v;
  end if;
end;
$$;

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note
) values (
  'foundation.gateway','production','71',
  now()-interval '59 minutes',now()+interval '1 second',
  100,0,2,1200,2200,
  0,'manual-verified','test:gateway-health:degraded','degraded fixture'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_health_v1('foundation.gateway','production') into v;
  if v->>'healthState' <> 'degraded' then
    raise exception '2 percent 5xx should be degraded under v1 policy: %',v;
  end if;
  if not (v->'reasonCodes' ? 'elevated-5xx-rate') then
    raise exception 'degraded health should explain elevated 5xx rate: %',v;
  end if;
end;
$$;

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note
) values (
  'foundation.gateway','production','71',
  now()-interval '58 minutes',now()+interval '2 seconds',
  100,0,6,1200,2200,
  0,'manual-verified','test:gateway-health:unhealthy','unhealthy fixture'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_health_v1('foundation.gateway','production') into v;
  if v->>'healthState' <> 'unhealthy' then
    raise exception '6 percent 5xx should be unhealthy under v1 policy: %',v;
  end if;
  if not (v->'reasonCodes' ? 'critical-5xx-rate') then
    raise exception 'unhealthy health should explain critical 5xx rate: %',v;
  end if;

  select foundation.get_foundation_health_v1('production') into v;
  if v->>'operationalState' <> 'unhealthy' then
    raise exception 'required unhealthy service should make Foundation unhealthy: %',v;
  end if;
end;
$$;

insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,required_for_core,lifecycle
) values (
  'test.stale-health','Stale Health Test','shine-core','internal-service',false,'active'
);

insert into foundation.service_health_policies(
  service_id,environment,policy_version,evaluation_window_seconds,max_evidence_age_seconds,
  min_request_count,warning_5xx_rate,critical_5xx_rate,warning_p95_ms,critical_p95_ms,
  warning_runtime_error_count,critical_runtime_error_count,evidence_ref
) values (
  'test.stale-health','production','1.0.0',3600,900,
  20,0.01,0.05,8000,15000,
  1,5,'test:stale-health-policy'
);

insert into foundation.service_health_evidence(
  service_id,environment,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref
) values (
  'test.stale-health','production',
  now()-interval '2 hours',now()-interval '30 minutes',
  100,0,0,1000,
  0,'manual-verified','test:stale-health-evidence'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_health_v1('test.stale-health','production') into v;
  if v->>'healthState' <> 'unknown' then
    raise exception 'stale evidence must return unknown: %',v;
  end if;
  if not (v->'reasonCodes' ? 'health-evidence-stale') then
    raise exception 'stale evidence reason should be explicit: %',v;
  end if;
end;
$$;

do $$
begin
  begin
    update foundation.service_health_evidence
       set evidence_note='mutation should fail'
     where evidence_ref='test:gateway-health:healthy';
    raise exception 'append-only health evidence update unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.service_health_evidence','SELECT') then
    raise exception 'anon must not read service health evidence';
  end if;
  if has_table_privilege('authenticated','foundation.service_health_policies','SELECT') then
    raise exception 'authenticated must not read service health policy';
  end if;
  if not has_function_privilege('foundation_runtime','foundation.get_service_health_v1(text,text)','EXECUTE') then
    raise exception 'foundation_runtime must execute service health reader';
  end if;
  if not has_function_privilege('foundation_runtime','foundation.get_service_state_v1(text,text)','EXECUTE') then
    raise exception 'foundation_runtime must execute service state reader';
  end if;
  if not has_function_privilege('foundation_runtime','foundation.get_foundation_health_v1(text)','EXECUTE') then
    raise exception 'foundation_runtime must execute Foundation health reader';
  end if;
  if has_function_privilege('anon','foundation.get_service_health_v1(text,text)','EXECUTE') then
    raise exception 'anon must not execute service health reader';
  end if;
end;
$$;

set local role foundation_runtime;
select foundation.get_service_health_v1('foundation.gateway','production');
select foundation.get_service_state_v1('foundation.gateway','production');
select foundation.get_foundation_health_v1('production');
reset role;

rollback;
