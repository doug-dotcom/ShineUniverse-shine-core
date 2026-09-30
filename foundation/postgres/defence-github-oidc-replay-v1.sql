-- Shine Defence GitHub OIDC replay binding v1.
-- Bind one verified GitHub run/attempt + audience + operation + target to one
-- semantic request digest. Exact retries are observable and allowed; a changed
-- payload under the same identity fails closed.

create table foundation.github_oidc_operation_bindings (
  binding_id uuid primary key default gen_random_uuid(),
  repository text not null
    check (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  ref text not null
    check (length(ref) between 1 and 256 and ref !~ '[[:cntrl:]]'),
  workflow_ref text not null
    check (length(workflow_ref) between 1 and 1024 and workflow_ref !~ '[[:cntrl:]]'),
  run_id text not null
    check (run_id ~ '^[0-9]{1,32}$'),
  run_attempt text not null
    check (run_attempt ~ '^[0-9]{1,16}$'),
  event_name text not null
    check (event_name ~ '^[a-z_]{1,64}$'),
  audience text not null
    check (audience ~ '^[a-z0-9][a-z0-9._:-]{0,127}$'),
  operation text not null
    check (operation ~ '^[a-z0-9][a-z0-9._:-]{0,127}$'),
  target_key text not null
    check (length(target_key) between 1 and 512 and target_key !~ '[[:cntrl:]]'),
  request_sha256 text not null
    check (request_sha256 ~ '^[a-f0-9]{64}$'),
  bound_at timestamptz not null default clock_timestamp(),
  unique(repository,run_id,run_attempt,audience,operation,target_key)
);

alter table foundation.github_oidc_operation_bindings enable row level security;

revoke all on foundation.github_oidc_operation_bindings
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant select on foundation.github_oidc_operation_bindings
  to shine_defence_runtime,service_role;

create trigger github_oidc_operation_bindings_append_only
before update or delete on foundation.github_oidc_operation_bindings
for each row execute function foundation.reject_append_only_mutation();


create table foundation.github_oidc_operation_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  binding_id uuid not null references foundation.github_oidc_operation_bindings(binding_id),
  outcome text not null
    check (outcome in ('accepted-new','replayed-exact','rejected-conflict')),
  presented_sha256 text not null
    check (presented_sha256 ~ '^[a-f0-9]{64}$'),
  observed_at timestamptz not null default clock_timestamp(),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object')
);

alter table foundation.github_oidc_operation_events enable row level security;

revoke all on foundation.github_oidc_operation_events
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant select on foundation.github_oidc_operation_events
  to shine_defence_runtime,service_role;

create index github_oidc_operation_events_binding_idx
  on foundation.github_oidc_operation_events(binding_id,observed_at desc,event_sequence desc);

