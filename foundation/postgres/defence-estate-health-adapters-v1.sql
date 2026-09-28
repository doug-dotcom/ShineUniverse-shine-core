-- Shine Defence estate health adapters v1.
-- Keeps provider/runtime freshness independent from health freshness and
-- normalises existing app-specific public health endpoints without weakening
-- Foundation's canonical service-health contract.

create table foundation.defence_health_probe_targets (
  target_version text not null,
  target_id text not null references foundation.defence_estate_targets(target_id),
  target_url text not null
    check (target_url ~ '^https://'),
  response_mode text not null
    check (response_mode in ('json_contains','text_exact')),
  expected_json jsonb,
  expected_text text,
  timeout_milliseconds integer not null default 10000
    check (timeout_milliseconds between 1000 and 30000),
  evaluation_window_seconds integer not null default 1200
    check (evaluation_window_seconds between 300 and 86400),
  max_evidence_age_seconds integer not null default 600
    check (max_evidence_age_seconds between 60 and 86400),
  min_samples integer not null default 3
    check (min_samples between 1 and 100),
  degraded_failure_count integer not null default 1
    check (degraded_failure_count >= 1),
  unhealthy_failure_count integer not null default 2
    check (unhealthy_failure_count >= 1),
  startup_grace_seconds integer not null default 1200
    check (startup_grace_seconds between 60 and 86400),
  enabled boolean not null default true,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  primary key(target_id,target_version),
  check (unhealthy_failure_count >= degraded_failure_count),
  check (
    (response_mode='json_contains'
      and expected_json is not null
      and jsonb_typeof(expected_json)='object'
      and expected_json <> '{}'::jsonb
      and expected_text is null)
    or
    (response_mode='text_exact'
      and expected_text is not null
      and length(btrim(expected_text)) between 1 and 512
      and expected_json is null)
  )
);

alter table foundation.defence_health_probe_targets enable row level security;

create policy shine_defence_runtime_health_probe_targets_select
on foundation.defence_health_probe_targets
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_health_probe_targets from public,anon,authenticated;
grant select on foundation.defence_health_probe_targets to shine_defence_runtime,service_role;
grant select,insert on foundation.defence_health_probe_targets to service_role;

create index defence_health_probe_targets_current_idx
  on foundation.defence_health_probe_targets(target_id,effective_at desc,recorded_at desc);

create trigger defence_health_probe_targets_append_only
before update or delete on foundation.defence_health_probe_targets
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_health_probe_target
with (security_invoker=true)
as
select distinct on (target_id)
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,
  startup_grace_seconds,enabled,effective_at,evidence_ref,evidence_note,recorded_at
from foundation.defence_health_probe_targets
order by target_id,effective_at desc,recorded_at desc,target_version desc;

revoke all on foundation.current_defence_health_probe_target from public,anon,authenticated;
grant select on foundation.current_defence_health_probe_target to shine_defence_runtime,service_role;


