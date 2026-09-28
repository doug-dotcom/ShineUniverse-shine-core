-- Shine Defence federated estate inventory v1.
-- Canonicalises shared Supabase/Railway backends separately from the Shine apps
-- that depend on them. Universe remains the source of app identity; this is the
-- bounded operational projection used by Defence.

create table foundation.defence_estate_targets (
  target_id text primary key
    check (target_id ~ '^[a-z0-9][a-z0-9._:-]*$'),
  display_name text not null,
  provider text not null
    check (provider in ('supabase','railway')),
  provider_project_ref text not null,
  environment_ref text,
  service_ref text,
  target_role text not null
    check (target_role in ('control_plane','shared_backend','primary_service','partial_service')),
  required_for_estate boolean not null default true,
  allowed_runtime_states text[] not null default array['active']::text[],
  lifecycle text not null default 'active'
    check (lifecycle in ('active','disabled','retired')),
  metadata jsonb not null default '{}'::jsonb,
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(allowed_runtime_states)>0),
  check (allowed_runtime_states <@ array['active','sleeping','transitioning','inactive','failed','unknown']::text[]),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_estate_targets enable row level security;

create policy shine_defence_runtime_estate_targets_select
on foundation.defence_estate_targets
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_estate_targets from public,anon,authenticated;
grant select on foundation.defence_estate_targets to shine_defence_runtime,service_role;
grant select,insert,update on foundation.defence_estate_targets to service_role;


create table foundation.defence_estate_target_apps (
  target_id text not null references foundation.defence_estate_targets(target_id),
  app_key text not null
    check (app_key ~ '^[a-z0-9][a-z0-9_:-]*$'),
  relationship text not null
    check (relationship in ('primary','shared','partial','control_plane')),
  inventory_source text not null default 'universe.app_registry',
  source_evidence_ref text not null,
  linked_at timestamptz not null default now(),
  primary key(target_id,app_key)
);

alter table foundation.defence_estate_target_apps enable row level security;

create policy shine_defence_runtime_estate_target_apps_select
on foundation.defence_estate_target_apps
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_estate_target_apps from public,anon,authenticated;
grant select on foundation.defence_estate_target_apps to shine_defence_runtime,service_role;
grant select,insert,update,delete on foundation.defence_estate_target_apps to service_role;

create index defence_estate_target_apps_app_idx
  on foundation.defence_estate_target_apps(app_key,target_id);


