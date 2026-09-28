-- Shine Defence Railway transition Sentinel v1.
-- Best-effort webhook evidence is advisory; serving runtime provenance remains authoritative.

create or replace function foundation.run_defence_railway_transition_sentinel_v1(
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_transition foundation.defence_railway_transition_events%rowtype;
  v_provenance foundation.defence_runtime_provenance_observations%rowtype;
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
    where provider='railway'
      and lifecycle='active'
      and required_for_estate
    order by target_id
  loop
    v_transition := null;
    v_provenance := null;

    select t.* into v_transition
    from foundation.defence_railway_transition_events t
    where t.target_id=v_target.target_id
      and t.occurred_at<=p_observed_at
    order by t.occurred_at desc,t.recorded_at desc,t.event_id desc
    limit 1;

    select p.* into v_provenance
    from foundation.defence_runtime_provenance_observations p
    where p.target_id=v_target.target_id
      and p.observed_at<=p_observed_at
    order by p.observed_at desc,p.recorded_at desc,p.observation_id desc
    limit 1;

    if v_transition.event_id is null then
      continue;
    elsif v_transition.transition_state='crashed'
      and v_provenance.observation_id is not null
      and v_transition.deployment_id::text=v_provenance.deployment_id then
      v_state := 'fail';
      v_reason := 'serving-deployment-crashed';
    elsif v_transition.transition_state='failed'
      and (
        v_provenance.observation_id is null
        or v_transition.deployment_id::text is distinct from v_provenance.deployment_id
      ) then
      v_state := 'warning';
      v_reason := 'release-attempt-failed';
    elsif v_transition.transition_state in (
      'waiting','needs_approval','queued','initializing','building','deploying'
    )
      and v_transition.occurred_at<=p_observed_at-interval '20 minutes' then
      v_state := 'warning';
      v_reason := 'release-transition-stuck';
    elsif v_transition.transition_state='success'
      and (
        v_provenance.observation_id is null
        or v_transition.deployment_id::text is distinct from v_provenance.deployment_id
      )
      and v_transition.occurred_at<=p_observed_at-interval '10 minutes' then
      v_state := 'warning';
      v_reason := 'successful-release-not-serving';
    else
      v_state := 'pass';
      v_reason := 'healthy';
    end if;

    v_incident_key := v_target.target_id||':railway-transition';
    v_prior := null;

    select i.* into v_prior
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
    elsif v_prior.event_id is not null
      and v_prior.event_type<>'recovered' then
      v_event_type := 'recovered';
    end if;

    if v_event_type is not null then
      insert into foundation.defence_estate_incident_events(
        incident_key,target_id,event_type,state,reason_code,
        observation_id,health_observation_id,occurred_at,evidence_ref
      ) values (
        v_incident_key,
        v_target.target_id,
        v_event_type,
        v_state,
        v_reason,
        null,
        null,
        p_observed_at,
        'sentinel:shine-defence:railway-transition:v1'
      );
      v_created := v_created+1;
    end if;
  end loop;

  select
    count(*),
    count(*) filter (where state='fail'),
    count(*) filter (where state='warning')
  into v_active,v_fail,v_warning
  from foundation.current_defence_estate_incidents
  where incident_key like 'railway:%:railway-transition';

  return jsonb_build_object(
    'defenceRailwayTransitionSentinel','shine-defence/railway-transition-sentinel-v1',
    'schemaVersion','1.0.0',
    'observedAt',p_observed_at,
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active,
    'activeFailCount',v_fail,
    'activeWarningCount',v_warning,
    'summary',foundation.get_defence_railway_transition_summary_v1()
  );
end;
$$;

revoke all on function foundation.run_defence_railway_transition_sentinel_v1(timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_defence_railway_transition_sentinel_v1(timestamptz)
  to shine_defence_runtime,service_role;


select cron.schedule(
  'shine-defence-railway-transition-sentinel-5m',
  '1,6,11,16,21,26,31,36,41,46,51,56 * * * *',
  $$select foundation.run_defence_railway_transition_sentinel_v1(now());$$
);
