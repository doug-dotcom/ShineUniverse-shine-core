begin;

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
)
select
  target_id,
  case when target_id='railway:dnd' then 'sleeping' else 'active' end,
  'unknown',
  now(),
  now()+interval '1 hour',
  'manual-verified',
  'test:estate-sentinel:healthy:'||target_id,
  '{}'::jsonb
from foundation.defence_estate_targets
where lifecycle='active' and required_for_estate;

do $$
declare
  v jsonb;
begin
  select foundation.run_defence_estate_sentinel_v1(now()+interval '1 second') into v;
  if (v->>'activeIncidentCount')::integer<>0
     or (v->>'incidentEventsCreated')::integer<>0 then
    raise exception 'healthy/expected estate must be quiet: %',v;
  end if;
end;
$$;

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
) values (
  'railway:fish','failed','unknown',now()+interval '2 seconds',now()+interval '1 hour',
  'manual-verified','test:estate-sentinel:fish-failed','{}'::jsonb
);

do $$
declare
  v jsonb;
  s jsonb;
begin
  select foundation.run_defence_estate_sentinel_v1(now()+interval '3 seconds') into v;
  if (v->>'activeIncidentCount')::integer<>1
     or (v->>'activeFailCount')::integer<>1
     or (v->>'incidentEventsCreated')::integer<>1 then
    raise exception 'runtime failure must open one fail incident: %',v;
  end if;

  select foundation.get_defence_estate_sentinel_summary_v1() into s;
  if s->>'state'<>'fail'
     or (s->>'affectedAppCount')::integer<>1 then
    raise exception 'estate Sentinel summary must expose affected Fish app: %',s;
  end if;
end;
$$;

do $$
declare
  before_events integer;
  after_events integer;
  v jsonb;
begin
  select count(*) into before_events
  from foundation.defence_estate_incident_events
  where incident_key='railway:fish';

  select foundation.run_defence_estate_sentinel_v1(now()+interval '4 seconds') into v;

  select count(*) into after_events
  from foundation.defence_estate_incident_events
  where incident_key='railway:fish';

  if after_events<>before_events
     or (v->>'incidentEventsCreated')::integer<>0 then
    raise exception 'unchanged estate fault must not create duplicate incident noise: %',v;
  end if;
end;
$$;

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
) values (
  'railway:fish','active','unknown',now()+interval '5 seconds',now()+interval '1 hour',
  'manual-verified','test:estate-sentinel:fish-recovered','{}'::jsonb
);

do $$
declare
  v jsonb;
  s jsonb;
begin
  select foundation.run_defence_estate_sentinel_v1(now()+interval '6 seconds') into v;
  if (v->>'activeIncidentCount')::integer<>0
     or (v->>'incidentEventsCreated')::integer<>1 then
    raise exception 'recovered target must close its incident once: %',v;
  end if;

  if not exists (
    select 1
    from foundation.current_defence_estate_incident_state
    where incident_key='railway:fish'
      and event_type='recovered'
      and state='pass'
      and reason_code='healthy'
  ) then
    raise exception 'Fish recovery event missing';
  end if;

  select foundation.get_defence_estate_sentinel_summary_v1() into s;
  if s->>'state'<>'pass' then
    raise exception 'estate Sentinel summary should return pass after recovery: %',s;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.run_defence_estate_sentinel_v1(now()+interval '2 hours') into v;
  if (v->>'activeWarningCount')::integer<>20
     or (v->>'activeFailCount')::integer<>0 then
    raise exception 'expired federation evidence must become stale warnings: %',v;
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.defence_estate_incident_events','SELECT')
     or has_table_privilege('authenticated','foundation.current_defence_estate_incidents','SELECT') then
    raise exception 'public roles must not read federated Sentinel incidents';
  end if;

  if has_function_privilege('anon','foundation.run_defence_estate_sentinel_v1(timestamptz)','EXECUTE')
     or has_function_privilege('authenticated','foundation.get_defence_estate_sentinel_summary_v1()','EXECUTE') then
    raise exception 'public roles must not execute federated Sentinel functions';
  end if;

  if not has_function_privilege('shine_defence_runtime','foundation.run_defence_estate_sentinel_v1(timestamptz)','EXECUTE')
     or not has_function_privilege('foundation_runtime','foundation.get_defence_estate_sentinel_summary_v1()','EXECUTE') then
    raise exception 'internal roles missing federated Sentinel privileges';
  end if;
end;
$$;

do $$
begin
  begin
    update foundation.defence_estate_incident_events
       set evidence_ref='mutation-should-fail';
    raise exception 'federated Sentinel history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
