-- Shine Defence credential-free Railway runtime provenance v1.
-- Successful monitored health responses may carry bounded non-secret Railway
-- release identity in response headers. Valid provenance refreshes the serving
-- deployment observation without requiring Railway management credentials.

alter table foundation.defence_estate_observations
  drop constraint if exists defence_estate_observations_evidence_kind_check;

alter table foundation.defence_estate_observations
  add constraint defence_estate_observations_evidence_kind_check
  check (evidence_kind in (
    'supabase-management-api',
    'railway-api',
    'runtime-self-report',
    'manual-verified'
  ));


create table foundation.defence_runtime_provenance_observations (
  observation_id uuid primary key default gen_random_uuid(),
  target_id text not null references foundation.defence_estate_targets(target_id),
  provider text not null check (provider='railway'),
  repository text not null
    check (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  commit_sha text not null
    check (commit_sha ~ '^[a-fA-F0-9]{40}$'),
  branch text not null
    check (length(branch) between 1 and 200 and branch !~ '[[:cntrl:]]'),
  deployment_id text not null
    check (deployment_id ~ '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[1-5][a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$'),
  service_name text not null
    check (length(service_name) between 1 and 200 and service_name !~ '[[:cntrl:]]'),
  environment_name text not null
    check (length(environment_name) between 1 and 200 and environment_name !~ '[[:cntrl:]]'),
  health_probe_result_sequence bigint not null
    references foundation.defence_health_probe_results(result_sequence),
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (valid_until>observed_at),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_runtime_provenance_observations enable row level security;

create policy shine_defence_runtime_runtime_provenance_select
on foundation.defence_runtime_provenance_observations
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_runtime_provenance_observations
  from public,anon,authenticated;
grant select on foundation.defence_runtime_provenance_observations
  to shine_defence_runtime,service_role;
grant insert on foundation.defence_runtime_provenance_observations
  to service_role;

create index defence_runtime_provenance_target_time_idx
  on foundation.defence_runtime_provenance_observations(
    target_id,observed_at desc,recorded_at desc
  );

create index defence_runtime_provenance_probe_result_idx
  on foundation.defence_runtime_provenance_observations(
    health_probe_result_sequence
  );

create trigger defence_runtime_provenance_append_only
before update or delete on foundation.defence_runtime_provenance_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_runtime_provenance
with (security_invoker=true)
as
select distinct on (target_id)
  observation_id,target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata,recorded_at
from foundation.defence_runtime_provenance_observations
order by target_id,observed_at desc,recorded_at desc,observation_id desc;

revoke all on foundation.current_defence_runtime_provenance
  from public,anon,authenticated;
grant select on foundation.current_defence_runtime_provenance
  to shine_defence_runtime,service_role;


update foundation.defence_estate_targets
set metadata = metadata || jsonb_build_object(
  'runtimeProvenanceContract','shine-defence/runtime-provenance-v1',
  'runtimeProvenanceRequired',true,
  'runtimeProvenanceEffectiveAt',now(),
  'sourceRepository',case target_id
    when 'railway:daash' then 'doug-dotcom/Shine-DaAsh'
    when 'railway:dive' then 'doug-dotcom/shine-dive-'
    when 'railway:dnd' then 'doug-dotcom/shine-D-D'
    when 'railway:fiona' then 'doug-dotcom/Fiona-Finance'
    when 'railway:fish' then 'doug-dotcom/shine-fish'
    when 'railway:my-money' then 'doug-dotcom/shine-my-money-'
    when 'railway:project-l' then 'doug-dotcom/Project-L-Modular'
    when 'railway:punt49' then 'doug-dotcom/Punt-49'
    when 'railway:recovery-companion' then 'doug-dotcom/Project-RC'
    when 'railway:rivers' then 'doug-dotcom/shine-music'
    when 'railway:shine-ai' then 'doug-dotcom/Shine-Ai'
    when 'railway:ski' then 'doug-dotcom/Shine-Ski'
    when 'railway:translate' then 'doug-dotcom/shine-translate'
    when 'railway:travel' then 'doug-dotcom/shine-travel'
  end,
  'sourceBranch',case target_id
    when 'railway:dive' then 'codex/dive-foundation'
    when 'railway:dnd' then 'build/layer-001-foundation'
    when 'railway:fish' then 'build/first-app'
    else 'main'
  end
),
updated_at=now()
where provider='railway'
  and lifecycle='active';


create or replace function foundation.record_defence_estate_observation_v1(
  p_target_id text,
  p_runtime_state text,
  p_health_state text,
  p_deployment_ref text,
  p_version_ref text,
  p_artifact_ref text,
  p_observed_at timestamptz,
  p_valid_until timestamptz,
  p_evidence_kind text,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_id uuid;
  v_blocked_keys text[] := array[
    'secret','token','password','credential','authorization','cookie','api_key','apikey'
  ];
begin
  if not exists (
    select 1
    from foundation.defence_estate_targets
    where target_id=p_target_id and lifecycle='active'
  ) then
    raise exception 'unknown-or-inactive-estate-target' using errcode='22023';
  end if;

  if p_runtime_state not in ('active','sleeping','transitioning','inactive','failed','unknown')
     or p_health_state not in ('healthy','degraded','unhealthy','unknown')
     or p_evidence_kind not in (
       'supabase-management-api','railway-api','runtime-self-report','manual-verified'
     )
     or p_valid_until<=p_observed_at
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-estate-observation' using errcode='22023';
  end if;

  if exists (
    select 1
    from unnest(v_blocked_keys) k
    where p_metadata ? k
  ) then
    raise exception 'sensitive-estate-observation-metadata-key' using errcode='22023';
  end if;

  insert into foundation.defence_estate_observations(
    target_id,runtime_state,health_state,deployment_ref,version_ref,artifact_ref,
    observed_at,valid_until,evidence_kind,evidence_ref,metadata
  ) values (
    p_target_id,p_runtime_state,p_health_state,p_deployment_ref,p_version_ref,p_artifact_ref,
    p_observed_at,p_valid_until,p_evidence_kind,p_evidence_ref,p_metadata
  )
  returning observation_id into v_id;

  return v_id;
end;
$$;


create or replace function foundation.record_defence_runtime_provenance_v1(
  p_target_id text,
  p_headers jsonb,
  p_health_probe_result_sequence bigint
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_probe foundation.defence_health_probe_results%rowtype;
  v_health_target foundation.defence_health_probe_targets%rowtype;
  v_provider text;
  v_repository text;
  v_commit text;
  v_branch text;
  v_deployment text;
  v_service text;
  v_environment text;
  v_expected_repository text;
  v_expected_branch text;
  v_valid_until timestamptz;
  v_evidence_ref text;
  v_provenance_id uuid;
  v_estate_id uuid;
begin
  if p_headers is null or jsonb_typeof(p_headers)<>'object' then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','runtime-provenance-headers-missing',
      'targetId',p_target_id
    );
  end if;

  select * into v_target
  from foundation.defence_estate_targets
  where target_id=p_target_id
    and lifecycle='active';

  if v_target.target_id is null or v_target.provider<>'railway' then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','runtime-provenance-target-not-railway',
      'targetId',p_target_id
    );
  end if;

  select * into v_probe
  from foundation.defence_health_probe_results
  where result_sequence=p_health_probe_result_sequence
    and target_id=p_target_id;

  if v_probe.result_sequence is null or not v_probe.contract_ok then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','health-contract-not-passed',
      'targetId',p_target_id
    );
  end if;

  select * into v_health_target
  from foundation.current_defence_health_probe_target
  where target_id=p_target_id
    and enabled;

  if v_health_target.target_id is null then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','health-target-not-enabled',
      'targetId',p_target_id
    );
  end if;

  v_provider := p_headers->>'x-shine-runtime-provider';
  v_repository := p_headers->>'x-shine-runtime-repository';
  v_commit := lower(coalesce(p_headers->>'x-shine-runtime-commit',''));
  v_branch := p_headers->>'x-shine-runtime-branch';
  v_deployment := p_headers->>'x-shine-runtime-deployment';
  v_service := p_headers->>'x-shine-runtime-service';
  v_environment := p_headers->>'x-shine-runtime-environment';
  v_expected_repository := v_target.metadata->>'sourceRepository';
  v_expected_branch := v_target.metadata->>'sourceBranch';

  if v_provider is null
     and v_repository is null
     and v_commit=''
     and v_deployment is null then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','runtime-provenance-headers-missing',
      'targetId',p_target_id
    );
  end if;

  if v_provider<>'railway'
     or v_repository is null
     or v_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
     or v_commit !~ '^[a-f0-9]{40}$'
     or v_branch is null
     or length(v_branch) not between 1 and 200
     or v_branch ~ '[[:cntrl:]]'
     or v_deployment is null
     or v_deployment !~ '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[1-5][a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$'
     or v_service is null
     or length(v_service) not between 1 and 200
     or v_service ~ '[[:cntrl:]]'
     or v_environment is null
     or length(v_environment) not between 1 and 200
     or v_environment ~ '[[:cntrl:]]' then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','runtime-provenance-invalid',
      'targetId',p_target_id
    );
  end if;

  if v_expected_repository is null
     or lower(v_repository)<>lower(v_expected_repository) then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','runtime-provenance-repository-mismatch',
      'targetId',p_target_id
    );
  end if;

  if v_expected_branch is null
     or v_branch<>v_expected_branch then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','runtime-provenance-branch-mismatch',
      'targetId',p_target_id
    );
  end if;

  v_valid_until := case
    when v_health_target.probe_mode='on_demand'
      then v_probe.response_at + interval '48 hours'
    else v_probe.response_at + interval '15 minutes'
  end;

  v_evidence_ref :=
    'health-runtime-provenance:' || p_target_id || ':' ||
    v_deployment || ':' || v_commit || ':' || v_probe.result_sequence::text;

  insert into foundation.defence_runtime_provenance_observations(
    target_id,provider,repository,commit_sha,branch,deployment_id,
    service_name,environment_name,health_probe_result_sequence,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    p_target_id,'railway',v_repository,v_commit,v_branch,v_deployment,
    v_service,v_environment,v_probe.result_sequence,
    v_probe.response_at,v_valid_until,v_evidence_ref,
    jsonb_build_object(
      'contract','shine-defence/runtime-provenance-v1',
      'transport','health-response-headers',
      'healthContractPassed',true
    )
  )
  on conflict (evidence_ref) do nothing
  returning observation_id into v_provenance_id;

  if v_provenance_id is null then
    return jsonb_build_object(
      'status','already-recorded',
      'targetId',p_target_id,
      'deploymentId',v_deployment,
      'commitSha',v_commit
    );
  end if;

  v_estate_id := foundation.record_defence_estate_observation_v1(
    p_target_id,
    'active',
    'unknown',
    v_deployment,
    v_branch,
    v_commit,
    v_probe.response_at,
    v_valid_until,
    'runtime-self-report',
    v_evidence_ref,
    jsonb_build_object(
      'collector','shine-defence/runtime-provenance-v1',
      'repository',v_repository,
      'serviceName',v_service,
      'environmentName',v_environment,
      'healthProbeResultSequence',v_probe.result_sequence
    )
  );

  return jsonb_build_object(
    'status','recorded',
    'targetId',p_target_id,
    'repository',v_repository,
    'commitSha',v_commit,
    'branch',v_branch,
    'deploymentId',v_deployment,
    'validUntil',v_valid_until,
    'provenanceObservationId',v_provenance_id,
    'estateObservationId',v_estate_id
  );
