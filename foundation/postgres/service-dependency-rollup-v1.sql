-- Foundation Layer 24: service dependency graph and health roll-up.
-- Models dependency criticality, safe failure modes, blast radius and provider-specific state.

create table foundation.service_state_sources (
  source_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  source_version text not null,
  source_kind text not null
    check (source_kind in ('standard-health','defence-posture')),
  source_config jsonb not null default '{}'::jsonb,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  unique(service_id,environment,source_version),
  check (jsonb_typeof(source_config)='object')
);

alter table foundation.service_state_sources enable row level security;

create policy foundation_runtime_service_state_sources_select
on foundation.service_state_sources
for select
to foundation_runtime
using (true);

revoke all on foundation.service_state_sources from public,anon,authenticated;
grant select on foundation.service_state_sources to foundation_runtime;
grant select,insert on foundation.service_state_sources to service_role;

create index service_state_sources_current_idx
  on foundation.service_state_sources(service_id,environment,effective_at desc,recorded_at desc);

create trigger service_state_sources_append_only
before update or delete on foundation.service_state_sources
for each row execute function foundation.reject_append_only_mutation();


create table foundation.service_dependencies (
  dependency_id uuid primary key default gen_random_uuid(),
  dependent_service_id text not null references foundation.service_registry(service_id),
  dependency_service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  dependency_version text not null,
  dependency_type text not null
    check (dependency_type in ('hard','guard','soft','optional')),
  impact_scope text not null
    check (impact_scope ~ '^[a-z0-9][a-z0-9._:-]*$'),
  failure_mode text not null
    check (failure_mode in ('block','fail-closed','degrade','continue')),
  description text not null,
  active boolean not null default true,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  unique(dependent_service_id,dependency_service_id,environment,dependency_version),
  check (dependent_service_id <> dependency_service_id),
  check (
    (dependency_type='hard' and failure_mode='block')
    or (dependency_type='guard' and failure_mode='fail-closed')
    or (dependency_type='soft' and failure_mode='degrade')
    or (dependency_type='optional' and failure_mode='continue')
  )
);

alter table foundation.service_dependencies enable row level security;

create policy foundation_runtime_service_dependencies_select
on foundation.service_dependencies
for select
to foundation_runtime
using (true);

revoke all on foundation.service_dependencies from public,anon,authenticated;
grant select on foundation.service_dependencies to foundation_runtime;
grant select,insert on foundation.service_dependencies to service_role;

create index service_dependencies_dependent_idx
  on foundation.service_dependencies(dependent_service_id,environment,effective_at desc);

create index service_dependencies_dependency_idx
  on foundation.service_dependencies(dependency_service_id,environment,effective_at desc);

create trigger service_dependencies_append_only
before update or delete on foundation.service_dependencies
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_service_state_source
with (security_invoker=true)
as
select distinct on (service_id,environment)
  source_id,
  service_id,
  environment,
  source_version,
  source_kind,
  source_config,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.service_state_sources
order by service_id,environment,effective_at desc,recorded_at desc,source_id desc;

revoke all on foundation.current_service_state_source from public,anon,authenticated;
grant select on foundation.current_service_state_source to foundation_runtime;


create view foundation.current_service_dependencies
with (security_invoker=true)
as
select distinct on (dependent_service_id,dependency_service_id,environment)
  dependency_id,
  dependent_service_id,
  dependency_service_id,
  environment,
  dependency_version,
  dependency_type,
  impact_scope,
  failure_mode,
  description,
  active,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.service_dependencies
order by
  dependent_service_id,
  dependency_service_id,
  environment,
  effective_at desc,
  recorded_at desc,
  dependency_id desc;

revoke all on foundation.current_service_dependencies from public,anon,authenticated;
grant select on foundation.current_service_dependencies to foundation_runtime;


