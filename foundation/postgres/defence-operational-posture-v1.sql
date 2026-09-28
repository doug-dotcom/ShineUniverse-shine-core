-- Shine Defence operational posture v1.
-- Internal-only, evidence-backed checks over Foundation/Postgres security and deployment truth.
-- This contract deliberately does not expose detailed posture through the public Foundation Gateway.

do $$
begin
  if not exists (select 1 from pg_roles where rolname='shine_defence_runtime') then
    create role shine_defence_runtime nologin nosuperuser nocreatedb nocreaterole nobypassrls;
  else
    alter role shine_defence_runtime nologin nosuperuser nocreatedb nocreaterole nobypassrls;
  end if;
end
$$;

grant usage on schema foundation to shine_defence_runtime;

-- Close the one live Foundation table that was private by grants but lacked RLS.
do $$
begin
  if to_regclass('foundation.integration_delegation_refresh_requests') is not null then
    alter table foundation.integration_delegation_refresh_requests enable row level security;
    revoke all on table foundation.integration_delegation_refresh_requests from public,anon,authenticated;
    drop policy if exists deny_public_delegation_refresh_requests on foundation.integration_delegation_refresh_requests;
    create policy deny_public_delegation_refresh_requests
      on foundation.integration_delegation_refresh_requests
      as restrictive
      for all
      to anon,authenticated
      using (false)
      with check (false);
  end if;
end
$$;

