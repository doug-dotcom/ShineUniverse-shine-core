begin;

do $$
begin
  if not foundation.defence_health_contract_matches_v1(
    'json_contains','{"status":"ok"}'::jsonb,null,200,false,null,
    '{"status":"ok","extra":true}'
  ) then
    raise exception 'json_contains adapter should accept a superset object';
  end if;

  if foundation.defence_health_contract_matches_v1(
    'json_contains','{"status":"ok"}'::jsonb,null,200,false,null,
    '{"status":"bad"}'
  ) then
    raise exception 'json_contains adapter accepted the wrong status';
  end if;

  if not foundation.defence_health_contract_matches_v1(
    'text_exact',null,'ok',200,false,null,E' ok\n'
  ) then
    raise exception 'text_exact adapter should trim surrounding whitespace';
  end if;

  if foundation.defence_health_contract_matches_v1(
    'text_exact',null,'ok',500,false,null,'ok'
  ) then
    raise exception 'non-2xx response unexpectedly passed adapter contract';
  end if;
end;
$$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from foundation.current_defence_health_probe_target
  where enabled;

  if v_count<>7 then
    raise exception 'expected seven always-on health adapters, got %',v_count;
  end if;

  if exists (
    select 1 from foundation.current_defence_health_probe_target
    where target_id='railway:dnd'
  ) then
    raise exception 'sleeping D&D service must not be continuously probed';
  end if;
end;
$$;

-- Keep provider/runtime evidence fresh independently of health evidence.
insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
)
select
  target_id,
  case when target_id='railway:dnd' then 'sleeping' else 'active' end,
  'unknown',
  now(),
  now()+interval '4 hours',
  'manual-verified',
  'test:health-adapter:provider:'||target_id,
  '{}'::jsonb
from foundation.defence_estate_targets
where lifecycle='active' and required_for_estate;

do $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_req uuid;
  i integer;
begin
  select * into v_target
  from foundation.current_defence_health_probe_target
  where target_id='railway:daash';

  for i in 1..3 loop
    insert into foundation.defence_health_probe_requests(
      target_id,target_version,external_request_id,target_url,queued_at,evidence_ref,metadata
    ) values (
      v_target.target_id,v_target.target_version,700000+i,v_target.target_url,
      now()-make_interval(mins=>4-i),'test:health-request:healthy:'||i,'{}'::jsonb
    )
    returning probe_request_id into v_req;

    perform foundation.record_defence_health_probe_result_v1(
      v_req,200,false,null,true,
      now()-make_interval(mins=>3-i),
      100+i*10,null,'test:health-result:healthy:'||i,'{}'::jsonb
    );
  end loop;
end;
$$;

do $$
declare
  v jsonb;
  e jsonb;
begin
  select foundation.refresh_defence_health_from_probes_v1('railway:daash',now()) into v;
  if v->>'healthState'<>'healthy'
     or (v->>'sampleCount')::integer<>3
     or (v->>'failureCount')::integer<>0 then
    raise exception 'three passing probes should produce healthy evidence: %',v;
  end if;

  select foundation.get_defence_estate_summary_v1() into e;
  if e->>'state'<>'pass'
     or (e->>'healthCoverageTargets')::integer<>7
     or (e->>'freshHealthTargets')::integer<>1 then
    raise exception 'provider-fresh estate with healthy adapter should pass during startup grace: %',e;
  end if;
end;
$$;

-- Two failures in the same window make the configured target unhealthy.
do $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_req uuid;
  i integer;
begin
  select * into v_target
  from foundation.current_defence_health_probe_target
  where target_id='railway:daash';

  for i in 1..2 loop
    insert into foundation.defence_health_probe_requests(
      target_id,target_version,external_request_id,target_url,queued_at,evidence_ref,metadata
    ) values (
      v_target.target_id,v_target.target_version,700010+i,v_target.target_url,
      now()+make_interval(secs=>i), 'test:health-request:failed:'||i,'{}'::jsonb
    )
    returning probe_request_id into v_req;

    perform foundation.record_defence_health_probe_result_v1(
      v_req,500,false,null,false,
      now()+make_interval(secs=>10+i),
      150+i*10,null,'test:health-result:failed:'||i,'{}'::jsonb
    );
  end loop;
end;
$$;

do $$
declare
  v jsonb;
  e jsonb;
  s jsonb;
begin
  select foundation.refresh_defence_health_from_probes_v1(
    'railway:daash',now()+interval '20 seconds'
  ) into v;

  if v->>'healthState'<>'unhealthy'
     or (v->>'failureCount')::integer<>2 then
    raise exception 'two failures among five probes should be unhealthy: %',v;
  end if;

  select foundation.get_defence_estate_summary_v1() into e;
  if e->>'state'<>'fail'
     or (e->>'degradedOrUnhealthy')::integer<>1 then
    raise exception 'fresh unhealthy adapter evidence must fail estate summary: %',e;
  end if;

  select foundation.run_defence_estate_sentinel_v1(now()+interval '21 seconds') into s;
  if (s->>'activeFailCount')::integer<>1 then
    raise exception 'unhealthy adapter evidence must open one fail incident: %',s;
  end if;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where target_id='railway:daash'
      and reason_code='health-unhealthy'
      and health_observation_id is not null
  ) then
    raise exception 'health incident missing independent health provenance';
  end if;
end;
$$;

-- Provider evidence stays fresh while health evidence expires, proving the
-- two clocks are not allowed to refresh each other.
do $$
declare
  s jsonb;
begin
  select foundation.run_defence_estate_sentinel_v1(now()+interval '30 minutes') into s;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where target_id='railway:daash'
      and state='warning'
      and reason_code='health-observation-stale'
  ) then
    raise exception 'stale health evidence must warn independently of fresh provider evidence: %',s;
  end if;

  if exists (
    select 1
    from foundation.current_defence_estate_incidents
    where target_id='railway:daash'
      and reason_code='stale-observation'
  ) then
    raise exception 'fresh provider evidence was incorrectly marked stale';
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.defence_health_observations','SELECT')
     or has_table_privilege('authenticated','foundation.defence_health_probe_results','SELECT') then
    raise exception 'public roles must not read Defence health evidence';
  end if;

  if has_function_privilege(
      'anon',
      'foundation.defence_health_contract_matches_v1(text,jsonb,text,integer,boolean,text,text)',
      'EXECUTE'
    ) then
    raise exception 'public role unexpectedly executes Defence health matcher';
  end if;

  begin
    update foundation.defence_health_observations
       set health_state='healthy';
    raise exception 'Defence health history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
