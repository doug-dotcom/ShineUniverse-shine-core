-- Shine Defence automatic artefact re-attestation v1.
-- Required-core deployments must bind an exact immutable source commit.
-- Missing or expired exact-artifact assurance is then eligible for GitHub OIDC re-attestation.

create table foundation.defence_artifact_attestation_events (
  event_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  artifact_sha256 text not null
    check (artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  source_ref text not null,
  source_commit text not null
    check (source_commit ~ '^[a-fA-F0-9]{40}$'),
  state text not null
    check (state in ('pass','fail')),
  auth_status text not null
    check (auth_status in ('pass','fail')),
  dependencies_status text not null
    check (dependencies_status in ('pass','fail')),
  inspector_version text not null,
  policy_commit text not null
    check (policy_commit ~ '^[a-fA-F0-9]{40}$'),
  report_sha256 text not null
    check (report_sha256 ~ '^[a-fA-F0-9]{64}$'),
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (valid_until>observed_at),
  check (jsonb_typeof(metadata)='object'),
  check (
    (state='pass' and auth_status='pass' and dependencies_status='pass')
    or state='fail'
  )
);

alter table foundation.defence_artifact_attestation_events enable row level security;

create policy shine_defence_runtime_artifact_attestation_events_select
on foundation.defence_artifact_attestation_events
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_artifact_attestation_events from public,anon,authenticated;
grant select on foundation.defence_artifact_attestation_events to shine_defence_runtime,service_role;
grant insert on foundation.defence_artifact_attestation_events to service_role;

create index defence_artifact_attestation_service_idx
  on foundation.defence_artifact_attestation_events(
    service_id,environment,observed_at desc,recorded_at desc
  );

create trigger defence_artifact_attestation_events_append_only
before update or delete on foundation.defence_artifact_attestation_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.enforce_core_deployment_source_binding_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_required boolean := false;
begin
  select required_for_core
    into v_required
  from foundation.service_registry
  where service_id=new.service_id;

  if coalesce(v_required,false)
     and (
       new.source_ref is null
       or new.source_ref !~ '^github://[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/commit/[a-fA-F0-9]{40}$'
     ) then
    raise exception 'required-core-deployment-source-binding-required'
      using errcode='22023';
  end if;

  return new;
end;
$$;

drop trigger if exists service_deployment_expectations_require_core_source
  on foundation.service_deployment_expectations;

create trigger service_deployment_expectations_require_core_source
before insert on foundation.service_deployment_expectations
for each row execute function foundation.enforce_core_deployment_source_binding_v1();


create or replace function foundation.bind_current_service_source_v1(
  p_service_id text,
  p_environment text,
  p_source_ref text,
  p_evidence_ref text,
  p_evidence_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_service foundation.service_registry%rowtype;
  v_expected foundation.service_deployment_expectations%rowtype;
  v_observed foundation.service_deployment_observations%rowtype;
  v_id uuid;
begin
  if p_source_ref !~ '^github://[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/commit/[a-fA-F0-9]{40}$'
     or p_evidence_ref is null
     or length(p_evidence_ref)=0 then
    raise exception 'invalid-core-source-binding' using errcode='22023';
  end if;

  select * into v_service
  from foundation.service_registry
  where service_id=p_service_id
    and lifecycle='active';

  if v_service.service_id is null or not v_service.required_for_core then
    raise exception 'source-binding-requires-active-core-service' using errcode='22023';
  end if;

  select * into v_expected
  from foundation.current_service_deployment_expectations
  where service_id=p_service_id and environment=p_environment;

  select * into v_observed
  from foundation.current_service_deployment_observations
  where service_id=p_service_id and environment=p_environment;

  if v_expected.expectation_id is null
     or v_observed.observation_id is null
     or v_expected.expected_runtime_ref is distinct from v_observed.runtime_ref
     or (
       v_expected.expected_version is not null
       and v_expected.expected_version is distinct from v_observed.runtime_version
     )
     or (
       v_expected.expected_artifact_sha256 is not null
       and v_expected.expected_artifact_sha256 is distinct from v_observed.artifact_sha256
     )
     or v_expected.expected_state is distinct from v_observed.runtime_state
     or v_observed.artifact_sha256 is null then
    raise exception 'cannot-bind-source-to-unaligned-deployment' using errcode='22023';
  end if;

  insert into foundation.service_deployment_expectations(
    service_id,environment,expected_runtime_ref,expected_version,
    expected_artifact_sha256,expected_state,source_ref,effective_at,
    evidence_ref,evidence_note
  ) values (
    v_expected.service_id,
    v_expected.environment,
    v_expected.expected_runtime_ref,
    v_expected.expected_version,
    v_expected.expected_artifact_sha256,
    v_expected.expected_state,
    p_source_ref,
    clock_timestamp(),
    p_evidence_ref,
    coalesce(p_evidence_note,'Exact immutable source commit bound to the current aligned core deployment.')
  )
  returning expectation_id into v_id;

  return v_id;
end;
$$;

revoke all on function foundation.bind_current_service_source_v1(text,text,text,text,text)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.bind_current_service_source_v1(text,text,text,text,text)
  to service_role;


create or replace function foundation.get_defence_reattestation_work_v1(
  p_force boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_row record;
  v_auth_status text;
  v_dependency_status text;
  v_source_commit text;
  v_source_repository text;
begin
  for v_row in
    select
      s.service_id,
      s.display_name,
      e.environment,
      e.expected_version,
      e.expected_artifact_sha256,
      e.source_ref,
      o.artifact_sha256 as observed_artifact_sha256,
      o.runtime_version,
      o.runtime_state,
      foundation.get_service_deployment_truth_v1(s.service_id,e.environment) as truth
    from foundation.service_registry s
    join foundation.current_service_deployment_expectations e
      on e.service_id=s.service_id
    left join foundation.current_service_deployment_observations o
      on o.service_id=s.service_id and o.environment=e.environment
    where s.required_for_core
      and s.lifecycle='active'
    order by s.service_id,e.environment
  loop
    if v_row.truth->>'truthState'<>'aligned'
       or v_row.observed_artifact_sha256 is null then
      continue;
    end if;

    select status into v_auth_status
    from foundation.defence_external_evidence
    where domain='auth'
      and subject_ref=v_row.service_id
      and artifact_sha256=v_row.observed_artifact_sha256
      and valid_until>now()
    order by observed_at desc,recorded_at desc,evidence_id desc
    limit 1;

    select status into v_dependency_status
    from foundation.defence_external_evidence
    where domain='dependencies'
      and subject_ref=v_row.service_id
      and artifact_sha256=v_row.observed_artifact_sha256
      and valid_until>now()
    order by observed_at desc,recorded_at desc,evidence_id desc
    limit 1;

    if not p_force
       and v_auth_status='pass'
       and v_dependency_status='pass' then
      continue;
    end if;

    if coalesce(v_auth_status,'')='fail'
       or coalesce(v_dependency_status,'')='fail' then
      return jsonb_build_object(
        'defenceReattestationWork','shine-defence/reattestation-work-v1',
        'schemaVersion','1.0.0',
        'status','blocked',
        'reasonCode','existing-failed-evidence',
        'serviceId',v_row.service_id,
        'environment',v_row.environment,
        'artifactSha256',v_row.observed_artifact_sha256
      );
    end if;

    if v_row.source_ref is null then
      return jsonb_build_object(
        'defenceReattestationWork','shine-defence/reattestation-work-v1',
        'schemaVersion','1.0.0',
        'status','blocked',
        'reasonCode','source-binding-missing',
        'serviceId',v_row.service_id,
        'environment',v_row.environment,
        'artifactSha256',v_row.observed_artifact_sha256
      );
    end if;

    if v_row.source_ref !~ '^github://[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/commit/[a-fA-F0-9]{40}$' then
      return jsonb_build_object(
        'defenceReattestationWork','shine-defence/reattestation-work-v1',
        'schemaVersion','1.0.0',
        'status','blocked',
        'reasonCode','unsupported-source-binding',
        'serviceId',v_row.service_id,
        'environment',v_row.environment,
        'artifactSha256',v_row.observed_artifact_sha256,
        'sourceRef',v_row.source_ref
      );
    end if;

    v_source_repository := regexp_replace(
      v_row.source_ref,
      '^github://([^/]+/[^/]+)/commit/[a-fA-F0-9]{40}$',
      '\1'
    );
    v_source_commit := regexp_replace(
      v_row.source_ref,
      '^github://[^/]+/[^/]+/commit/([a-fA-F0-9]{40})$',
      '\1'
    );

    return jsonb_build_object(
      'defenceReattestationWork','shine-defence/reattestation-work-v1',
      'schemaVersion','1.0.0',
      'status','work',
      'serviceId',v_row.service_id,
      'displayName',v_row.display_name,
      'environment',v_row.environment,
      'artifactSha256',lower(v_row.observed_artifact_sha256),
      'runtimeVersion',v_row.runtime_version,
      'sourceRef',v_row.source_ref,
      'sourceRepository',v_source_repository,
      'sourceCommit',lower(v_source_commit),
      'requiredDomains',jsonb_build_array('auth','dependencies'),
      'currentAuthStatus',v_auth_status,
      'currentDependenciesStatus',v_dependency_status
    );
  end loop;

  return jsonb_build_object(
    'defenceReattestationWork','shine-defence/reattestation-work-v1',
    'schemaVersion','1.0.0',
    'status','no-work'
  );
end;
$$;

revoke all on function foundation.get_defence_reattestation_work_v1(boolean)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.get_defence_reattestation_work_v1(boolean)
  to shine_defence_runtime,service_role;


create or replace function foundation.record_defence_reattestation_v1(
  p_service_id text,
  p_environment text,
  p_artifact_sha256 text,
  p_source_commit text,
  p_auth_status text,
  p_dependencies_status text,
  p_inspector_version text,
  p_policy_commit text,
  p_report_sha256 text,
  p_observed_at timestamptz,
  p_valid_until timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_expected foundation.service_deployment_expectations%rowtype;
  v_observed foundation.service_deployment_observations%rowtype;
  v_truth jsonb;
  v_expected_source_ref text;
  v_state text;
  v_event_id uuid;
  v_auth_id uuid;
  v_dependency_id uuid;
begin
  if p_artifact_sha256 !~ '^[a-fA-F0-9]{64}$'
     or p_source_commit !~ '^[a-fA-F0-9]{40}$'
     or p_policy_commit !~ '^[a-fA-F0-9]{40}$'
     or p_report_sha256 !~ '^[a-fA-F0-9]{64}$'
     or p_auth_status not in ('pass','fail')
     or p_dependencies_status not in ('pass','fail')
     or p_valid_until<=p_observed_at
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-defence-reattestation' using errcode='22023';
  end if;

  select * into v_expected
  from foundation.current_service_deployment_expectations
  where service_id=p_service_id and environment=p_environment;

  select * into v_observed
  from foundation.current_service_deployment_observations
  where service_id=p_service_id and environment=p_environment;

  v_truth := foundation.get_service_deployment_truth_v1(p_service_id,p_environment);

  if v_expected.expectation_id is null
     or v_observed.observation_id is null
     or v_truth->>'truthState'<>'aligned'
     or lower(v_observed.artifact_sha256)<>lower(p_artifact_sha256)
     or v_expected.source_ref is null then
    raise exception 'reattestation-target-is-not-current-aligned-deployment' using errcode='22023';
  end if;

  v_expected_source_ref := regexp_replace(
    v_expected.source_ref,
    '/commit/[a-fA-F0-9]{40}$',
    '/commit/'||lower(p_source_commit)
  );

  if lower(v_expected.source_ref)<>lower(v_expected_source_ref) then
    raise exception 'reattestation-source-commit-mismatch' using errcode='22023';
  end if;

  v_state := case
    when p_auth_status='pass' and p_dependencies_status='pass' then 'pass'
    else 'fail'
  end;

  v_auth_id := foundation.record_defence_external_evidence_v1(
    'auth',
    p_service_id,
    p_auth_status,
    p_artifact_sha256,
    p_observed_at,
    p_valid_until,
    'source-inspection',
    p_evidence_ref||':auth',
    p_metadata || jsonb_build_object(
      'sourceCommit',lower(p_source_commit),
      'policyCommit',lower(p_policy_commit),
      'inspectorVersion',p_inspector_version,
      'reportSha256',lower(p_report_sha256)
    )
  );

  v_dependency_id := foundation.record_defence_external_evidence_v1(
    'dependencies',
    p_service_id,
    p_dependencies_status,
    p_artifact_sha256,
    p_observed_at,
    p_valid_until,
    'dependency-audit',
    p_evidence_ref||':dependencies',
    p_metadata || jsonb_build_object(
      'sourceCommit',lower(p_source_commit),
      'policyCommit',lower(p_policy_commit),
      'inspectorVersion',p_inspector_version,
      'reportSha256',lower(p_report_sha256)
    )
  );

  insert into foundation.defence_artifact_attestation_events(
    service_id,environment,artifact_sha256,source_ref,source_commit,state,
    auth_status,dependencies_status,inspector_version,policy_commit,report_sha256,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    p_service_id,p_environment,lower(p_artifact_sha256),v_expected.source_ref,
    lower(p_source_commit),v_state,p_auth_status,p_dependencies_status,
    p_inspector_version,lower(p_policy_commit),lower(p_report_sha256),
    p_observed_at,p_valid_until,p_evidence_ref,p_metadata
  )
  returning event_id into v_event_id;

  return jsonb_build_object(
    'defenceReattestation','shine-defence/reattestation-result-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'serviceId',p_service_id,
    'environment',p_environment,
    'artifactSha256',lower(p_artifact_sha256),
    'sourceCommit',lower(p_source_commit),
    'attestationEventId',v_event_id,
    'authEvidenceId',v_auth_id,
    'dependenciesEvidenceId',v_dependency_id,
    'validUntil',p_valid_until
  );
end;
$$;

revoke all on function foundation.record_defence_reattestation_v1(
  text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_reattestation_v1(
  text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,jsonb
) to service_role;
