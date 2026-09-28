-- Foundation Layer 21: canonical deployment truth.
-- Separates declared service identity, expected deployment state and observed runtime state.
-- Deployment alignment is intentionally distinct from health.

create table foundation.service_registry (
  service_id text primary key
    check (service_id ~ '^[a-z0-9][a-z0-9._:-]*$'),
  display_name text not null,
  owner_component text not null
    check (owner_component in ('shine-core','shine-id','shine-vault','universe')),
  service_kind text not null
    check (service_kind in ('supabase-edge-function','database-contract','railway-service','external-service','internal-service')),
  contract_ref text,
  required_for_core boolean not null default false,
  lifecycle text not null default 'active'
    check (lifecycle in ('active','disabled','retired')),
  metadata jsonb not null default '{}'::jsonb,
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.service_registry enable row level security;

create policy foundation_runtime_service_registry_select
on foundation.service_registry
for select
to foundation_runtime
using (true);

revoke all on foundation.service_registry from public,anon,authenticated;
grant select on foundation.service_registry to foundation_runtime;
grant select,insert,update on foundation.service_registry to service_role;


create table foundation.service_deployment_expectations (
  expectation_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  expected_runtime_ref text not null,
  expected_version text,
  expected_artifact_sha256 text
    check (expected_artifact_sha256 is null or expected_artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  expected_state text not null default 'active'
    check (expected_state in ('active','degraded','inactive','disabled')),
  source_ref text,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now()
);

alter table foundation.service_deployment_expectations enable row level security;

create policy foundation_runtime_service_deployment_expectations_select
on foundation.service_deployment_expectations
for select
to foundation_runtime
using (true);

revoke all on foundation.service_deployment_expectations from public,anon,authenticated;
grant select on foundation.service_deployment_expectations to foundation_runtime;
grant select,insert on foundation.service_deployment_expectations to service_role;

create index service_deployment_expectations_current_idx
  on foundation.service_deployment_expectations(service_id,environment,effective_at desc,recorded_at desc);

create trigger service_deployment_expectations_append_only
before update or delete on foundation.service_deployment_expectations
for each row execute function foundation.reject_append_only_mutation();


create table foundation.service_deployment_observations (
  observation_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  runtime_ref text not null,
  runtime_version text,
  artifact_sha256 text
    check (artifact_sha256 is null or artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  runtime_state text not null
    check (runtime_state in ('active','degraded','inactive','failed','unknown')),
  health_state text not null default 'unknown'
    check (health_state in ('healthy','degraded','unhealthy','unknown')),
  observed_at timestamptz not null,
  evidence_kind text not null
    check (evidence_kind in ('supabase-api','railway-api','healthcheck','deployment-api','manual-verified')),
  evidence_ref text not null,
  evidence_note text,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.service_deployment_observations enable row level security;

create policy foundation_runtime_service_deployment_observations_select
on foundation.service_deployment_observations
for select
to foundation_runtime
using (true);

revoke all on foundation.service_deployment_observations from public,anon,authenticated;
grant select on foundation.service_deployment_observations to foundation_runtime;
grant select,insert on foundation.service_deployment_observations to service_role;

create index service_deployment_observations_current_idx
  on foundation.service_deployment_observations(service_id,environment,observed_at desc,recorded_at desc);

create trigger service_deployment_observations_append_only
before update or delete on foundation.service_deployment_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_service_deployment_expectations
with (security_invoker=true)
as
select distinct on (service_id,environment)
  expectation_id,
  service_id,
  environment,
  expected_runtime_ref,
  expected_version,
  expected_artifact_sha256,
  expected_state,
  source_ref,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.service_deployment_expectations
order by service_id,environment,effective_at desc,recorded_at desc,expectation_id desc;

revoke all on foundation.current_service_deployment_expectations from public,anon,authenticated;
grant select on foundation.current_service_deployment_expectations to foundation_runtime;


create view foundation.current_service_deployment_observations
with (security_invoker=true)
as
select distinct on (service_id,environment)
  observation_id,
  service_id,
  environment,
  runtime_ref,
  runtime_version,
  artifact_sha256,
  runtime_state,
  health_state,
  observed_at,
  evidence_kind,
  evidence_ref,
  evidence_note,
  metadata,
  recorded_at
from foundation.service_deployment_observations
order by service_id,environment,observed_at desc,recorded_at desc,observation_id desc;

revoke all on foundation.current_service_deployment_observations from public,anon,authenticated;
grant select on foundation.current_service_deployment_observations to foundation_runtime;


create or replace function foundation.get_service_deployment_truth_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_service foundation.service_registry%rowtype;
  v_expected foundation.service_deployment_expectations%rowtype;
  v_observed foundation.service_deployment_observations%rowtype;
  v_reasons text[] := array[]::text[];
  v_truth_state text;
  v_health_state text := 'unknown';
begin
  select *
    into v_service
  from foundation.service_registry
  where service_id=p_service_id;

  if v_service.service_id is null then
    return jsonb_build_object(
      'deploymentTruthResponse','shine-foundation/deployment-truth-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'truthState','unknown',
      'healthState','unknown',
      'reasonCodes',jsonb_build_array('unknown-service')
    );
  end if;

  select *
    into v_expected
  from foundation.current_service_deployment_expectations
  where service_id=p_service_id
    and environment=p_environment;

  select *
    into v_observed
  from foundation.current_service_deployment_observations
  where service_id=p_service_id
    and environment=p_environment;

  if v_expected.expectation_id is null then
    v_reasons := array_append(v_reasons,'missing-expectation');
  end if;

  if v_observed.observation_id is null then
    v_reasons := array_append(v_reasons,'missing-observation');
  else
    v_health_state := v_observed.health_state;
  end if;

  if v_expected.expectation_id is not null and v_observed.observation_id is not null then
    if v_expected.expected_runtime_ref is distinct from v_observed.runtime_ref then
      v_reasons := array_append(v_reasons,'runtime-ref-mismatch');
    end if;

    if v_expected.expected_version is not null
       and v_expected.expected_version is distinct from v_observed.runtime_version then
      v_reasons := array_append(v_reasons,'version-mismatch');
    end if;

    if v_expected.expected_artifact_sha256 is not null
       and v_expected.expected_artifact_sha256 is distinct from v_observed.artifact_sha256 then
      v_reasons := array_append(v_reasons,'artifact-mismatch');
    end if;

    if v_expected.expected_state is distinct from v_observed.runtime_state then
      v_reasons := array_append(v_reasons,'runtime-state-mismatch');
    end if;
  end if;

  if v_expected.expectation_id is null or v_observed.observation_id is null then
    v_truth_state := 'unknown';
  elsif cardinality(v_reasons)=0 then
    v_truth_state := 'aligned';
  else
    v_truth_state := 'drift';
  end if;

  return jsonb_build_object(
    'deploymentTruthResponse','shine-foundation/deployment-truth-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',v_service.service_id,
    'displayName',v_service.display_name,
    'ownerComponent',v_service.owner_component,
    'serviceKind',v_service.service_kind,
    'contractRef',v_service.contract_ref,
    'requiredForCore',v_service.required_for_core,
    'lifecycle',v_service.lifecycle,
    'environment',p_environment,
    'truthState',v_truth_state,
    'healthState',v_health_state,
    'reasonCodes',to_jsonb(v_reasons),
    'expected',case
      when v_expected.expectation_id is null then null
      else jsonb_build_object(
        'runtimeRef',v_expected.expected_runtime_ref,
        'version',v_expected.expected_version,
        'artifactSha256',v_expected.expected_artifact_sha256,
        'runtimeState',v_expected.expected_state,
        'sourceRef',v_expected.source_ref,
        'effectiveAt',v_expected.effective_at,
        'evidenceRef',v_expected.evidence_ref
      )
    end,
    'observed',case
      when v_observed.observation_id is null then null
      else jsonb_build_object(
        'runtimeRef',v_observed.runtime_ref,
        'version',v_observed.runtime_version,
        'artifactSha256',v_observed.artifact_sha256,
        'runtimeState',v_observed.runtime_state,
        'healthState',v_observed.health_state,
        'observedAt',v_observed.observed_at,
        'evidenceKind',v_observed.evidence_kind,
        'evidenceRef',v_observed.evidence_ref
      )
    end
  );
end;
$$;

revoke all on function foundation.get_service_deployment_truth_v1(text,text) from public,anon,authenticated;
grant execute on function foundation.get_service_deployment_truth_v1(text,text) to foundation_runtime;


insert into foundation.service_registry(
  service_id,
  display_name,
  owner_component,
  service_kind,
  contract_ref,
  required_for_core,
  lifecycle,
  metadata
)
values (
  'foundation.gateway',
  'Foundation Gateway',
  'shine-core',
  'supabase-edge-function',
  'shine-foundation/foundation-v1',
  true,
  'active',
  jsonb_build_object(
    'projectRef','sjpxqeyewahraxvidvcc',
    'edgeFunctionSlug','foundation-gateway'
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

insert into foundation.service_deployment_expectations(
  service_id,
  environment,
  expected_runtime_ref,
  expected_version,
  expected_artifact_sha256,
  expected_state,
  source_ref,
  effective_at,
  evidence_ref,
  evidence_note
)
select
  'foundation.gateway',
  'production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  '71',
  '18b6b0e4198bab8054234b325a80a6f98009817fbc2c38953922f5b4018f8c3b',
  'active',
  null,
  now(),
  'supabase:edge-function:foundation-gateway:v71',
  'Expected state pinned from a verified active runtime observation. Git commit provenance is intentionally not asserted.'
where not exists (
  select 1
  from foundation.service_deployment_expectations
  where service_id='foundation.gateway'
    and environment='production'
    and evidence_ref='supabase:edge-function:foundation-gateway:v71'
);

insert into foundation.service_deployment_observations(
  service_id,
  environment,
  runtime_ref,
  runtime_version,
  artifact_sha256,
  runtime_state,
  health_state,
  observed_at,
  evidence_kind,
  evidence_ref,
  evidence_note,
  metadata
)
select
  'foundation.gateway',
  'production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  '71',
  '18b6b0e4198bab8054234b325a80a6f98009817fbc2c38953922f5b4018f8c3b',
  'active',
  'unknown',
  now(),
  'supabase-api',
  'supabase:edge-function:foundation-gateway:v71',
  'Supabase reports the Edge Function ACTIVE at version 71. Runtime active state is not treated as a health measurement.',
  jsonb_build_object('verifyJwt',false)
where not exists (
  select 1
  from foundation.service_deployment_observations
  where service_id='foundation.gateway'
    and environment='production'
    and evidence_ref='supabase:edge-function:foundation-gateway:v71'
);