create table foundation.defence_estate_observations (
  observation_id uuid primary key default gen_random_uuid(),
  target_id text not null references foundation.defence_estate_targets(target_id),
  runtime_state text not null
    check (runtime_state in ('active','sleeping','transitioning','inactive','failed','unknown')),
  health_state text not null default 'unknown'
    check (health_state in ('healthy','degraded','unhealthy','unknown')),
  deployment_ref text,
  version_ref text,
  artifact_ref text,
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_kind text not null
    check (evidence_kind in ('supabase-management-api','railway-api','manual-verified')),
  evidence_ref text not null,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (valid_until>observed_at),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_estate_observations enable row level security;

create policy shine_defence_runtime_estate_observations_select
on foundation.defence_estate_observations
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_estate_observations from public,anon,authenticated;
grant select on foundation.defence_estate_observations to shine_defence_runtime,service_role;
grant insert on foundation.defence_estate_observations to service_role;

create index defence_estate_observations_current_idx
  on foundation.defence_estate_observations(target_id,observed_at desc,recorded_at desc);

create trigger defence_estate_observations_append_only
before update or delete on foundation.defence_estate_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_estate_observations
with (security_invoker=true)
as
select distinct on (target_id)
  observation_id,target_id,runtime_state,health_state,deployment_ref,version_ref,
  artifact_ref,observed_at,valid_until,evidence_kind,evidence_ref,metadata,recorded_at
from foundation.defence_estate_observations
order by target_id,observed_at desc,recorded_at desc,observation_id desc;

revoke all on foundation.current_defence_estate_observations from public,anon,authenticated;
grant select on foundation.current_defence_estate_observations to shine_defence_runtime,service_role;


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
  v_blocked_keys text[] := array['secret','token','password','credential','authorization','cookie','api_key','apikey'];
begin
  if not exists (
    select 1 from foundation.defence_estate_targets
    where target_id=p_target_id and lifecycle='active'
  ) then
    raise exception 'unknown-or-inactive-estate-target' using errcode='22023';
  end if;

  if p_runtime_state not in ('active','sleeping','transitioning','inactive','failed','unknown')
     or p_health_state not in ('healthy','degraded','unhealthy','unknown')
     or p_evidence_kind not in ('supabase-management-api','railway-api','manual-verified')
     or p_valid_until<=p_observed_at
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-estate-observation' using errcode='22023';
  end if;

  if exists (
    select 1 from unnest(v_blocked_keys) k
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

revoke all on function foundation.record_defence_estate_observation_v1(
  text,text,text,text,text,text,timestamptz,timestamptz,text,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.record_defence_estate_observation_v1(
  text,text,text,text,text,text,timestamptz,timestamptz,text,text,jsonb
) to shine_defence_runtime,service_role;


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

  select
    count(*) filter (where o.observation_id is not null and o.valid_until>now()),
    count(*) filter (where o.observation_id is null),
    count(*) filter (where o.observation_id is not null and o.valid_until<=now()),
    count(*) filter (where o.runtime_state in ('failed','inactive')),
    count(*) filter (
      where o.observation_id is not null
        and o.runtime_state<>all(t.allowed_runtime_states)
        and o.runtime_state not in ('failed','inactive')
    ),
    count(*) filter (where o.health_state in ('degraded','unhealthy')),
    count(*) filter (where o.observation_id is not null and o.health_state='unknown')
  into
    v_fresh,v_missing,v_stale,v_runtime_bad,v_runtime_unexpected,v_health_bad,v_health_unknown
  from foundation.defence_estate_targets t
  left join foundation.current_defence_estate_observations o using(target_id)
  where t.lifecycle='active' and t.required_for_estate;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'targetId',t.target_id,
      'provider',t.provider,
      'runtimeState',coalesce(o.runtime_state,'unknown'),
      'healthState',coalesce(o.health_state,'unknown'),
      'observedAt',o.observed_at,
      'validUntil',o.valid_until,
      'reason',case
        when o.observation_id is null then 'missing-observation'
        when o.valid_until<=now() then 'stale-observation'
        when o.runtime_state in ('failed','inactive') then 'runtime-failure'
        when o.runtime_state<>all(t.allowed_runtime_states) then 'unexpected-runtime-state'
        when o.health_state in ('degraded','unhealthy') then 'health-degraded'
        else 'unknown'
      end
    ) order by t.target_id
  ),'[]'::jsonb)
  into v_problem_targets
  from foundation.defence_estate_targets t
  left join foundation.current_defence_estate_observations o using(target_id)
  where t.lifecycle='active'
    and t.required_for_estate
    and (
      o.observation_id is null
      or o.valid_until<=now()
      or o.runtime_state in ('failed','inactive')
      or o.runtime_state<>all(t.allowed_runtime_states)
      or o.health_state in ('degraded','unhealthy')
    );

  v_state := case
    when v_runtime_bad>0 or v_health_bad>0 then 'fail'
    when v_missing>0 or v_stale>0 or v_runtime_unexpected>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceEstateSummary','shine-defence/estate-summary-v1',
    'schemaVersion','1.0.0',
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
    'problemTargets',v_problem_targets,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_estate_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_estate_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;