create table foundation.defence_external_evidence (
  evidence_id uuid primary key default gen_random_uuid(),
  domain text not null
    check (domain in ('auth','rls','service_to_service','secrets','dependencies','data_exposure','deployment_integrity')),
  subject_ref text not null
    check (subject_ref ~ '^[a-z0-9][a-z0-9._:/-]*$'),
  status text not null
    check (status in ('pass','warning','fail','unknown')),
  artifact_sha256 text
    check (artifact_sha256 is null or artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_kind text not null
    check (evidence_kind in ('supabase-api','source-inspection','ci','dependency-audit','deployment-api','manual-verified')),
  evidence_ref text not null,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (valid_until > observed_at),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_external_evidence enable row level security;

create policy shine_defence_runtime_external_evidence_select
on foundation.defence_external_evidence
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_external_evidence from public,anon,authenticated;
grant select on foundation.defence_external_evidence to shine_defence_runtime,service_role;
grant insert on foundation.defence_external_evidence to service_role;

create index defence_external_evidence_current_idx
  on foundation.defence_external_evidence(domain,subject_ref,observed_at desc,recorded_at desc);

create trigger defence_external_evidence_append_only
before update or delete on foundation.defence_external_evidence
for each row execute function foundation.reject_append_only_mutation();


create table foundation.defence_posture_observations (
  observation_id uuid primary key default gen_random_uuid(),
  posture_version text not null default '1.0.0'
    check (posture_version='1.0.0'),
  environment text not null default 'production'
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  overall_state text not null
    check (overall_state in ('pass','warning','fail','unknown')),
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  checks jsonb not null,
  evidence_ref text not null,
  recorded_at timestamptz not null default now(),
  check (valid_until > observed_at),
  check (jsonb_typeof(checks)='object')
);

alter table foundation.defence_posture_observations enable row level security;

create policy shine_defence_runtime_posture_select
on foundation.defence_posture_observations
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_posture_observations from public,anon,authenticated;
grant select on foundation.defence_posture_observations to shine_defence_runtime,service_role;
grant insert on foundation.defence_posture_observations to service_role;

create index defence_posture_observations_current_idx
  on foundation.defence_posture_observations(environment,observed_at desc,recorded_at desc);

create trigger defence_posture_observations_append_only
before update or delete on foundation.defence_posture_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_posture
with (security_invoker=true)
as
select distinct on (environment)
  observation_id,
  posture_version,
  environment,
  overall_state,
  observed_at,
  valid_until,
  checks,
  evidence_ref,
  recorded_at
from foundation.defence_posture_observations
order by environment,observed_at desc,recorded_at desc,observation_id desc;

revoke all on foundation.current_defence_posture from public,anon,authenticated;
grant select on foundation.current_defence_posture to shine_defence_runtime,service_role;


create or replace function foundation.record_defence_external_evidence_v1(
  p_domain text,
  p_subject_ref text,
  p_status text,
  p_artifact_sha256 text,
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
  if p_domain not in ('auth','rls','service_to_service','secrets','dependencies','data_exposure','deployment_integrity')
     or p_status not in ('pass','warning','fail','unknown')
     or p_subject_ref !~ '^[a-z0-9][a-z0-9._:/-]*$'
     or p_valid_until<=p_observed_at
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object'
     or (p_artifact_sha256 is not null and p_artifact_sha256 !~ '^[a-fA-F0-9]{64}$') then
    raise exception 'invalid-defence-evidence' using errcode='22023';
  end if;

  if exists (
    select 1
    from unnest(v_blocked_keys) k
    where p_metadata ? k
  ) then
    raise exception 'sensitive-defence-evidence-metadata-key' using errcode='22023';
  end if;

  insert into foundation.defence_external_evidence(
    domain,subject_ref,status,artifact_sha256,observed_at,valid_until,
    evidence_kind,evidence_ref,metadata
  ) values (
    p_domain,p_subject_ref,p_status,lower(p_artifact_sha256),p_observed_at,p_valid_until,
    p_evidence_kind,p_evidence_ref,p_metadata
  )
  returning evidence_id into v_id;

  return v_id;
end;
$$;

revoke all on function foundation.record_defence_external_evidence_v1(
  text,text,text,text,timestamptz,timestamptz,text,text,jsonb
) from public,anon,authenticated;
grant execute on function foundation.record_defence_external_evidence_v1(
  text,text,text,text,timestamptz,timestamptz,text,text,jsonb
) to shine_defence_runtime,service_role;


create or replace function foundation.evaluate_defence_posture_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_rls_disabled integer := 0;
  v_definer_exposed integer := 0;
  v_role_violations integer := 0;
  v_unexpected_runtime_writes integer := 0;
  v_invalid_hashes integer := 0;
  v_public_secret_access integer := 0;
  v_public_schema_usage integer := 0;
  v_public_table_grants integer := 0;
  v_core_services integer := 0;
  v_deployment_drift integer := 0;
  v_deployment_unknown integer := 0;
  v_auth_missing integer := 0;
  v_auth_bad integer := 0;
  v_auth_warning integer := 0;
  v_dependency_missing integer := 0;
  v_dependency_bad integer := 0;
  v_dependency_warning integer := 0;
  v_state_auth text;
  v_state_rls text;
  v_state_s2s text;
  v_state_secrets text;
  v_state_dependencies text;
  v_state_exposure text;
  v_state_deployment text;
  v_overall text;
  v_checks jsonb;
  v_target record;
  v_n integer;
begin
  if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'invalid-defence-environment' using errcode='22023';
  end if;

  select count(*) into v_rls_disabled
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('foundation','universe')
    and c.relkind in ('r','p')
    and not c.relrowsecurity;

  select count(*) into v_definer_exposed
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('foundation','universe')
    and p.prosecdef
    and (
      pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE')
      or pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE')
    );

  select count(*) into v_role_violations
  from (
    values ('foundation_runtime'),('foundation_gateway'),('shine_defence_runtime')
  ) expected(role_name)
  left join pg_catalog.pg_roles r on r.rolname=expected.role_name
  where r.oid is null
     or r.rolsuper
     or r.rolcreaterole
     or r.rolcreatedb
     or r.rolcanlogin
     or r.rolbypassrls;

  select count(*) into v_unexpected_runtime_writes
  from information_schema.role_table_grants g
  where g.table_schema in ('foundation','universe')
    and g.privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
    and (
      g.grantee='foundation_gateway'
      or (
        g.grantee='foundation_runtime'
        and not (
          g.table_schema='foundation'
          and g.table_name='access_audit_events'
          and g.privilege_type='INSERT'
        )
      )
      or g.grantee='shine_defence_runtime'
    );

  for v_target in
    select *
    from (values
      ('app_credentials','token_hash'),
      ('integration_client_credentials','token_hash'),
      ('integration_delegation_sessions','token_hash'),
      ('integration_delegation_refresh_credentials','token_hash'),
      ('integration_delegation_refresh_requests','new_refresh_token_hash'),
      ('integration_delegation_refresh_requests','new_delegation_token_hash')
    ) as t(table_name,column_name)
  loop
    if pg_catalog.to_regclass('foundation.'||v_target.table_name) is not null then
      execute pg_catalog.format(
        'select count(*) from foundation.%I where %I is null or %I !~ %L',
        v_target.table_name,
        v_target.column_name,
        v_target.column_name,
        '^[a-fA-F0-9]{64}$'
      ) into v_n;
      v_invalid_hashes := v_invalid_hashes + v_n;
    end if;
  end loop;

  for v_target in
    select *
    from (values
      ('foundation.app_credentials'),
      ('foundation.integration_client_credentials'),
      ('foundation.integration_delegation_sessions'),
      ('foundation.integration_delegation_refresh_credentials'),
      ('foundation.integration_delegation_refresh_requests')
    ) as t(relation_name)
  loop
    if pg_catalog.to_regclass(v_target.relation_name) is not null then
      if pg_catalog.has_table_privilege('anon',v_target.relation_name,'SELECT')
         or pg_catalog.has_table_privilege('authenticated',v_target.relation_name,'SELECT') then
        v_public_secret_access := v_public_secret_access + 1;
      end if;
    end if;
  end loop;

  select count(*) into v_public_schema_usage
  from pg_catalog.pg_namespace n
  cross join (values ('anon'),('authenticated')) r(role_name)
  where n.nspname in ('foundation','universe')
    and pg_catalog.has_schema_privilege(r.role_name,n.oid,'USAGE');

  select count(*) into v_public_table_grants
  from information_schema.role_table_grants g
  where g.table_schema in ('foundation','universe')
    and g.grantee in ('anon','authenticated');

  select
    count(*),
    count(*) filter (where truth->>'truthState'='drift'),
    count(*) filter (where truth->>'truthState'='unknown')
  into v_core_services,v_deployment_drift,v_deployment_unknown
  from (
    select foundation.get_service_deployment_truth_v1(s.service_id,p_environment) truth
    from foundation.service_registry s
    where s.required_for_core
      and s.lifecycle='active'
  ) x;

  select
    count(*) filter (where a.status is null),
    count(*) filter (where a.status='fail'),
    count(*) filter (where a.status in ('warning','unknown'))
  into v_auth_missing,v_auth_bad,v_auth_warning
  from foundation.service_registry s
  left join foundation.current_service_deployment_observations o
    on o.service_id=s.service_id and o.environment=p_environment
  left join lateral (
    select e.status
    from foundation.defence_external_evidence e
    where e.domain='auth'
      and e.subject_ref=s.service_id
      and e.valid_until>pg_catalog.now()
      and e.artifact_sha256 is not distinct from o.artifact_sha256
    order by e.observed_at desc,e.recorded_at desc,e.evidence_id desc
    limit 1
  ) a on true
  where s.required_for_core
    and s.lifecycle='active';

  select
    count(*) filter (where d.status is null),
    count(*) filter (where d.status='fail'),
    count(*) filter (where d.status in ('warning','unknown'))
  into v_dependency_missing,v_dependency_bad,v_dependency_warning
  from foundation.service_registry s
  left join foundation.current_service_deployment_observations o
    on o.service_id=s.service_id and o.environment=p_environment
  left join lateral (
    select e.status
    from foundation.defence_external_evidence e
    where e.domain='dependencies'
      and e.subject_ref=s.service_id
      and e.valid_until>pg_catalog.now()
      and e.artifact_sha256 is not distinct from o.artifact_sha256
    order by e.observed_at desc,e.recorded_at desc,e.evidence_id desc
    limit 1
  ) d on true
  where s.required_for_core
    and s.lifecycle='active';

  v_state_auth := case
    when v_definer_exposed>0 or v_auth_bad>0 then 'fail'
    when v_auth_missing>0 or v_auth_warning>0 then 'warning'
    else 'pass'
  end;

  v_state_rls := case when v_rls_disabled>0 then 'fail' else 'pass' end;

  v_state_s2s := case
    when v_role_violations>0 or v_unexpected_runtime_writes>0 then 'fail'
    else 'pass'
  end;

  v_state_secrets := case
    when v_invalid_hashes>0 or v_public_secret_access>0 then 'fail'
    else 'pass'
  end;

  v_state_dependencies := case
    when v_dependency_bad>0 then 'fail'
    when v_dependency_missing>0 or v_dependency_warning>0 then 'warning'
    else 'pass'
  end;

  v_state_exposure := case
    when v_public_schema_usage>0 or v_public_table_grants>0 or v_definer_exposed>0 then 'fail'
    else 'pass'
  end;

  v_state_deployment := case
    when v_deployment_drift>0 then 'fail'
    when v_core_services=0 or v_deployment_unknown>0 then 'warning'
    else 'pass'
  end;

  v_overall := case
    when 'fail' in (v_state_auth,v_state_rls,v_state_s2s,v_state_secrets,v_state_dependencies,v_state_exposure,v_state_deployment) then 'fail'
    when 'warning' in (v_state_auth,v_state_rls,v_state_s2s,v_state_secrets,v_state_dependencies,v_state_exposure,v_state_deployment) then 'warning'
    else 'pass'
  end;

  v_checks := jsonb_build_object(
    'auth',jsonb_build_object(
      'state',v_state_auth,
      'publicSecurityDefinerFunctions',v_definer_exposed,
      'coreServicesMissingArtifactBoundEvidence',v_auth_missing,
      'coreServicesFailingEvidence',v_auth_bad,
      'coreServicesWarningEvidence',v_auth_warning
    ),
    'rls',jsonb_build_object(
      'state',v_state_rls,
      'tablesWithoutRls',v_rls_disabled
    ),
    'serviceToService',jsonb_build_object(
      'state',v_state_s2s,
      'runtimeRoleViolations',v_role_violations,
      'unexpectedRuntimeWriteGrants',v_unexpected_runtime_writes
    ),
    'secrets',jsonb_build_object(
      'state',v_state_secrets,
      'invalidCredentialHashes',v_invalid_hashes,
      'publiclyReadableCredentialStores',v_public_secret_access
    ),
    'dependencies',jsonb_build_object(
      'state',v_state_dependencies,
      'coreServicesMissingArtifactBoundEvidence',v_dependency_missing,
      'coreServicesFailingEvidence',v_dependency_bad,
      'coreServicesWarningEvidence',v_dependency_warning
    ),
    'dataExposure',jsonb_build_object(
      'state',v_state_exposure,
      'publicSchemaUsageGrants',v_public_schema_usage,
      'publicTableGrants',v_public_table_grants,
      'publicSecurityDefinerFunctions',v_definer_exposed
    ),
    'deploymentIntegrity',jsonb_build_object(
      'state',v_state_deployment,
      'requiredCoreServices',v_core_services,
      'driftedServices',v_deployment_drift,
      'unknownServices',v_deployment_unknown
    )
  );

  return jsonb_build_object(
    'defencePosture','shine-defence/operational-posture-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'overallState',v_overall,
    'evaluatedAt',pg_catalog.now(),
    'checks',v_checks
  );
end;
$$;

revoke all on function foundation.evaluate_defence_posture_v1(text)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.evaluate_defence_posture_v1(text)
  to shine_defence_runtime,service_role;


create or replace function foundation.record_defence_posture_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now(),
  p_valid_until timestamptz default now()+interval '2 hours',
  p_evidence_ref text default 'postgres:foundation:defence-operational-posture-v1'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_posture jsonb;
  v_id uuid;
begin
  if p_valid_until<=p_observed_at then
    raise exception 'invalid-defence-posture-validity' using errcode='22023';
  end if;

  v_posture := foundation.evaluate_defence_posture_v1(p_environment);

  insert into foundation.defence_posture_observations(
    environment,overall_state,observed_at,valid_until,checks,evidence_ref
  ) values (
    p_environment,v_posture->>'overallState',p_observed_at,p_valid_until,
    v_posture->'checks',p_evidence_ref
  )
  returning observation_id into v_id;

  return v_posture
    || jsonb_build_object(
      'observationId',v_id,
      'observedAt',p_observed_at,
      'validUntil',p_valid_until,
      'evidenceRef',p_evidence_ref
    );
end;
$$;

revoke all on function foundation.record_defence_posture_v1(text,timestamptz,timestamptz,text)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.record_defence_posture_v1(text,timestamptz,timestamptz,text)
  to shine_defence_runtime,service_role;


-- Seed bounded evidence for the exact Gateway v71 artifact inspected during this layer.
select foundation.record_defence_external_evidence_v1(
  'auth',
  'foundation.gateway',
  'pass',
  '18b6b0e4198bab8054234b325a80a6f98009817fbc2c38953922f5b4018f8c3b',
  now(),
  now()+interval '7 days',
  'source-inspection',
  'supabase:edge-function:foundation-gateway:v71:custom-auth-boundary',
  jsonb_build_object(
    'verifyJwt',false,
    'customCredentialBoundary',true,
    'runtimeRole','foundation_gateway',
    'securityDefinerPublicExecute',false
  )
);

select foundation.record_defence_external_evidence_v1(
  'dependencies',
  'foundation.gateway',
  'pass',
  '18b6b0e4198bab8054234b325a80a6f98009817fbc2c38953922f5b4018f8c3b',
  now(),
  now()+interval '7 days',
  'source-inspection',
  'github:shine-core:foundation-runtime-imports:v71',
  jsonb_build_object(
    'runtimeImport','npm:postgres@3.4.9',
    'pinned',true,
    'unversionedRuntimeImports',0
  )
);

select foundation.record_defence_posture_v1(
  'production',
  now(),
  now()+interval '24 hours',
  'postgres:foundation:defence-operational-posture-v1:initial'
);
