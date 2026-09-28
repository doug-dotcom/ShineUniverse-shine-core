-- Shine Defence estate health coverage v2.
-- Closes Railway health coverage while preserving sleep-aware services.

alter table foundation.defence_health_probe_targets
  add column if not exists probe_mode text not null default 'continuous';

alter table foundation.defence_health_probe_targets
  drop constraint if exists defence_health_probe_targets_probe_mode_check;

alter table foundation.defence_health_probe_targets
  add constraint defence_health_probe_targets_probe_mode_check
  check (probe_mode in ('continuous','on_demand'));

create or replace view foundation.current_defence_health_probe_target
with (security_invoker=true)
as
select distinct on (target_id)
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,
  startup_grace_seconds,enabled,effective_at,evidence_ref,evidence_note,recorded_at,
  probe_mode
from foundation.defence_health_probe_targets
order by target_id,effective_at desc,recorded_at desc,target_version desc;

revoke all on foundation.current_defence_health_probe_target from public,anon,authenticated;
grant select on foundation.current_defence_health_probe_target to shine_defence_runtime,service_role;


insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values
  (
    '2.0.0','railway:fish',
    'https://shine-fish-production.up.railway.app/health',
    'json_contains','{"status":"ok","app":"shine-fish"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-fish:v2',
    'Existing production /health endpoint, verified from Foundation via pg_net.',
    'continuous'
  ),
  (
    '2.0.0','railway:punt49',
    'https://punt-49-chat-production.up.railway.app/health',
    'json_contains','{"ok":true,"service":"punt49","web":true}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-punt49:v2',
    'Existing unauthenticated production /health endpoint.',
    'continuous'
  ),
  (
    '2.0.0','railway:rivers',
    'https://shine-music-production.up.railway.app/health',
    'json_contains','{"service":"shine-music","status":"ok","schemaVersion":"1.0.0"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-rivers:v2',
    'Canonical Shine Music health endpoint added for estate monitoring.',
    'continuous'
  ),
  (
    '2.0.0','railway:ski',
    'https://shine-ski-production.up.railway.app/healthz',
    'json_contains','{"status":"ok","app":"Shine Ski"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-ski:v2',
    'Existing production /healthz endpoint, verified from Foundation via pg_net.',
    'continuous'
  ),
  (
    '2.0.0','railway:translate',
    'https://shine-translate-production.up.railway.app/health',
    'json_contains','{"service":"shine-translate","status":"ok","schemaVersion":"1.0.0"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-translate:v2',
    'Canonical Shine Translate health endpoint added for estate monitoring.',
    'continuous'
  ),
  (
    '2.0.0','railway:travel',
    'https://shine-travel-sherpa-production.up.railway.app/health',
    'json_contains','{"ok":true,"app":"Shine Travel"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-travel:v2',
    'Existing production /health endpoint, verified from Foundation via pg_net.',
    'continuous'
  ),
  (
    '2.0.0','railway:dnd',
    'https://shine-dnd-capability-production.up.railway.app/health',
    'json_contains','{"service":"shine-dnd-capability","status":"ok","schemaVersion":"1.0.0"}'::jsonb,null,
    10000,1200,600,1,1,1,1200,true,now(),
    'defence:health-target:railway-dnd:v2',
    'Sleep-aware on-demand health target. It is intentionally excluded from continuous probes.',
    'on_demand'
  );


update foundation.defence_estate_targets
set metadata = metadata || case target_id
  when 'railway:dnd' then '{"healthMonitoringMode":"on_demand","sleepAware":true}'::jsonb
  else '{"healthMonitoringMode":"continuous"}'::jsonb
end,
updated_at=now()
where provider='railway'
  and lifecycle='active';


create or replace function foundation.get_defence_estate_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_targets integer := 0;
  v_apps integer := 0;
  v_fresh integer := 0;
  v_missing integer := 0;
  v_stale integer := 0;
  v_runtime_bad integer := 0;
  v_runtime_unexpected integer := 0;
  v_health_bad integer := 0;
  v_health_unknown integer := 0;
  v_health_coverage integer := 0;
  v_continuous_health integer := 0;
  v_on_demand_health integer := 0;
  v_fresh_health integer := 0;
  v_missing_health integer := 0;
  v_stale_health integer := 0;
  v_uncovered_railway integer := 0;
  v_state text;
  v_problem_targets jsonb := '[]'::jsonb;