create or replace function foundation.get_service_native_state_v1(
  p_service_id text,
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_service foundation.service_registry%rowtype;
  v_source foundation.service_state_sources%rowtype;
  v_posture foundation.defence_posture_observations%rowtype;
  v_standard jsonb;
  v_state text;
  v_reason text[] := array[]::text[];
begin
  select * into v_service
  from foundation.service_registry
  where service_id=p_service_id;

  if v_service.service_id is null then
    return jsonb_build_object(
      'nativeStateResponse','shine-foundation/service-native-state-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'operationalState','unknown',
      'reasonCodes',jsonb_build_array('unknown-service')
    );
  end if;

  select * into v_source
  from foundation.current_service_state_source
  where service_id=p_service_id
    and environment=p_environment;

  if v_source.source_id is null then
    return jsonb_build_object(
      'nativeStateResponse','shine-foundation/service-native-state-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'displayName',v_service.display_name,
      'environment',p_environment,
      'sourceKind',null,
      'operationalState','unknown',
      'reasonCodes',jsonb_build_array('missing-state-source')
    );
  end if;

  if v_source.source_kind='standard-health' then
    v_standard := foundation.get_service_state_v1(p_service_id,p_environment);

    return jsonb_build_object(
      'nativeStateResponse','shine-foundation/service-native-state-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'displayName',v_service.display_name,
      'environment',p_environment,
      'sourceKind',v_source.source_kind,
      'operationalState',coalesce(v_standard->>'operationalState','unknown'),
      'reasonCodes','[]'::jsonb,
      'sourceEvidenceRef',v_source.evidence_ref,
      'sourceState',v_standard
    );
  end if;

  if v_source.source_kind='defence-posture' then
    select * into v_posture
    from foundation.current_defence_posture
    where environment=p_environment
    limit 1;

    if v_posture.observation_id is null then
      v_state := 'unknown';
      v_reason := array_append(v_reason,'missing-defence-posture');
    elsif v_posture.valid_until < p_as_of then
      v_state := 'unknown';
      v_reason := array_append(v_reason,'stale-defence-posture');
    else
      v_state := case lower(v_posture.overall_state)
        when 'pass' then 'operational'
        when 'warn' then 'degraded'
        when 'warning' then 'degraded'
        when 'fail' then 'unhealthy'
        when 'failed' then 'unhealthy'
        else 'unknown'
      end;

      if v_state='unknown' then
        v_reason := array_append(v_reason,'unrecognised-defence-posture');
      end if;
    end if;

    return jsonb_build_object(
      'nativeStateResponse','shine-foundation/service-native-state-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'displayName',v_service.display_name,
      'environment',p_environment,
      'sourceKind',v_source.source_kind,
      'operationalState',v_state,
      'reasonCodes',to_jsonb(v_reason),
      'sourceEvidenceRef',case when v_posture.observation_id is null then v_source.evidence_ref else v_posture.evidence_ref end,
      'sourceState',case
        when v_posture.observation_id is null then null
        else jsonb_build_object(
          'postureVersion',v_posture.posture_version,
          'overallState',v_posture.overall_state,
          'observedAt',v_posture.observed_at,
          'validUntil',v_posture.valid_until,
          'checks',v_posture.checks
        )
      end
    );
  end if;

  return jsonb_build_object(
    'nativeStateResponse','shine-foundation/service-native-state-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',p_service_id,
    'environment',p_environment,
    'sourceKind',v_source.source_kind,
    'operationalState','unknown',
    'reasonCodes',jsonb_build_array('unsupported-state-source')
  );
end;
$$;

revoke all on function foundation.get_service_native_state_v1(text,text,timestamptz)
  from public,anon,authenticated;
grant execute on function foundation.get_service_native_state_v1(text,text,timestamptz)
  to foundation_runtime;


create or replace function foundation.get_service_dependency_rollup_v1(
  p_service_id text,
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_own jsonb;
  v_own_state text;
  v_dependencies jsonb := '[]'::jsonb;
  v_has_blocked boolean := false;
  v_has_guarded boolean := false;
  v_has_unknown boolean := false;
  v_has_degraded boolean := false;
  v_effective_state text;
  v_safe_mode text;
  v_blocked_scopes jsonb := '[]'::jsonb;
  v_guarded_scopes jsonb := '[]'::jsonb;
  v_degraded_scopes jsonb := '[]'::jsonb;
begin
  v_own := foundation.get_service_native_state_v1(p_service_id,p_environment,p_as_of);
  v_own_state := coalesce(v_own->>'operationalState','unknown');

  with evaluated as (
    select
      d.dependency_id,
      d.dependency_service_id,
      d.dependency_type,
      d.impact_scope,
      d.failure_mode,
      d.description,
      foundation.get_service_native_state_v1(
        d.dependency_service_id,
        p_environment,
        p_as_of
      ) as dependency_state
    from foundation.current_service_dependencies d
    where d.dependent_service_id=p_service_id
      and d.environment=p_environment
      and d.active=true
  ),
  classified as (
    select *,
      coalesce(dependency_state->>'operationalState','unknown') as raw_state,
      case
        when dependency_type='optional' then 'none'
        when dependency_type='hard'
          and coalesce(dependency_state->>'operationalState','unknown') in ('unhealthy','drift')
          then 'blocked'
        when dependency_type='hard'
          and coalesce(dependency_state->>'operationalState','unknown')='unknown'
          then 'unknown'
        when dependency_type='hard'
          and coalesce(dependency_state->>'operationalState','unknown')='degraded'
          then 'degraded'
        when dependency_type='guard'
          and coalesce(dependency_state->>'operationalState','unknown') in ('unhealthy','drift','unknown')
          then 'guarded'
        when dependency_type='guard'
          and coalesce(dependency_state->>'operationalState','unknown')='degraded'
          then 'degraded'
        when dependency_type='soft'
          and coalesce(dependency_state->>'operationalState','unknown') <> 'operational'
          then 'degraded'
        else 'none'
      end as impact
    from evaluated
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'dependencyServiceId',dependency_service_id,
      'dependencyType',dependency_type,
      'impactScope',impact_scope,
      'failureMode',failure_mode,
      'description',description,
      'nativeState',dependency_state,
      'impact',impact
    ) order by dependency_service_id),'[]'::jsonb),
    coalesce(bool_or(impact='blocked'),false),
    coalesce(bool_or(impact='guarded'),false),
    coalesce(bool_or(impact='unknown'),false),
    coalesce(bool_or(impact='degraded'),false),
    coalesce(jsonb_agg(to_jsonb(impact_scope)) filter (where impact='blocked'),'[]'::jsonb),
    coalesce(jsonb_agg(to_jsonb(impact_scope)) filter (where impact='guarded'),'[]'::jsonb),
    coalesce(jsonb_agg(to_jsonb(impact_scope)) filter (where impact='degraded'),'[]'::jsonb)
  into
    v_dependencies,
    v_has_blocked,
    v_has_guarded,
    v_has_unknown,
    v_has_degraded,
    v_blocked_scopes,
    v_guarded_scopes,
    v_degraded_scopes
  from classified;

  if v_own_state in ('unhealthy','drift') then
    v_effective_state := 'blocked';
    v_safe_mode := 'blocked';
  elsif v_own_state='unknown' then
    v_effective_state := 'unknown';
    v_safe_mode := 'unknown';
  elsif v_has_blocked then
    v_effective_state := 'blocked';
    v_safe_mode := 'blocked';
  elsif v_has_guarded then
    v_effective_state := 'guarded';
    v_safe_mode := 'guarded';
  elsif v_has_unknown then
    v_effective_state := 'unknown';
    v_safe_mode := 'unknown';
  elsif v_own_state='degraded' or v_has_degraded then
    v_effective_state := 'degraded';
    v_safe_mode := 'degraded';
  else
    v_effective_state := 'operational';
    v_safe_mode := 'normal';
  end if;

  return jsonb_build_object(
    'dependencyRollupResponse','shine-foundation/service-dependency-rollup-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',p_service_id,
    'environment',p_environment,
    'effectiveState',v_effective_state,
    'safeMode',v_safe_mode,
    'ownState',v_own,
    'dependencies',v_dependencies,
    'blockedScopes',v_blocked_scopes,
    'guardedScopes',v_guarded_scopes,
    'degradedScopes',v_degraded_scopes
  );
