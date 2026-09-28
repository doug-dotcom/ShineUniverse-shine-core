-- Shine Defence federated estate Sentinel v1.
-- Turns the estate target projection into an exception-only lifecycle while
-- preserving the distinction between deployment/runtime evidence and health.

create index if not exists defence_incident_events_posture_observation_idx
  on foundation.defence_incident_events(posture_observation_id);

create table foundation.defence_estate_incident_events (
  event_id uuid primary key default gen_random_uuid(),
  incident_key text not null
    check (incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  target_id text not null references foundation.defence_estate_targets(target_id),
  event_type text not null
    check (event_type in ('opened','changed','recovered')),
  state text not null
    check (state in ('pass','warning','fail')),
  reason_code text not null
    check (reason_code in (
      'healthy',
      'missing-observation',
      'stale-observation',
      'runtime-failure',
      'unexpected-runtime-state',
      'health-degraded',
      'health-unhealthy'
    )),
  observation_id uuid references foundation.defence_estate_observations(observation_id),
  occurred_at timestamptz not null,
  evidence_ref text not null,
  recorded_at timestamptz not null default now(),
  check (
    (event_type='recovered' and state='pass' and reason_code='healthy')
    or
    (event_type in ('opened','changed') and state in ('warning','fail') and reason_code<>'healthy')
  )
);

alter table foundation.defence_estate_incident_events enable row level security;

create policy shine_defence_runtime_estate_incident_events_select
on foundation.defence_estate_incident_events
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_estate_incident_events from public,anon,authenticated;
grant select on foundation.defence_estate_incident_events to shine_defence_runtime,service_role;
grant insert on foundation.defence_estate_incident_events to service_role;

create index defence_estate_incident_events_key_time_idx
  on foundation.defence_estate_incident_events(incident_key,occurred_at desc,recorded_at desc);

create index defence_estate_incident_events_target_time_idx
  on foundation.defence_estate_incident_events(target_id,occurred_at desc);

create index defence_estate_incident_events_observation_idx
  on foundation.defence_estate_incident_events(observation_id);

create trigger defence_estate_incident_events_append_only
before update or delete on foundation.defence_estate_incident_events
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_estate_incident_state
with (security_invoker=true)
as
select distinct on (incident_key)
  event_id,incident_key,target_id,event_type,state,reason_code,
  observation_id,occurred_at,evidence_ref,recorded_at
from foundation.defence_estate_incident_events
order by incident_key,occurred_at desc,recorded_at desc,event_id desc;

revoke all on foundation.current_defence_estate_incident_state from public,anon,authenticated;
grant select on foundation.current_defence_estate_incident_state to shine_defence_runtime,service_role;


create view foundation.current_defence_estate_incidents
with (security_invoker=true)
as
select *
from foundation.current_defence_estate_incident_state
where event_type<>'recovered';

revoke all on foundation.current_defence_estate_incidents from public,anon,authenticated;
grant select on foundation.current_defence_estate_incidents to shine_defence_runtime,service_role;


create or replace function foundation.run_defence_estate_sentinel_v1(
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_obs foundation.defence_estate_observations%rowtype;
  v_prior foundation.defence_estate_incident_events%rowtype;
  v_state text;
  v_reason text;
  v_event_type text;
  v_incident_key text;
  v_created integer := 0;
  v_active integer := 0;
  v_fail integer := 0;
  v_warning integer := 0;
begin
  for v_target in
    select *
    from foundation.defence_estate_targets
    where lifecycle='active'
      and required_for_estate
    order by target_id
  loop
    v_obs := null;

    select o.*
      into v_obs
    from foundation.defence_estate_observations o
    where o.target_id=v_target.target_id
      and o.observed_at<=p_observed_at
    order by o.observed_at desc,o.recorded_at desc,o.observation_id desc
    limit 1;

    if v_obs.observation_id is null then
      v_state := 'warning';
      v_reason := 'missing-observation';
    elsif v_obs.valid_until<=p_observed_at then
      v_state := 'warning';
      v_reason := 'stale-observation';
    elsif v_obs.runtime_state in ('failed','inactive') then
      v_state := 'fail';
      v_reason := 'runtime-failure';
    elsif not (v_obs.runtime_state=any(v_target.allowed_runtime_states)) then
      v_state := 'warning';
      v_reason := 'unexpected-runtime-state';
    elsif v_obs.health_state='unhealthy' then
      v_state := 'fail';
      v_reason := 'health-unhealthy';
    elsif v_obs.health_state='degraded' then
      v_state := 'warning';
      v_reason := 'health-degraded';
    else
      v_state := 'pass';
      v_reason := 'healthy';
    end if;

    v_incident_key := v_target.target_id;
    v_prior := null;

    select i.*
      into v_prior
    from foundation.defence_estate_incident_events i
    where i.incident_key=v_incident_key
    order by i.occurred_at desc,i.recorded_at desc,i.event_id desc
    limit 1;

    v_event_type := null;

    if v_state in ('warning','fail') then
      if v_prior.event_id is null or v_prior.event_type='recovered' then
        v_event_type := 'opened';
      elsif v_prior.state is distinct from v_state
         or v_prior.reason_code is distinct from v_reason then
        v_event_type := 'changed';
      end if;
    elsif v_state='pass'
      and v_prior.event_id is not null
      and v_prior.event_type<>'recovered' then
      v_event_type := 'recovered';
    end if;

    if v_event_type is not null then
      insert into foundation.defence_estate_incident_events(
        incident_key,target_id,event_type,state,reason_code,observation_id,
        occurred_at,evidence_ref
      ) values (
        v_incident_key,v_target.target_id,v_event_type,v_state,v_reason,
        v_obs.observation_id,p_observed_at,'sentinel:shine-defence:estate:v1'
      );
      v_created := v_created+1;
    end if;
  end loop;

  select
    count(*),
    count(*) filter (where state='fail'),
    count(*) filter (where state='warning')
  into v_active,v_fail,v_warning
  from foundation.current_defence_estate_incidents;

  return jsonb_build_object(
    'defenceEstateSentinel','shine-defence/estate-sentinel-run-v1',
    'schemaVersion','1.0.0',
    'observedAt',p_observed_at,
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active,
    'activeFailCount',v_fail,
    'activeWarningCount',v_warning,
    'estate',foundation.get_defence_estate_summary_v1()
  );
end;
$$;

revoke all on function foundation.run_defence_estate_sentinel_v1(timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_defence_estate_sentinel_v1(timestamptz)
  to shine_defence_runtime,service_role;


create or replace function foundation.get_defence_estate_sentinel_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_fail integer := 0;
  v_warning integer := 0;
  v_apps integer := 0;
  v_targets jsonb := '[]'::jsonb;
  v_state text;
begin
  select
    count(*) filter (where i.state='fail'),
    count(*) filter (where i.state='warning'),
    count(distinct a.app_key),
    coalesce(jsonb_agg(
      jsonb_build_object(
        'targetId',i.target_id,
        'state',i.state,
        'reasonCode',i.reason_code,
        'occurredAt',i.occurred_at
      ) order by i.target_id
    ),'[]'::jsonb)
  into v_fail,v_warning,v_apps,v_targets
  from foundation.current_defence_estate_incidents i
  left join foundation.defence_estate_target_apps a
    on a.target_id=i.target_id;

  v_state := case
    when v_fail>0 then 'fail'
    when v_warning>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceEstateSentinelSummary','shine-defence/estate-sentinel-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'activeIncidentCount',v_fail+v_warning,
    'activeFailCount',v_fail,
    'activeWarningCount',v_warning,
    'affectedAppCount',v_apps,
    'activeTargets',v_targets,
    'estate',foundation.get_defence_estate_summary_v1()
  );
end;
$$;

revoke all on function foundation.get_defence_estate_sentinel_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_estate_sentinel_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