begin
  select count(*)
    into v_targets
  from foundation.defence_estate_targets
  where lifecycle='active' and required_for_estate;

  select count(distinct a.app_key)
    into v_apps
  from foundation.defence_estate_target_apps a
  join foundation.defence_estate_targets t using(target_id)
  where t.lifecycle='active' and t.required_for_estate;

  with estate as (
    select
      t.*,
      o.observation_id as provider_observation_id,
      o.runtime_state,
      o.health_state as provider_health_state,
      o.observed_at as provider_observed_at,
      o.valid_until as provider_valid_until,
      hp.enabled as health_probe_enabled,
      hp.probe_mode as health_probe_mode,
      hp.effective_at as health_probe_effective_at,
      hp.startup_grace_seconds,
      h.observation_id as health_observation_id,
      h.health_state as probe_health_state,
      h.observed_at as health_observed_at,
      h.valid_until as health_valid_until,
      case
        when h.observation_id is not null and h.valid_until>now() then h.health_state
        when o.observation_id is not null and o.valid_until>now() then o.health_state
        else 'unknown'
      end as effective_health_state
    from foundation.defence_estate_targets t
    left join foundation.current_defence_estate_observations o using(target_id)
    left join foundation.current_defence_health_probe_target hp using(target_id)
    left join foundation.current_defence_health_observations h using(target_id)
    where t.lifecycle='active' and t.required_for_estate
  )
  select
    count(*) filter (where provider_observation_id is not null and provider_valid_until>now()),
    count(*) filter (where provider_observation_id is null),
    count(*) filter (where provider_observation_id is not null and provider_valid_until<=now()),
    count(*) filter (where runtime_state in ('failed','inactive')),
    count(*) filter (
      where provider_observation_id is not null
        and runtime_state<>all(allowed_runtime_states)
        and runtime_state not in ('failed','inactive')
    ),
    count(*) filter (where effective_health_state in ('degraded','unhealthy')),
    count(*) filter (where effective_health_state='unknown'),
    count(*) filter (where health_probe_enabled),
    count(*) filter (where health_probe_enabled and health_probe_mode='continuous'),
    count(*) filter (where health_probe_enabled and health_probe_mode='on_demand'),
    count(*) filter (where health_probe_enabled and health_observation_id is not null and health_valid_until>now()),
    count(*) filter (
      where health_probe_enabled
        and health_probe_mode='continuous'
        and health_observation_id is null
        and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    ),
    count(*) filter (
      where health_probe_enabled
        and health_probe_mode='continuous'
        and health_observation_id is not null
        and health_valid_until<=now()
        and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    ),
    count(*) filter (
      where provider='railway'
        and coalesce(health_probe_enabled,false)=false
    )
  into
    v_fresh,v_missing,v_stale,v_runtime_bad,v_runtime_unexpected,
    v_health_bad,v_health_unknown,v_health_coverage,v_continuous_health,
    v_on_demand_health,v_fresh_health,v_missing_health,v_stale_health,
    v_uncovered_railway
  from estate;

  with estate as (
    select
      t.*,
      o.observation_id as provider_observation_id,
      o.runtime_state,
      o.health_state as provider_health_state,
      o.observed_at as provider_observed_at,
      o.valid_until as provider_valid_until,
      hp.enabled as health_probe_enabled,
      hp.probe_mode as health_probe_mode,
      hp.effective_at as health_probe_effective_at,
      hp.startup_grace_seconds,
      h.observation_id as health_observation_id,
      h.health_state as probe_health_state,
      h.observed_at as health_observed_at,
      h.valid_until as health_valid_until,
      case
        when h.observation_id is not null and h.valid_until>now() then h.health_state
        when o.observation_id is not null and o.valid_until>now() then o.health_state
        else 'unknown'
      end as effective_health_state
    from foundation.defence_estate_targets t
    left join foundation.current_defence_estate_observations o using(target_id)
    left join foundation.current_defence_health_probe_target hp using(target_id)
    left join foundation.current_defence_health_observations h using(target_id)
    where t.lifecycle='active' and t.required_for_estate
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'targetId',target_id,
      'provider',provider,
      'runtimeState',coalesce(runtime_state,'unknown'),
      'healthState',effective_health_state,
      'healthMonitoringMode',health_probe_mode,
      'providerObservedAt',provider_observed_at,
      'providerValidUntil',provider_valid_until,
      'healthObservedAt',health_observed_at,
      'healthValidUntil',health_valid_until,
      'reason',case
        when provider_observation_id is null then 'missing-observation'
        when provider_valid_until<=now() then 'stale-observation'
        when runtime_state in ('failed','inactive') then 'runtime-failure'
        when runtime_state<>all(allowed_runtime_states) then 'unexpected-runtime-state'
        when provider='railway' and coalesce(health_probe_enabled,false)=false then 'health-coverage-missing'
        when effective_health_state='unhealthy' then 'health-unhealthy'
        when effective_health_state='degraded' then 'health-degraded'
        when health_probe_enabled
          and health_probe_mode='continuous'
          and health_observation_id is null
          and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
          then 'health-observation-missing'
        when health_probe_enabled
          and health_probe_mode='continuous'
          and health_observation_id is not null
          and health_valid_until<=now()
          and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
          then 'health-observation-stale'
        else 'unknown'
      end
    ) order by target_id
  ),'[]'::jsonb)
  into v_problem_targets
  from estate
  where
    provider_observation_id is null
    or provider_valid_until<=now()
    or runtime_state in ('failed','inactive')
    or runtime_state<>all(allowed_runtime_states)
    or (provider='railway' and coalesce(health_probe_enabled,false)=false)
    or effective_health_state in ('degraded','unhealthy')
    or (
      health_probe_enabled
      and health_probe_mode='continuous'
      and health_observation_id is null
      and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    )
    or (
      health_probe_enabled
      and health_probe_mode='continuous'
      and health_observation_id is not null
      and health_valid_until<=now()
      and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    );

  v_state := case
    when v_runtime_bad>0 or v_health_bad>0 then 'fail'
    when v_missing>0 or v_stale>0 or v_runtime_unexpected>0
      or v_missing_health>0 or v_stale_health>0 or v_uncovered_railway>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceEstateSummary','shine-defence/estate-summary-v1',
    'schemaVersion','1.2.0',
    'state',v_state,
    'requiredTargets',v_targets,
    'mappedApps',v_apps,
    'freshTargets',v_fresh,
    'missingTargets',v_missing,
    'staleTargets',v_stale,
    'runtimeFailures',v_runtime_bad,
    'unexpectedRuntimeStates',v_runtime_unexpected,
    'degradedOrUnhealthy',v_health_bad,
    'unknownHealth',v_health_unknown,
    'healthCoverageTargets',v_health_coverage,
    'continuousHealthTargets',v_continuous_health,
    'onDemandHealthTargets',v_on_demand_health,
    'freshHealthTargets',v_fresh_health,
    'missingHealthTargets',v_missing_health,
    'staleHealthTargets',v_stale_health,
    'uncoveredRailwayHealthTargets',v_uncovered_railway,
    'problemTargets',v_problem_targets,
    'evaluatedAt',now()
  );