end;
$$;

revoke all on function foundation.record_defence_runtime_provenance_v1(
  text,jsonb,bigint
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_runtime_provenance_v1(
  text,jsonb,bigint
) to service_role;


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
    'health-observation-stale',
    'runtime-provenance-coverage-missing',
    'runtime-provenance-missing',
    'runtime-provenance-stale'
  ));


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
  v_provenance_coverage integer := 0;
  v_continuous_provenance integer := 0;
  v_on_demand_provenance integer := 0;
  v_fresh_provenance integer := 0;
  v_missing_provenance integer := 0;
  v_stale_provenance integer := 0;
  v_uncovered_provenance integer := 0;
  v_state text;
  v_problem_targets jsonb := '[]'::jsonb;
begin
  select count(*) into v_targets
  from foundation.defence_estate_targets
  where lifecycle='active' and required_for_estate;

  select count(distinct a.app_key) into v_apps
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
      rp.observation_id as provenance_observation_id,
      rp.observed_at as provenance_observed_at,
      rp.valid_until as provenance_valid_until,
      case
        when h.observation_id is not null and h.valid_until>now() then h.health_state
        when o.observation_id is not null and o.valid_until>now() then o.health_state
        else 'unknown'
      end as effective_health_state,
      case
        when t.metadata ? 'runtimeProvenanceEffectiveAt'
          then (t.metadata->>'runtimeProvenanceEffectiveAt')::timestamptz
        else t.updated_at
      end as provenance_effective_at
    from foundation.defence_estate_targets t
    left join foundation.current_defence_estate_observations o using(target_id)
    left join foundation.current_defence_health_probe_target hp using(target_id)
    left join foundation.current_defence_health_observations h using(target_id)
    left join foundation.current_defence_runtime_provenance rp using(target_id)
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
    count(*) filter (
      where health_probe_enabled
        and health_observation_id is not null
        and health_valid_until>now()
    ),
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
      where provider='railway' and coalesce(health_probe_enabled,false)=false
    ),
    count(*) filter (
      where provider='railway'
        and metadata->>'runtimeProvenanceRequired'='true'
        and health_probe_enabled
    ),
    count(*) filter (
      where provider='railway'
        and metadata->>'runtimeProvenanceRequired'='true'
        and health_probe_enabled
        and health_probe_mode='continuous'
    ),
    count(*) filter (
      where provider='railway'
        and metadata->>'runtimeProvenanceRequired'='true'
        and health_probe_enabled
        and health_probe_mode='on_demand'
    ),
    count(*) filter (
      where provider='railway'
        and provenance_observation_id is not null
        and provenance_valid_until>now()
    ),
    count(*) filter (
      where provider='railway'
        and metadata->>'runtimeProvenanceRequired'='true'
        and health_probe_enabled
        and health_probe_mode='continuous'
        and provenance_observation_id is null
        and now() > provenance_effective_at + interval '20 minutes'
    ),
    count(*) filter (
      where provider='railway'
        and metadata->>'runtimeProvenanceRequired'='true'
        and health_probe_enabled
        and health_probe_mode='continuous'
        and provenance_observation_id is not null
        and provenance_valid_until<=now()
        and now() > provenance_effective_at + interval '20 minutes'
    ),
    count(*) filter (
      where provider='railway'
        and metadata->>'runtimeProvenanceRequired'='true'
        and coalesce(health_probe_enabled,false)=false
    )
  into
    v_fresh,v_missing,v_stale,v_runtime_bad,v_runtime_unexpected,
    v_health_bad,v_health_unknown,v_health_coverage,v_continuous_health,
    v_on_demand_health,v_fresh_health,v_missing_health,v_stale_health,
    v_uncovered_railway,
    v_provenance_coverage,v_continuous_provenance,v_on_demand_provenance,
    v_fresh_provenance,v_missing_provenance,v_stale_provenance,
    v_uncovered_provenance
  from estate;

  with estate as (
    select
      t.*,
      o.observation_id as provider_observation_id,
      o.runtime_state,
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
      rp.observation_id as provenance_observation_id,
      rp.observed_at as provenance_observed_at,
      rp.valid_until as provenance_valid_until,
      case
        when h.observation_id is not null and h.valid_until>now() then h.health_state
        when o.observation_id is not null and o.valid_until>now() then o.health_state
        else 'unknown'
      end as effective_health_state,
      case
        when t.metadata ? 'runtimeProvenanceEffectiveAt'
          then (t.metadata->>'runtimeProvenanceEffectiveAt')::timestamptz
        else t.updated_at
      end as provenance_effective_at
    from foundation.defence_estate_targets t
    left join foundation.current_defence_estate_observations o using(target_id)
    left join foundation.current_defence_health_probe_target hp using(target_id)
    left join foundation.current_defence_health_observations h using(target_id)
    left join foundation.current_defence_runtime_provenance rp using(target_id)
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
      'runtimeProvenanceObservedAt',provenance_observed_at,
      'runtimeProvenanceValidUntil',provenance_valid_until,
      'reason',case
        when provider_observation_id is null then 'missing-observation'
        when provider_valid_until<=now() then 'stale-observation'
        when runtime_state in ('failed','inactive') then 'runtime-failure'
        when runtime_state<>all(allowed_runtime_states) then 'unexpected-runtime-state'
        when provider='railway' and coalesce(health_probe_enabled,false)=false
          then 'health-coverage-missing'
        when provider='railway'
          and metadata->>'runtimeProvenanceRequired'='true'
          and coalesce(health_probe_enabled,false)=false
          then 'runtime-provenance-coverage-missing'
        when provider='railway'
          and metadata->>'runtimeProvenanceRequired'='true'
          and health_probe_mode='continuous'
          and provenance_observation_id is null
          and now() > provenance_effective_at + interval '20 minutes'
          then 'runtime-provenance-missing'
        when provider='railway'
          and metadata->>'runtimeProvenanceRequired'='true'
          and health_probe_mode='continuous'
          and provenance_observation_id is not null
          and provenance_valid_until<=now()
          and now() > provenance_effective_at + interval '20 minutes'
          then 'runtime-provenance-stale'
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
    or (
      provider='railway'
      and metadata->>'runtimeProvenanceRequired'='true'
      and health_probe_mode='continuous'
      and provenance_observation_id is null
      and now() > provenance_effective_at + interval '20 minutes'
    )
    or (
      provider='railway'
      and metadata->>'runtimeProvenanceRequired'='true'
      and health_probe_mode='continuous'
      and provenance_observation_id is not null
      and provenance_valid_until<=now()
      and now() > provenance_effective_at + interval '20 minutes'
    )
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
      or v_missing_health>0 or v_stale_health>0 or v_uncovered_railway>0
      or v_missing_provenance>0 or v_stale_provenance>0 or v_uncovered_provenance>0
      then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceEstateSummary','shine-defence/estate-summary-v1',
    'schemaVersion','1.3.0',
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
    'runtimeProvenanceCoverageTargets',v_provenance_coverage,
    'continuousRuntimeProvenanceTargets',v_continuous_provenance,
    'onDemandRuntimeProvenanceTargets',v_on_demand_provenance,
    'freshRuntimeProvenanceTargets',v_fresh_provenance,
    'missingRuntimeProvenanceTargets',v_missing_provenance,
    'staleRuntimeProvenanceTargets',v_stale_provenance,
    'uncoveredRuntimeProvenanceTargets',v_uncovered_provenance,
    'problemTargets',v_problem_targets,
    'evaluatedAt',now()
  );