-- Supabase backend targets.
insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,target_role,required_for_estate,allowed_runtime_states,metadata
) values
  ('supabase:sjpxqeyewahraxvidvcc','Shine Foundation','supabase','sjpxqeyewahraxvidvcc','control_plane',true,array['active']::text[],jsonb_build_object('projectName','Shine Foundation')),
  ('supabase:raxfwycrnviwxxzykhfq','Shine-L','supabase','raxfwycrnviwxxzykhfq','shared_backend',true,array['active']::text[],jsonb_build_object('projectName','Shine-L')),
  ('supabase:isluulaquwvtzlwkakyq','Shine Recovery Companion','supabase','isluulaquwvtzlwkakyq','shared_backend',true,array['active']::text[],jsonb_build_object('projectName','Shine Recovery Companion')),
  ('supabase:lqicznkysqqxbrmtxmms','Shine Dive','supabase','lqicznkysqqxbrmtxmms','shared_backend',true,array['active']::text[],jsonb_build_object('projectName','Shine Dive')),
  ('supabase:ojpfpgikbqzsmuukljad','Shine Fish Oracle','supabase','ojpfpgikbqzsmuukljad','shared_backend',true,array['active']::text[],jsonb_build_object('projectName','Shine Fish Oracle')),
  ('supabase:kkdgibknfcnoyondnmdb','Shine My Money','supabase','kkdgibknfcnoyondnmdb','shared_backend',true,array['active']::text[],jsonb_build_object('projectName','Shine My Money'));

-- Railway primary service targets.
insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,target_role,required_for_estate,allowed_runtime_states,metadata
) values
  ('railway:daash','Shine DaAsh','railway','b0e8a4e4-f4ae-4bfd-aa0d-2b34fb8211d2','3f6f6eab-daac-4da7-9a1d-caaa24dccd01','e39219ad-cd27-47f8-a6c9-687181113240','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','shine-daash-x')),
  ('railway:dive','Shine Dive','railway','341772f7-a30d-4feb-b4da-2360717c1ca9','600fe8df-cc75-461c-b8bd-049bd28f0fc1','f922c795-ee8f-4a4a-92a6-7770ae06cc0a','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','shine-dive')),
  ('railway:dnd','Shine D&D capability','railway','311a5dad-75cb-462b-b503-f05a4109e8d7','8cc14012-7bf7-48fd-a647-747bb70584d4','68087e56-6908-4565-81a6-281b2ae6befe','primary_service',true,array['active','sleeping']::text[],jsonb_build_object('serviceName','shine-dnd-capability','sleepAllowed',true)),
  ('railway:fiona','Fiona Finance','railway','72648456-7ccf-4c6b-ac73-b63aaf7caffa','0bcb521a-69c0-448a-8066-442ba0a01ba1','60f991cd-0a34-47ee-998b-4df9b64fbe18','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Fiona-Finance')),
  ('railway:fish','Shine Fish','railway','81486445-2331-46db-b8f1-35e73158853d','207210fb-694b-493a-aa02-cc607d72c5e4','2282f233-7e57-4d67-b02a-403968deb390','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','shine-fish')),
  ('railway:my-money','Shine My Money','railway','406a2f6d-4542-470a-a6e8-59980f4b5500','294a94be-dbf4-4b2e-a6b4-afc5bdc5c304','14f11970-0e22-4f18-a4e0-9fb4b84bbf01','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Shine My Money')),
  ('railway:project-l','Project L / Companion','railway','72648456-7ccf-4c6b-ac73-b63aaf7caffa','0bcb521a-69c0-448a-8066-442ba0a01ba1','0edbbc64-5cb5-46b5-b818-2f938196c2a1','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Project-L-Modular')),
  ('railway:punt49','Punt-49','railway','72648456-7ccf-4c6b-ac73-b63aaf7caffa','0bcb521a-69c0-448a-8066-442ba0a01ba1','af90b122-ef51-402c-8de3-5239926da9ae','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Punt-49-Chat')),
  ('railway:recovery-companion','Shine Recovery Companion','railway','6b2a1fdf-6908-4b6a-a18a-3f1f50724497','822c00e0-0969-4dc2-8c88-2c893c2549b9','1cd8f81c-6f65-4b71-91cb-de2df70eb41f','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Project-RC')),
  ('railway:rivers','Rivers / Shine Music','railway','3dba2137-071a-4fcd-8b8d-b83b1a4615ca','287d1d11-6b96-46c1-8869-1b70a8e30952','537fb21b-a230-46b5-a7c6-8a437750bd5f','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Shine Music')),
  ('railway:shine-ai','Shine AI','railway','72648456-7ccf-4c6b-ac73-b63aaf7caffa','0bcb521a-69c0-448a-8066-442ba0a01ba1','18cd334c-5e66-4221-915e-f7c2cfdb7ef7','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Shine-AI')),
  ('railway:ski','Shine Ski','railway','4514424e-1378-4ea7-b13f-fdacce5195ee','146dbf93-17ad-47de-8d12-bda33206c4bb','85991136-5c38-443a-a476-848bda7c184e','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Shine Ski')),
  ('railway:translate','Shine Translate','railway','c30e131d-5336-4a3d-a2ca-e2f6337bb5e5','8ae2870b-7182-4ae0-a13a-2de9309d5e23','c0e989de-85fb-44d5-b966-a3bdbba60393','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Shine Translate')),
  ('railway:travel','Shine Travel','railway','72648456-7ccf-4c6b-ac73-b63aaf7caffa','0bcb521a-69c0-448a-8066-442ba0a01ba1','d47224cf-e8db-4aea-8de7-d3ccb588cf5b','primary_service',true,array['active']::text[],jsonb_build_object('serviceName','Shine-Travel-Sherpa'));