create table foundation.defence_health_probe_requests (
  probe_request_id uuid primary key default gen_random_uuid(),
  target_id text not null,
  target_version text not null,
  external_request_id bigint,
  target_url text not null,
  queued_at timestamptz not null default now(),
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  foreign key(target_id,target_version)
    references foundation.defence_health_probe_targets(target_id,target_version),
  unique(external_request_id),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_health_probe_requests enable row level security;

create policy shine_defence_runtime_health_probe_requests_select
on foundation.defence_health_probe_requests
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_health_probe_requests from public,anon,authenticated;
grant select on foundation.defence_health_probe_requests to shine_defence_runtime,service_role;
grant select,insert on foundation.defence_health_probe_requests to service_role;

create index defence_health_probe_requests_target_idx
  on foundation.defence_health_probe_requests(target_id,queued_at desc);

create index defence_health_probe_requests_target_version_idx
  on foundation.defence_health_probe_requests(target_id,target_version);

create trigger defence_health_probe_requests_append_only
before update or delete on foundation.defence_health_probe_requests
for each row execute function foundation.reject_append_only_mutation();


create table foundation.defence_health_probe_results (
  result_sequence bigint generated always as identity primary key,
  probe_result_id uuid not null unique default gen_random_uuid(),
  probe_request_id uuid not null unique
    references foundation.defence_health_probe_requests(probe_request_id),
  target_id text not null references foundation.defence_estate_targets(target_id),
  http_status integer,
  timed_out boolean not null default false,
  error_message text,
  contract_ok boolean not null default false,
  response_at timestamptz not null,
  roundtrip_ms numeric(12,3)
    check (roundtrip_ms is null or roundtrip_ms >= 0),
  response_sha256 text
    check (response_sha256 is null or response_sha256 ~ '^[a-fA-F0-9]{64}$'),
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (http_status is null or http_status between 100 and 599),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_health_probe_results enable row level security;

create policy shine_defence_runtime_health_probe_results_select
on foundation.defence_health_probe_results
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_health_probe_results from public,anon,authenticated;
grant select on foundation.defence_health_probe_results to shine_defence_runtime,service_role;
grant select,insert on foundation.defence_health_probe_results to service_role;

create index defence_health_probe_results_target_window_idx
  on foundation.defence_health_probe_results(target_id,response_at desc,result_sequence desc);

create trigger defence_health_probe_results_append_only
before update or delete on foundation.defence_health_probe_results
for each row execute function foundation.reject_append_only_mutation();


create table foundation.defence_health_observations (
  observation_id uuid primary key default gen_random_uuid(),
  target_id text not null references foundation.defence_estate_targets(target_id),
  health_state text not null
    check (health_state in ('healthy','degraded','unhealthy','unknown')),
  sample_count integer not null
    check (sample_count >= 0),
  failure_count integer not null
    check (failure_count >= 0 and failure_count <= sample_count),
  window_started_at timestamptz,
  window_ended_at timestamptz,
  avg_roundtrip_ms numeric(12,3)
    check (avg_roundtrip_ms is null or avg_roundtrip_ms >= 0),
  p95_roundtrip_ms numeric(12,3)
    check (p95_roundtrip_ms is null or p95_roundtrip_ms >= 0),
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (valid_until > observed_at),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_health_observations enable row level security;

create policy shine_defence_runtime_health_observations_select
on foundation.defence_health_observations
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_health_observations from public,anon,authenticated;
grant select on foundation.defence_health_observations to shine_defence_runtime,service_role;
grant select,insert on foundation.defence_health_observations to service_role;

create index defence_health_observations_current_idx
  on foundation.defence_health_observations(target_id,observed_at desc,recorded_at desc);

create trigger defence_health_observations_append_only
before update or delete on foundation.defence_health_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_health_observations
with (security_invoker=true)
as
select distinct on (target_id)
  observation_id,target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata,recorded_at
from foundation.defence_health_observations
order by target_id,observed_at desc,recorded_at desc,observation_id desc;

revoke all on foundation.current_defence_health_observations from public,anon,authenticated;
grant select on foundation.current_defence_health_observations to shine_defence_runtime,service_role;


create or replace function foundation.defence_health_contract_matches_v1(
  p_response_mode text,
  p_expected_json jsonb,
  p_expected_text text,
  p_http_status integer,
  p_timed_out boolean,
  p_error_message text,
  p_response_content text
)
returns boolean
language plpgsql
immutable
security invoker
set search_path = pg_catalog
as $$
declare
  v_body jsonb;
begin
  if p_http_status is null
     or p_http_status < 200
     or p_http_status > 299
     or coalesce(p_timed_out,false)
     or p_error_message is not null
     or p_response_content is null then
    return false;
  end if;

  if p_response_mode='text_exact' then
    return btrim(p_response_content, E' \t\r\n')=p_expected_text;
  end if;

  if p_response_mode='json_contains' then
    begin
      v_body := p_response_content::jsonb;
    exception
      when others then
        return false;
    end;

    return jsonb_typeof(v_body)='object'
      and v_body @> p_expected_json;
  end if;

  return false;
end;
$$;

revoke all on function foundation.defence_health_contract_matches_v1(text,jsonb,text,integer,boolean,text,text)
  from public,anon,authenticated;
grant execute on function foundation.defence_health_contract_matches_v1(text,jsonb,text,integer,boolean,text,text)
  to shine_defence_runtime,service_role;


create or replace function foundation.record_defence_health_probe_result_v1(
  p_probe_request_id uuid,
  p_http_status integer,
  p_timed_out boolean,
  p_error_message text,
  p_contract_ok boolean,
  p_response_at timestamptz,
  p_roundtrip_ms numeric,
  p_response_sha256 text,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_sequence bigint;
  v_request foundation.defence_health_probe_requests%rowtype;
begin
  select *
    into v_request
  from foundation.defence_health_probe_requests
  where probe_request_id=p_probe_request_id;

  if v_request.probe_request_id is null then
    raise exception 'unknown Defence health probe request';
  end if;

  insert into foundation.defence_health_probe_results(
    probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
    response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  ) values (
    p_probe_request_id,v_request.target_id,p_http_status,coalesce(p_timed_out,false),
    p_error_message,coalesce(p_contract_ok,false),p_response_at,p_roundtrip_ms,
    p_response_sha256,p_evidence_ref,coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (probe_request_id) do update
    set probe_request_id=excluded.probe_request_id
  returning result_sequence into v_sequence;

  return v_sequence;
end;
$$;

revoke all on function foundation.record_defence_health_probe_result_v1(
  uuid,integer,boolean,text,boolean,timestamptz,numeric,text,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.record_defence_health_probe_result_v1(
  uuid,integer,boolean,text,boolean,timestamptz,numeric,text,text,jsonb
) to service_role;


create or replace function foundation.refresh_defence_health_from_probes_v1(
  p_target_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_sample_count integer := 0;
  v_failure_count integer := 0;
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_avg numeric;
  v_p95 numeric;
  v_latest_sequence bigint;
  v_state text;
  v_evidence_ref text;
  v_id uuid;
begin
  select *
    into v_target
  from foundation.current_defence_health_probe_target
  where target_id=p_target_id;

  if v_target.target_id is null or not v_target.enabled then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode',case when v_target.target_id is null then 'missing-health-target' else 'health-target-disabled' end,
      'targetId',p_target_id
    );
  end if;

  select
    count(*)::integer,
    count(*) filter (where not contract_ok)::integer,
    min(response_at),
    max(response_at),
    round(avg(roundtrip_ms),3),
    round((percentile_cont(0.95) within group (order by roundtrip_ms))::numeric,3),
    max(result_sequence)
  into
    v_sample_count,v_failure_count,v_window_start,v_window_end,
    v_avg,v_p95,v_latest_sequence
  from foundation.defence_health_probe_results
  where target_id=p_target_id
    and response_at > p_as_of - make_interval(secs=>v_target.evaluation_window_seconds)
    and response_at <= p_as_of;

  if coalesce(v_sample_count,0)=0 then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','no-health-probe-results',
      'targetId',p_target_id
    );
  end if;

  v_state := case
    when v_sample_count < v_target.min_samples then 'unknown'
    when v_failure_count >= v_target.unhealthy_failure_count then 'unhealthy'
    when v_failure_count >= v_target.degraded_failure_count then 'degraded'
    else 'healthy'
  end;

  v_evidence_ref :=
    'defence-health-window:' || p_target_id || ':' || v_latest_sequence::text;

  insert into foundation.defence_health_observations(
    target_id,health_state,sample_count,failure_count,window_started_at,window_ended_at,
    avg_roundtrip_ms,p95_roundtrip_ms,observed_at,valid_until,evidence_ref,metadata
  ) values (
    p_target_id,v_state,v_sample_count,v_failure_count,v_window_start,v_window_end,
    v_avg,v_p95,p_as_of,p_as_of+make_interval(secs=>v_target.max_evidence_age_seconds),
    v_evidence_ref,
    jsonb_build_object(
      'collector','shine-defence/estate-health-adapters-v1',
      'targetVersion',v_target.target_version,
      'latestProbeResultSequence',v_latest_sequence,
      'syntheticProbe',true
    )
  )
  on conflict (evidence_ref) do nothing
  returning observation_id into v_id;

  return jsonb_build_object(
    'status',case when v_id is null then 'already-recorded' else 'recorded' end,
    'targetId',p_target_id,
    'healthState',v_state,
    'sampleCount',v_sample_count,
    'failureCount',v_failure_count,
    'evidenceRef',v_evidence_ref
  );
end;
$$;

revoke all on function foundation.refresh_defence_health_from_probes_v1(text,timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.refresh_defence_health_from_probes_v1(text,timestamptz)
  to service_role;


-- Replace estate summary so provider freshness and health freshness remain
-- independent. Dedicated health observations override provider-health hints
-- only while they are fresh.
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
  v_fresh_health integer := 0;
  v_missing_health integer := 0;
  v_stale_health integer := 0;
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
    count(*) filter (where health_probe_enabled and health_observation_id is not null and health_valid_until>now()),
    count(*) filter (
      where health_probe_enabled
        and health_observation_id is null
        and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    ),
    count(*) filter (
      where health_probe_enabled
        and health_observation_id is not null
        and health_valid_until<=now()
        and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    )
  into
    v_fresh,v_missing,v_stale,v_runtime_bad,v_runtime_unexpected,
    v_health_bad,v_health_unknown,v_health_coverage,v_fresh_health,
    v_missing_health,v_stale_health
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
      'providerObservedAt',provider_observed_at,
      'providerValidUntil',provider_valid_until,
      'healthObservedAt',health_observed_at,
      'healthValidUntil',health_valid_until,
      'reason',case
        when provider_observation_id is null then 'missing-observation'
        when provider_valid_until<=now() then 'stale-observation'
        when runtime_state in ('failed','inactive') then 'runtime-failure'
        when runtime_state<>all(allowed_runtime_states) then 'unexpected-runtime-state'
        when effective_health_state='unhealthy' then 'health-unhealthy'
        when effective_health_state='degraded' then 'health-degraded'
        when health_probe_enabled
          and health_observation_id is null
          and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
          then 'health-observation-missing'
        when health_probe_enabled
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
    or effective_health_state in ('degraded','unhealthy')
    or (
      health_probe_enabled
      and health_observation_id is null
      and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    )
    or (
      health_probe_enabled
      and health_observation_id is not null
      and health_valid_until<=now()
      and now() > health_probe_effective_at + make_interval(secs=>startup_grace_seconds)
    );

  v_state := case
    when v_runtime_bad>0 or v_health_bad>0 then 'fail'
    when v_missing>0 or v_stale>0 or v_runtime_unexpected>0
      or v_missing_health>0 or v_stale_health>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceEstateSummary','shine-defence/estate-summary-v1',
    'schemaVersion','1.1.0',
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
    'freshHealthTargets',v_fresh_health,
    'missingHealthTargets',v_missing_health,
    'staleHealthTargets',v_stale_health,
    'problemTargets',v_problem_targets,
    'evaluatedAt',now()
  );
end;
$$;


-- Extend estate Sentinel incident provenance to reference health observations
-- independently from provider observations.
alter table foundation.defence_estate_incident_events
  add column if not exists health_observation_id uuid
    references foundation.defence_health_observations(observation_id);

create index if not exists defence_estate_incident_events_health_observation_idx
  on foundation.defence_estate_incident_events(health_observation_id);

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
    'health-degraded',
    'health-unhealthy',
    'health-observation-missing',
    'health-observation-stale'
  ));

create or replace view foundation.current_defence_estate_incident_state
with (security_invoker=true)
as
select distinct on (incident_key)
  event_id,incident_key,target_id,event_type,state,reason_code,
  observation_id,occurred_at,evidence_ref,recorded_at,health_observation_id
from foundation.defence_estate_incident_events
order by incident_key,occurred_at desc,recorded_at desc,event_id desc;

revoke all on foundation.current_defence_estate_incident_state from public,anon,authenticated;
grant select on foundation.current_defence_estate_incident_state to shine_defence_runtime,service_role;

create or replace view foundation.current_defence_estate_incidents
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
    elsif v_health_target.target_id is not null
      and p_observed_at > v_health_target.effective_at + make_interval(secs=>v_health_target.startup_grace_seconds)
      and v_health.observation_id is null then
      v_state := 'warning';
      v_reason := 'health-observation-missing';
    elsif v_health_target.target_id is not null
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
    'schemaVersion','1.1.0',
    'observedAt',p_observed_at,
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active,
    'activeFailCount',v_fail,
    'activeWarningCount',v_warning,
    'estate',foundation.get_defence_estate_summary_v1()
  );
end;
$$;


-- Seed only always-on services with an existing Railway-configured health path.
-- D&D is deliberately excluded because its service is configured to sleep and
-- continuous probes would wake it.
insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note
) values
  (
    '1.0.0','railway:daash',
    'https://shine-daash-x-production.up.railway.app/api/status',
    'json_contains','{"status":"ok"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-daash:v1',
    'Uses the existing Railway-configured /api/status endpoint.'
  ),
  (
    '1.0.0','railway:dive',
    'https://shine-dive-production.up.railway.app/healthz',
    'text_exact',null,'ok',
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-dive:v1',
    'Uses the existing Railway-configured /healthz endpoint.'
  ),
  (
    '1.0.0','railway:fiona',
    'https://fiona-finance-production.up.railway.app/health',
    'json_contains','{"status":"ok","service":"fiona-finance"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-fiona:v1',
    'Uses the existing Railway-configured /health endpoint.'
  ),
  (
    '1.0.0','railway:my-money',
    'https://shine-my-money-production.up.railway.app/api/health',
    'json_contains','{"ok":true,"status":"healthy","service":"shine-my-money"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-my-money:v1',
    'Uses the existing Railway-configured /api/health endpoint.'
  ),
  (
    '1.0.0','railway:project-l',
    'https://project-l-modular-production.up.railway.app/health',
    'json_contains','{"status":"ok"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-project-l:v1',
    'Uses the existing Railway-configured /health endpoint.'
  ),
  (
    '1.0.0','railway:recovery-companion',
    'https://web-production-2bd5b.up.railway.app/health',
    'json_contains','{"status":"healthy","service":"Recovery Companion API"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-recovery-companion:v1',
    'Uses the existing Railway-configured /health endpoint on the verified production domain.'
  ),
  (
    '1.0.0','railway:shine-ai',
    'https://shine-ai-production-b6fd.up.railway.app/health',
    'json_contains','{"status":"ok","service":"shine-ai","environment":"production"}'::jsonb,null,
    10000,1200,600,3,1,2,1200,true,now(),
    'defence:health-target:railway-shine-ai:v1',
    'Uses the existing Railway-configured /health endpoint.'
  );
