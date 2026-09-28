-- Shine Defence Sentinel v1.
-- Re-runs the live operational posture, persists every observation, and records
-- only exception lifecycle events (open/change/recovery) for actionable review.

create table foundation.defence_incident_events (
  event_id uuid primary key default gen_random_uuid(),
  incident_key text not null
    check (incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  domain text not null
    check (domain in ('auth','rls','service_to_service','secrets','dependencies','data_exposure','deployment_integrity')),
  event_type text not null
    check (event_type in ('opened','changed','recovered')),
  state text not null
    check (state in ('pass','warning','fail')),
  check_snapshot jsonb not null,
  posture_observation_id uuid not null
    references foundation.defence_posture_observations(observation_id),
  occurred_at timestamptz not null,
  evidence_ref text not null,
  recorded_at timestamptz not null default now(),
  check (jsonb_typeof(check_snapshot)='object'),
  check (
    (event_type='recovered' and state='pass')
    or
    (event_type in ('opened','changed') and state in ('warning','fail'))
  )
);

alter table foundation.defence_incident_events enable row level security;

create policy shine_defence_runtime_incident_events_select
on foundation.defence_incident_events
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_incident_events from public,anon,authenticated;
grant select on foundation.defence_incident_events to shine_defence_runtime,service_role;
grant insert on foundation.defence_incident_events to service_role;

create index defence_incident_events_key_time_idx
  on foundation.defence_incident_events(incident_key,occurred_at desc,recorded_at desc);

create index defence_incident_events_environment_time_idx
  on foundation.defence_incident_events(environment,occurred_at desc);

create trigger defence_incident_events_append_only
before update or delete on foundation.defence_incident_events
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_incident_state
with (security_invoker=true)
as
select distinct on (incident_key)
  event_id,
  incident_key,
  environment,
  domain,
  event_type,
  state,
  check_snapshot,
  posture_observation_id,
  occurred_at,
  evidence_ref,
  recorded_at
from foundation.defence_incident_events
order by incident_key,occurred_at desc,recorded_at desc,event_id desc;

revoke all on foundation.current_defence_incident_state from public,anon,authenticated;
grant select on foundation.current_defence_incident_state to shine_defence_runtime,service_role;


create view foundation.current_defence_incidents
with (security_invoker=true)
as
select *
from foundation.current_defence_incident_state
where event_type<>'recovered';

revoke all on foundation.current_defence_incidents from public,anon,authenticated;
grant select on foundation.current_defence_incidents to shine_defence_runtime,service_role;


create or replace function foundation.run_defence_sentinel_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_posture jsonb;
  v_posture_id uuid;
  v_entry record;
  v_domain text;
  v_state text;
  v_incident_key text;
  v_prior foundation.defence_incident_events%rowtype;
  v_event_type text;
  v_created integer := 0;
  v_active integer := 0;
begin
  if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'invalid-defence-environment' using errcode='22023';
  end if;

  v_posture := foundation.record_defence_posture_v1(
    p_environment,
    p_observed_at,
    p_observed_at+interval '2 hours',
    'sentinel:foundation:defence:v1'
  );

  v_posture_id := (v_posture->>'observationId')::uuid;

  for v_entry in
    select key,value
    from jsonb_each(v_posture->'checks')
  loop
    v_domain := case v_entry.key
      when 'auth' then 'auth'
      when 'rls' then 'rls'
      when 'serviceToService' then 'service_to_service'
      when 'secrets' then 'secrets'
      when 'dependencies' then 'dependencies'
      when 'dataExposure' then 'data_exposure'
      when 'deploymentIntegrity' then 'deployment_integrity'
      else null
    end;

    if v_domain is null then
      continue;
    end if;

    v_state := v_entry.value->>'state';
    if v_state not in ('pass','warning','fail') then
      raise exception 'invalid-defence-domain-state: %',v_entry.key using errcode='22023';
    end if;

    v_incident_key := p_environment||':'||v_domain;
    v_prior := null;

    select *
      into v_prior
    from foundation.defence_incident_events
    where incident_key=v_incident_key
    order by occurred_at desc,recorded_at desc,event_id desc
    limit 1;

    v_event_type := null;

    if v_state in ('warning','fail') then
      if v_prior.event_id is null or v_prior.event_type='recovered' then
        v_event_type := 'opened';
      elsif v_prior.state is distinct from v_state
         or v_prior.check_snapshot is distinct from v_entry.value then
        v_event_type := 'changed';
      end if;
    elsif v_state='pass'
      and v_prior.event_id is not null
      and v_prior.event_type<>'recovered' then
      v_event_type := 'recovered';
    end if;

    if v_event_type is not null then
      insert into foundation.defence_incident_events(
        incident_key,
        environment,
        domain,
        event_type,
        state,
        check_snapshot,
        posture_observation_id,
        occurred_at,
        evidence_ref
      ) values (
        v_incident_key,
        p_environment,
        v_domain,
        v_event_type,
        v_state,
        v_entry.value,
        v_posture_id,
        p_observed_at,
        'sentinel:foundation:defence:v1'
      );
      v_created := v_created+1;
    end if;
  end loop;

  select count(*)
    into v_active
  from foundation.current_defence_incidents
  where environment=p_environment;

  return jsonb_build_object(
    'defenceSentinel','shine-defence/sentinel-run-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'overallState',v_posture->>'overallState',
    'postureObservationId',v_posture_id,
    'observedAt',p_observed_at,
    'validUntil',v_posture->>'validUntil',
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active
  );
end;
$$;

revoke all on function foundation.run_defence_sentinel_v1(text,timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_defence_sentinel_v1(text,timestamptz)
  to shine_defence_runtime,service_role;


create or replace function foundation.get_defence_sentinel_summary_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_posture foundation.defence_posture_observations%rowtype;
  v_active integer := 0;
  v_domains jsonb := '[]'::jsonb;
begin
  select p.*
    into v_posture
  from foundation.defence_posture_observations p
  where p.environment=p_environment
  order by p.observed_at desc,p.recorded_at desc,p.observation_id desc
  limit 1;

  select
    count(*),
    coalesce(jsonb_agg(domain order by domain),'[]'::jsonb)
  into v_active,v_domains
  from foundation.current_defence_incidents
  where environment=p_environment;

  if v_posture.observation_id is null then
    return jsonb_build_object(
      'defenceSentinelSummary','shine-defence/sentinel-summary-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'state','unknown',
      'stale',true,
      'activeIncidentCount',v_active,
      'activeDomains',v_domains
    );
  end if;

  return jsonb_build_object(
    'defenceSentinelSummary','shine-defence/sentinel-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'state',v_posture.overall_state,
    'stale',v_posture.valid_until<=now(),
    'observedAt',v_posture.observed_at,
    'validUntil',v_posture.valid_until,
    'activeIncidentCount',v_active,
    'activeDomains',v_domains
  );
end;
$$;

revoke all on function foundation.get_defence_sentinel_summary_v1(text)
  from public,anon,authenticated;
grant execute on function foundation.get_defence_sentinel_summary_v1(text)
  to foundation_runtime,shine_defence_runtime,service_role;