end;
$$;


alter table foundation.defence_estate_incident_events
  drop constraint if exists defence_estate_incident_events_reason_code_check;

alter table foundation.defence_estate_incident_events
  add constraint defence_estate_incident_events_reason_code_check
  check (reason_code in (
    'healthy',
    'missing-observation',
    'stale-observation',
    'runtime-failure',
    'unexpected-runtime-state',
    'health-coverage-missing',
    'health-degraded',
    'health-unhealthy',
    'health-observation-missing',
    'health-observation-stale'
  ));


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
  v_health_target foundation.defence_health_probe_targets%rowtype;
  v_health foundation.defence_health_observations%rowtype;
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
    v_health_target := null;
    v_health := null;

    select o.*
      into v_obs
    from foundation.defence_estate_observations o
    where o.target_id=v_target.target_id
      and o.observed_at<=p_observed_at
    order by o.observed_at desc,o.recorded_at desc,o.observation_id desc
    limit 1;

    select hp.*
      into v_health_target
    from foundation.current_defence_health_probe_target hp
    where hp.target_id=v_target.target_id
      and hp.enabled;

    select h.*
      into v_health
    from foundation.defence_health_observations h
    where h.target_id=v_target.target_id
      and h.observed_at<=p_observed_at
    order by h.observed_at desc,h.recorded_at desc,h.observation_id desc
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
    elsif v_target.provider='railway'
      and v_health_target.target_id is null then
      v_state := 'warning';
      v_reason := 'health-coverage-missing';
    elsif v_health_target.target_id is not null
      and v_health_target.probe_mode='continuous'
      and p_observed_at > v_health_target.effective_at + make_interval(secs=>v_health_target.startup_grace_seconds)
      and v_health.observation_id is null then
      v_state := 'warning';
      v_reason := 'health-observation-missing';
    elsif v_health_target.target_id is not null
      and v_health_target.probe_mode='continuous'
      and p_observed_at > v_health_target.effective_at + make_interval(secs=>v_health_target.startup_grace_seconds)
      and v_health.observation_id is not null
      and v_health.valid_until<=p_observed_at then
      v_state := 'warning';
      v_reason := 'health-observation-stale';
    elsif v_health.observation_id is not null
      and v_health.valid_until>p_observed_at
      and v_health.health_state='unhealthy' then
      v_state := 'fail';
      v_reason := 'health-unhealthy';
    elsif v_health.observation_id is not null
      and v_health.valid_until>p_observed_at
      and v_health.health_state='degraded' then
      v_state := 'warning';
      v_reason := 'health-degraded';
    elsif v_health.observation_id is null
      and v_obs.health_state='unhealthy' then
      v_state := 'fail';
      v_reason := 'health-unhealthy';
    elsif v_health.observation_id is null
      and v_obs.health_state='degraded' then
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
        incident_key,target_id,event_type,state,reason_code,
        observation_id,health_observation_id,occurred_at,evidence_ref
      ) values (
        v_incident_key,v_target.target_id,v_event_type,v_state,v_reason,
        v_obs.observation_id,v_health.observation_id,p_observed_at,
        'sentinel:shine-defence:estate:v1'
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
    'schemaVersion','1.2.0',
    'observedAt',p_observed_at,
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active,
    'activeFailCount',v_fail,
    'activeWarningCount',v_warning,
    'estate',foundation.get_defence_estate_summary_v1()
  );
end;
$$;