create trigger github_oidc_operation_events_append_only
before update or delete on foundation.github_oidc_operation_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.bind_github_oidc_operation_v1(
  p_repository text,
  p_ref text,
  p_workflow_ref text,
  p_run_id text,
  p_run_attempt text,
  p_event_name text,
  p_audience text,
  p_operation text,
  p_target_key text,
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $oidc_replay$
declare
  v_binding foundation.github_oidc_operation_bindings%rowtype;
  v_binding_id uuid;
  v_request_sha256 text;
  v_outcome text;
  v_allowed boolean := false;
begin
  if p_repository is null
     or p_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
     or p_ref is null
     or length(p_ref) not between 1 and 256
     or p_ref ~ '[[:cntrl:]]'
     or p_workflow_ref is null
     or length(p_workflow_ref) not between 1 and 1024
     or p_workflow_ref ~ '[[:cntrl:]]'
     or p_run_id is null
     or p_run_id !~ '^[0-9]{1,32}$'
     or p_run_attempt is null
     or p_run_attempt !~ '^[0-9]{1,16}$'
     or p_event_name is null
     or p_event_name !~ '^[a-z_]{1,64}$'
     or p_audience is null
     or p_audience !~ '^[a-z0-9][a-z0-9._:-]{0,127}$'
     or p_operation is null
     or p_operation !~ '^[a-z0-9][a-z0-9._:-]{0,127}$'
     or p_target_key is null
     or length(p_target_key) not between 1 and 512
     or p_target_key ~ '[[:cntrl:]]'
     or p_request is null
     or jsonb_typeof(p_request)<>'object'
     or pg_column_size(p_request)>131072 then
    raise exception 'github-oidc-operation-binding-invalid'
      using errcode='22023';
  end if;

  v_allowed := case p_audience
    when 'shine-defence-provider-ingest'
      then p_operation='provider-snapshot'
    when 'shine-foundation-deployment-receipt'
      then p_operation='deployment-receipt-publish'
    when 'shine-defence-release-head'
      then p_operation='release-head-snapshot'
    when 'shine-defence-rollback-readiness'
      then p_operation in ('rollback-claim','rollback-attest')
    when 'shine-defence-reattest'
      then p_operation in ('reattest-claim','reattest-attest')
    else false
  end;

  if not v_allowed then
    raise exception 'github-oidc-operation-purpose-not-allowed'
      using errcode='22023';
  end if;

  v_request_sha256 := encode(
    extensions.digest(convert_to(p_request::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.github_oidc_operation_bindings(
    repository,ref,workflow_ref,run_id,run_attempt,event_name,
    audience,operation,target_key,request_sha256
  ) values (
    p_repository,p_ref,p_workflow_ref,p_run_id,p_run_attempt,p_event_name,
    p_audience,p_operation,p_target_key,v_request_sha256
  )
  on conflict (repository,run_id,run_attempt,audience,operation,target_key)
  do nothing
  returning binding_id into v_binding_id;

  if v_binding_id is not null then
    select * into v_binding
    from foundation.github_oidc_operation_bindings
    where binding_id=v_binding_id;
    v_outcome := 'accepted-new';
  else
    select * into v_binding
    from foundation.github_oidc_operation_bindings
    where repository=p_repository
      and run_id=p_run_id
      and run_attempt=p_run_attempt
      and audience=p_audience
      and operation=p_operation
      and target_key=p_target_key;

    if v_binding.binding_id is null then
      raise exception 'github-oidc-operation-binding-race'
        using errcode='40001';
    end if;

    if v_binding.request_sha256=v_request_sha256
       and v_binding.ref=p_ref
       and v_binding.workflow_ref=p_workflow_ref
       and v_binding.event_name=p_event_name then
      v_outcome := 'replayed-exact';
    else
      v_outcome := 'rejected-conflict';
    end if;
  end if;

  insert into foundation.github_oidc_operation_events(
    binding_id,outcome,presented_sha256,metadata
  ) values (
    v_binding.binding_id,
    v_outcome,
    v_request_sha256,
    jsonb_build_object(
      'repository',p_repository,
      'ref',p_ref,
      'workflowRef',p_workflow_ref,
      'runId',p_run_id,
      'runAttempt',p_run_attempt,
      'eventName',p_event_name,
      'audience',p_audience,
      'operation',p_operation,
      'targetKey',p_target_key
    )
  );

  return jsonb_build_object(
    'githubOidcOperationBinding','shine-defence/github-oidc-operation-binding-v1',
    'schemaVersion','1.0.0',
    'status',v_outcome,
    'bindingId',v_binding.binding_id,
    'requestSha256',v_request_sha256,
    'originalRequestSha256',v_binding.request_sha256,
    'audience',p_audience,
    'operation',p_operation,
    'targetKey',p_target_key
  );
end;
$oidc_replay$;

revoke all on function foundation.bind_github_oidc_operation_v1(
  text,text,text,text,text,text,text,text,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.bind_github_oidc_operation_v1(
  text,text,text,text,text,text,text,text,text,jsonb
) to service_role;


-- Provider snapshots are the one OIDC destination that was not already
-- naturally idempotent. Evidence refs now identify one immutable observation.
alter table foundation.defence_estate_observations
  add constraint defence_estate_observations_evidence_ref_unique
  unique (evidence_ref);

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
as $estate_idempotency$
declare
  v_id uuid;
  v_existing foundation.defence_estate_observations%rowtype;
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
     or p_evidence_kind not in (
       'supabase-management-api','railway-api','manual-verified',
       'github-oidc','supabase-runtime-receipt'
     )
     or p_valid_until<=p_observed_at
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object'
     or p_evidence_ref is null
     or char_length(p_evidence_ref)>1024 then
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
  on conflict (evidence_ref) do nothing
  returning observation_id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  select * into v_existing
  from foundation.defence_estate_observations
  where evidence_ref=p_evidence_ref;

  if v_existing.observation_id is null
     or v_existing.target_id is distinct from p_target_id
     or v_existing.runtime_state is distinct from p_runtime_state
     or v_existing.health_state is distinct from p_health_state
     or v_existing.deployment_ref is distinct from p_deployment_ref
     or v_existing.version_ref is distinct from p_version_ref
     or v_existing.artifact_ref is distinct from p_artifact_ref
     or v_existing.observed_at is distinct from p_observed_at
     or v_existing.valid_until is distinct from p_valid_until
     or v_existing.evidence_kind is distinct from p_evidence_kind
     or v_existing.metadata is distinct from p_metadata then
    raise exception 'estate-observation-evidence-conflict'
      using errcode='23505';
  end if;

  return v_existing.observation_id;
end;
$estate_idempotency$;

revoke all on function foundation.record_defence_estate_observation_v1(
  text,text,text,text,text,text,timestamptz,timestamptz,text,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.record_defence_estate_observation_v1(
  text,text,text,text,text,text,timestamptz,timestamptz,text,text,jsonb
) to shine_defence_runtime,service_role;
