begin;

do $$
declare
  v jsonb;
begin
  if (select count(*) from foundation.current_defence_health_probe_target where enabled) <> 14 then
    raise exception 'expected 14 Railway health targets';
  end if;

  if (select count(*) from foundation.current_defence_health_probe_target where enabled and probe_mode='continuous') <> 13 then
    raise exception 'expected 13 continuous Railway health targets';
  end if;

  if (select count(*) from foundation.current_defence_health_probe_target where enabled and probe_mode='on_demand') <> 1 then
    raise exception 'expected one on-demand Railway health target';
  end if;

  if not exists (
    select 1
    from foundation.current_defence_health_probe_target
    where target_id='railway:dnd'
      and probe_mode='on_demand'
  ) then
    raise exception 'D&D must be the sleep-aware on-demand target';
  end if;

  select foundation.get_defence_estate_summary_v1() into v;
  if (v->>'healthCoverageTargets')::integer<>14
     or (v->>'continuousHealthTargets')::integer<>13
     or (v->>'onDemandHealthTargets')::integer<>1
     or (v->>'uncoveredRailwayHealthTargets')::integer<>0 then
    raise exception 'health coverage summary incorrect: %',v;
  end if;
end;
$$;


insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
)
select
  target_id,
  case when target_id='railway:dnd' then 'sleeping' else 'active' end,
  'unknown',
  now(),
  now()+interval '2 hours',
  'manual-verified',
  'test:coverage-v2:provider:'||target_id,
  '{}'::jsonb
from foundation.defence_estate_targets
where lifecycle='active' and required_for_estate;


insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,
  avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
)
select
  target_id,
  'healthy',
  3,
  0,
  now()-interval '5 minutes',
  now(),
  100,
  150,
  now(),
  now()+interval '1 hour',
  'test:coverage-v2:health:'||target_id,
  '{"test":true}'::jsonb
from foundation.current_defence_health_probe_target
where enabled and probe_mode='continuous';


do $$
declare
  v jsonb;
begin
  select foundation.get_defence_estate_summary_v1() into v;

  if v->>'state'<>'pass'
     or (v->>'freshTargets')::integer<>20
     or (v->>'freshHealthTargets')::integer<>13
     or (v->>'missingHealthTargets')::integer<>0
     or (v->>'staleHealthTargets')::integer<>0
     or (v->>'uncoveredRailwayHealthTargets')::integer<>0 then
    raise exception 'fully covered estate should pass with D&D unprobed: %',v;
  end if;

  select foundation.run_defence_estate_sentinel_v1(now()+interval '10 minutes') into v;

  if (v->>'activeIncidentCount')::integer<>0 then
    raise exception 'sleep-aware D&D must not create a missing-health incident: %',v;
  end if;
end;
$$;


insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-health-gap',
  'Coverage Gap Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  '{}'::jsonb
);

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
) values (
  'railway:test-health-gap',
  'active',
  'unknown',
  now(),
  now()+interval '2 hours',
  'manual-verified',
  'test:coverage-v2:gap-provider',
  '{}'::jsonb
);

do $$
declare
  v jsonb;
begin
  select foundation.run_defence_estate_sentinel_v1(now()+interval '1 second') into v;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where target_id='railway:test-health-gap'
      and state='warning'
      and reason_code='health-coverage-missing'
  ) then
    raise exception 'uncovered Railway target must create health coverage warning: %',v;
  end if;
end;
$$;


do $$
begin
  if has_table_privilege('anon','foundation.defence_health_probe_targets','SELECT')
     or has_table_privilege('authenticated','foundation.defence_health_observations','SELECT') then
    raise exception 'public roles must not read health coverage controls';
  end if;

  if has_function_privilege(
      'anon',
      'foundation.run_defence_estate_sentinel_v1(timestamptz)',
      'EXECUTE'
    ) then
    raise exception 'public roles must not execute estate Sentinel';
  end if;
end;
$$;

rollback;