-- App-to-backend projection from the current Universe registry and live deployment discovery.
insert into foundation.defence_estate_target_apps(target_id,app_key,relationship,source_evidence_ref) values
  ('supabase:sjpxqeyewahraxvidvcc','foundation','control_plane','universe.app_registry:2026-09-28'),
  ('supabase:sjpxqeyewahraxvidvcc','defence','control_plane','universe.app_registry:2026-09-28'),
  ('supabase:raxfwycrnviwxxzykhfq','project_l','shared','universe.app_registry:2026-09-28'),
  ('supabase:raxfwycrnviwxxzykhfq','concierge','shared','universe.app_registry:2026-09-28'),
  ('supabase:raxfwycrnviwxxzykhfq','shine_me','shared','universe.app_registry:2026-09-28'),
  ('supabase:raxfwycrnviwxxzykhfq','fiona','shared','universe.app_registry:2026-09-28'),
  ('supabase:raxfwycrnviwxxzykhfq','punt49','shared','universe.app_registry:2026-09-28'),
  ('supabase:raxfwycrnviwxxzykhfq','rivers','shared','universe.app_registry:2026-09-28'),
  ('supabase:isluulaquwvtzlwkakyq','recovery_companion','shared','universe.app_registry:2026-09-28'),
  ('supabase:isluulaquwvtzlwkakyq','daash','shared','universe.app_registry:2026-09-28'),
  ('supabase:lqicznkysqqxbrmtxmms','dive','shared','universe.app_registry:2026-09-28'),
  ('supabase:lqicznkysqqxbrmtxmms','ski','shared','universe.app_registry:2026-09-28'),
  ('supabase:ojpfpgikbqzsmuukljad','fish','shared','universe.app_registry:2026-09-28'),
  ('supabase:kkdgibknfcnoyondnmdb','my_money','shared','universe.app_registry:2026-09-28'),

  ('railway:daash','daash','primary','railway-discovery:2026-09-28'),
  ('railway:dive','dive','primary','railway-discovery:2026-09-28'),
  ('railway:dnd','dnd','primary','railway-discovery:2026-09-28'),
  ('railway:fiona','fiona','primary','railway-discovery:2026-09-28'),
  ('railway:fish','fish','primary','railway-discovery:2026-09-28'),
  ('railway:my-money','my_money','primary','railway-discovery:2026-09-28'),
  ('railway:project-l','project_l','primary','railway-discovery:2026-09-28'),
  ('railway:project-l','concierge','shared','railway-discovery:2026-09-28'),
  ('railway:project-l','shine_me','shared','railway-discovery:2026-09-28'),
  ('railway:punt49','punt49','primary','railway-discovery:2026-09-28'),
  ('railway:recovery-companion','recovery_companion','primary','railway-discovery:2026-09-28'),
  ('railway:rivers','rivers','primary','railway-discovery:2026-09-28'),
  ('railway:shine-ai','shine_ai','primary','railway-discovery:2026-09-28'),
  ('railway:ski','ski','primary','railway-discovery:2026-09-28'),
  ('railway:translate','translate','primary','railway-discovery:2026-09-28'),
  ('railway:travel','travel','primary','railway-discovery:2026-09-28');