end;
$$;


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
  v_provenance foundation.defence_runtime_provenance_observations%rowtype;
  v_prior foundation.defence_estate_incident_events%rowtype;
  v_state text;
  v_reason text;
  v_event_type text;
  v_incident_key text;
  v_provenance_effective_at timestamptz;
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
    v_provenance := null;

    select o.* into v_obs
    from foundation.defence_estate_observations o
    where o.target_id=v_target.target_id
      and o.observed_at<=p_observed_at
    order by o.observed_at desc,o.recorded_at desc,o.observation_id desc
    limit 1;

    select hp.* into v_health_target
    from foundation.current_defence_health_probe_target hp
    where hp.target_id=v_target.target_id
      and hp.enabled;

    select h.* into v_health
    from foundation.defence_health_observations h
    where h.target_id=v_target.target_id
      and h.observed_at<=p_observed_at
    order by h.observed_at desc,h.recorded_at desc,h.observation_id desc
    limit 1;

    select rp.* into v_provenance
    from foundation.defence_runtime_provenance_observations rp
    where rp.target_id=v_target.target_id
      and rp.observed_at<=p_observed_at
    order by rp.observed_at desc,rp.recorded_at desc,rp.observation_id desc
    limit 1;

    v_provenance_effective_at := case
      when v_target.metadata ? 'runtimeProvenanceEffectiveAt'
        then (v_target.metadata->>'runtimeProvenanceEffectiveAt')::timestamptz
      else v_target.updated_at
    end;

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
    elsif v_target.provider='railway'
      and v_target.metadata->>'runtimeProvenanceRequired'='true'
      and (
        v_target.metadata->>'sourceRepository' is null
        or v_target.metadata->>'sourceBranch' is null
      ) then
      v_state := 'warning';
      v_reason := 'runtime-provenance-coverage-missing';
    elsif v_target.provider='railway'
      and v_target.metadata->>'runtimeProvenanceRequired'='true'
      and v_health_target.probe_mode='continuous'
      and p_observed_at > v_provenance_effective_at + interval '20 minutes'
      and v_provenance.observation_id is null then
      v_state := 'warning';
      v_reason := 'runtime-provenance-missing';
    elsif v_target.provider='railway'
      and v_target.metadata->>'runtimeProvenanceRequired'='true'
      and v_health_target.probe_mode='continuous'
      and p_observed_at > v_provenance_effective_at + interval '20 minutes'
      and v_provenance.observation_id is not null
      and v_provenance.valid_until<=p_observed_at then
      v_state := 'warning';
      v_reason := 'runtime-provenance-stale';
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
    'schemaVersion','1.3.0',
    'observedAt',p_observed_at,
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active,
    'activeFailCount',v_fail,
    'activeWarningCount',v_warning,
    'estate',foundation.get_defence_estate_summary_v1()
  );
end;
$$;