end;
$$;

revoke all on function foundation.get_service_dependency_rollup_v1(text,text,timestamptz)
  from public,anon,authenticated;
grant execute on function foundation.get_service_dependency_rollup_v1(text,text,timestamptz)
  to foundation_runtime;


create or replace function foundation.get_service_blast_radius_v1(
  p_dependency_service_id text,
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
  with recursive impact_graph as (
    select
      d.dependent_service_id as affected_service_id,
      d.dependency_service_id,
      1 as depth,
      array[p_dependency_service_id,d.dependent_service_id]::text[] as path,
      array[d.dependency_type]::text[] as dependency_types,
      d.impact_scope,
      case d.dependency_type
        when 'hard' then 'blocked'
        when 'guard' then 'guarded'
        when 'soft' then 'degraded'
        else 'none'
      end as potential_impact
    from foundation.current_service_dependencies d
    where d.dependency_service_id=p_dependency_service_id
      and d.environment=p_environment
      and d.active=true

    union all

    select
      d.dependent_service_id,
      d.dependency_service_id,
      g.depth+1,
      g.path || d.dependent_service_id,
      g.dependency_types || d.dependency_type,
      d.impact_scope,
      case
        when d.dependency_type='optional' then 'none'
        when g.potential_impact='blocked' and d.dependency_type='hard' then 'blocked'
        when g.potential_impact in ('blocked','guarded') and d.dependency_type='guard' then 'guarded'
        when g.potential_impact in ('blocked','guarded','degraded') and d.dependency_type='soft' then 'degraded'
        when g.potential_impact='guarded' and d.dependency_type='hard' then 'guarded'
        when g.potential_impact='degraded' and d.dependency_type in ('hard','guard') then 'degraded'
        else 'none'
      end
    from impact_graph g
    join foundation.current_service_dependencies d
      on d.dependency_service_id=g.affected_service_id
     and d.environment=p_environment
     and d.active=true
    where g.depth < 16
      and not d.dependent_service_id = any(g.path)
      and g.potential_impact <> 'none'
  ),
  ranked as (
    select *,
      case potential_impact
        when 'blocked' then 4
        when 'guarded' then 3
        when 'degraded' then 2
        else 0
      end as impact_rank
    from impact_graph
  ),
  chosen as (
    select distinct on (affected_service_id)
      affected_service_id,
      depth,
      path,
      dependency_types,
      impact_scope,
      potential_impact,
      impact_rank
    from ranked
    order by affected_service_id,impact_rank desc,depth asc
  )
  select jsonb_build_object(
    'blastRadiusResponse','shine-foundation/service-blast-radius-response-v1',
    'schemaVersion','1.0.0',
    'dependencyServiceId',p_dependency_service_id,
    'environment',p_environment,
    'affectedCount',(select count(*) from chosen where potential_impact <> 'none'),
    'affected',coalesce((
      select jsonb_agg(jsonb_build_object(
        'serviceId',affected_service_id,
        'depth',depth,
        'path',to_jsonb(path),
        'dependencyTypes',to_jsonb(dependency_types),
        'impactScope',impact_scope,
        'potentialImpact',potential_impact
      ) order by depth,affected_service_id)
      from chosen
      where potential_impact <> 'none'
    ),'[]'::jsonb)
  );
$$;

revoke all on function foundation.get_service_blast_radius_v1(text,text)
  from public,anon,authenticated;
grant execute on function foundation.get_service_blast_radius_v1(text,text)
  to foundation_runtime;


create or replace function foundation.get_dependency_graph_health_v1(
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
  with recursive walk as (
    select
      d.dependent_service_id as start_service_id,
      d.dependency_service_id as current_service_id,
      array[d.dependent_service_id,d.dependency_service_id]::text[] as path,
      false as cycle
    from foundation.current_service_dependencies d
    where d.environment=p_environment
      and d.active=true

    union all

    select
      w.start_service_id,
      d.dependency_service_id,
      w.path || d.dependency_service_id,
      d.dependency_service_id=any(w.path)
    from walk w
    join foundation.current_service_dependencies d
      on d.dependent_service_id=w.current_service_id
     and d.environment=p_environment
     and d.active=true
    where array_length(w.path,1) < 32
      and not w.cycle
  ),
  cycles as (
    select distinct path
    from walk
    where cycle=true
  )
  select jsonb_build_object(
    'dependencyGraphHealthResponse','shine-foundation/dependency-graph-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'state',case when exists(select 1 from cycles) then 'fail' else 'pass' end,
    'activeEdges',(
      select count(*) from foundation.current_service_dependencies
      where environment=p_environment and active=true
    ),
    'cycleCount',(select count(*) from cycles),
    'cycles',coalesce((select jsonb_agg(to_jsonb(path)) from cycles),'[]'::jsonb)
  );
$$;

revoke all on function foundation.get_dependency_graph_health_v1(text)
  from public,anon,authenticated;
grant execute on function foundation.get_dependency_graph_health_v1(text)
  to foundation_runtime;


create or replace function foundation.get_foundation_dependency_rollup_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_services jsonb;
  v_overall text;
  v_graph jsonb;
begin
  v_graph := foundation.get_dependency_graph_health_v1(p_environment);

  select coalesce(jsonb_agg(
    foundation.get_service_dependency_rollup_v1(s.service_id,p_environment,p_as_of)
    order by s.service_id
  ),'[]'::jsonb)
  into v_services
  from foundation.service_registry s
  where s.required_for_core=true
    and s.lifecycle='active';

  if v_graph->>'state' <> 'pass' then
    v_overall := 'unknown';
  elsif jsonb_array_length(v_services)=0 then
    v_overall := 'unknown';
  elsif exists (
    select 1 from jsonb_array_elements(v_services) x
    where x->>'effectiveState'='blocked'
  ) then
    v_overall := 'blocked';
  elsif exists (
    select 1 from jsonb_array_elements(v_services) x
    where x->>'effectiveState'='guarded'
  ) then
    v_overall := 'guarded';
  elsif exists (
    select 1 from jsonb_array_elements(v_services) x
    where x->>'effectiveState'='unknown'
  ) then
    v_overall := 'unknown';
  elsif exists (
    select 1 from jsonb_array_elements(v_services) x
    where x->>'effectiveState'='degraded'
  ) then
    v_overall := 'degraded';
  else
    v_overall := 'operational';
  end if;

  return jsonb_build_object(
    'foundationDependencyRollupResponse','shine-foundation/foundation-dependency-rollup-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'effectiveState',v_overall,
    'graphHealth',v_graph,
    'coreServices',v_services
  );
end;
$$;

revoke all on function foundation.get_foundation_dependency_rollup_v1(text,timestamptz)
  from public,anon,authenticated;
grant execute on function foundation.get_foundation_dependency_rollup_v1(text,timestamptz)
  to foundation_runtime;


insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,
  required_for_core,lifecycle,metadata
)
values (
  'foundation.defence',
  'Shine Defence',
  'universe',
  'internal-service',
  'shine-defence/operational-posture-v1',
  false,
  'active',
  jsonb_build_object(
    'stateProvider','foundation.current_defence_posture',
    'relationship','security-guard'
  )
)
on conflict (service_id) do update
set display_name=excluded.display_name,
    owner_component=excluded.owner_component,
    service_kind=excluded.service_kind,
    contract_ref=excluded.contract_ref,
    required_for_core=excluded.required_for_core,
    lifecycle=excluded.lifecycle,
    metadata=excluded.metadata,
    updated_at=now();


insert into foundation.service_state_sources(
  service_id,environment,source_version,source_kind,source_config,
  effective_at,evidence_ref,evidence_note
)
select
  'foundation.gateway','production','1.0.0','standard-health','{}'::jsonb,
  now(),'foundation:state-source:gateway-production:v1',
  'Gateway state is sourced from deployment truth plus Layer 22 health evidence.'
where not exists (
  select 1 from foundation.service_state_sources
  where service_id='foundation.gateway'
    and environment='production'
    and source_version='1.0.0'
);

insert into foundation.service_state_sources(
  service_id,environment,source_version,source_kind,source_config,
  effective_at,evidence_ref,evidence_note
)
select
  'foundation.defence','production','1.0.0','defence-posture',
  jsonb_build_object('maxAgeMode','valid-until'),
  now(),'foundation:state-source:defence-production:v1',
  'Defence state is derived from the current signed/dated operational posture and its valid_until boundary.'
where not exists (
  select 1 from foundation.service_state_sources
  where service_id='foundation.defence'
    and environment='production'
    and source_version='1.0.0'
);

insert into foundation.service_dependencies(
  dependent_service_id,dependency_service_id,environment,dependency_version,
  dependency_type,impact_scope,failure_mode,description,active,
  effective_at,evidence_ref,evidence_note
)
select
  'foundation.gateway',
  'foundation.defence',
  'production',
  '1.0.0',
  'guard',
  'protected-operations',
  'fail-closed',
  'Foundation Gateway depends on Shine Defence for protected access decisions. Defence failure blocks guarded operations without requiring unrelated public/standalone surfaces to stop.',
  true,
  now(),
  'foundation:dependency:gateway:defence:v1',
  'Explicitly models the Foundation v1 access-decision invariant that Defence gates protected operations.'
where not exists (
  select 1 from foundation.service_dependencies
  where dependent_service_id='foundation.gateway'
    and dependency_service_id='foundation.defence'
    and environment='production'
    and dependency_version='1.0.0'
);
