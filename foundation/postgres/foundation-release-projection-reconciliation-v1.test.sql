begin;

-- CI-only Universe projection shell. Production uses the real Universe tables.
create schema if not exists universe;

create table if not exists universe.app_registry (
  app_key text primary key,
  display_name text,
  category text,
  lifecycle text,
  canonical_repo text,
  canonical_repo_status text,
  supabase_project_ref text,
  supabase_project_name text,
  layer_scheme text,
  current_layer integer,
  current_layer_status text,
  build_state text,
  production_service text,
  source_of_truth text,
  evidence_note text,
  last_verified_at timestamptz,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  readiness_release_ref text
);

create table if not exists universe.readiness_releases (
  app_key text not null,
  release_ref text not null,
  release_label text not null,
  source_layer_ref text,
  source_commit_ref text,
  opened_at timestamptz not null,
  evidence_ref text not null,
  evidence_note text,
  created_at timestamptz not null default now(),
  primary key(app_key,release_ref)
);

-- Deterministic Layer-36 Foundation runtime identity fixture.
insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer36-e',
  repeat('e',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  now()+interval '1 second',
  'test:layer36:deployment-expectation:e',
  'Layer 36 release projection fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer36-e',
  repeat('e',64),
  'active','healthy',
  now()+interval '1 second',
  'manual-verified',
  'test:layer36:deployment-observation:e',
  'Layer 36 release projection fixture.',
  '{"test":true}'::jsonb
);

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer36-e',
  now()-interval '5 minutes',
  now()+interval '2 seconds',
  100,0,0,20,25,
  0,'manual-verified',
  'test:layer36:health:e',
  'Healthy Layer 36 fixture.',
  '{"test":true}'::jsonb,
  now()+interval '2 seconds'
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '36000000-0000-4000-8000-000000000001'::uuid,
  '1.0.0','production','pass',
  now()+interval '3 seconds',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer36:defence:pass',
  now()+interval '3 seconds'
);

insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
)
values (
  '36000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer36-e',
  repeat('e',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  'test:layer36:provider:e',
  now()+interval '2 seconds',
  'layer36-test',
  '{"test":true}'::jsonb,
  now()+interval '2 seconds'
);

insert into foundation.service_deployment_receipt_publications(
  publication_id,publication_key,receipt_id,service_id,environment,provider,
  runtime_version,artifact_sha256,source_ref,provider_evidence_ref,
  publication_outcome,submitted_by,transport,transport_run_id,
  transport_run_attempt,transport_event,transport_repository,transport_ref,
  transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
)
values (
  '36000000-0000-4000-8000-000000000101'::uuid,
  'github-oidc:360000:1:36000000-0000-4000-8000-000000000100',
  '36000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer36-e',
  repeat('e',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  'test:layer36:provider:e',
  'accepted-new',
  'github-actions-oidc',
  'github-oidc',
  '360000','1','push',
  'doug-dotcom/ShineUniverse-shine-core',
  'refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('6',40),
  false,
  '{"test":true}'::jsonb,
  now()+interval '4 seconds'
);

do $layer36_audit$
declare
  v_policy jsonb;
  v_audit uuid := '36000000-0000-4000-8000-000000000200'::uuid;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/consent','production',now()+interval '5 seconds'
  ) into v_policy;

  if v_policy->>'policyState' <> 'admit' then
    raise exception 'Layer 36 fixture policy should admit: %',v_policy;
  end if;

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'policy','POST','/v1/grants/consent','production',
    v_policy,null,null,null,now()+interval '5 seconds'
  );

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'outcome','POST','/v1/grants/consent','production',
    null,401,'unauthenticated',null,now()+interval '6 seconds'
  );
end;
$layer36_audit$;

do $layer36_binding$
declare
  v jsonb;
begin
  select foundation.bind_foundation_release_identity_v1(
    36,'layer36-test','{"test":true}'::jsonb
  ) into v;

  if v->>'releaseRef' <> 'foundation:layer-36:eeeeeeee'
     or v->>'status' <> 'bound-new' then
    raise exception 'Layer 36 fixture binding failed: %',v;
  end if;
end;
$layer36_binding$;

insert into universe.readiness_releases(
  app_key,release_ref,release_label,source_layer_ref,source_commit_ref,
  opened_at,evidence_ref,evidence_note
)
values (
  'foundation',
  'foundation:layer-36:eeeeeeee',
  'Foundation Layer 36 release projection reconciliation',
  'layer:36',
  repeat('a',40),
  now()+interval '7 seconds',
  'https://example.invalid/foundation-layer-36',
  'Layer 36 CI projection fixture.'
)
on conflict (app_key,release_ref) do update
set release_label=excluded.release_label,
    source_layer_ref=excluded.source_layer_ref,
    source_commit_ref=excluded.source_commit_ref,
    opened_at=excluded.opened_at,
    evidence_ref=excluded.evidence_ref,
    evidence_note=excluded.evidence_note;

insert into universe.app_registry(
  app_key,display_name,category,lifecycle,canonical_repo,canonical_repo_status,
  supabase_project_ref,supabase_project_name,layer_scheme,current_layer,
  current_layer_status,build_state,production_service,source_of_truth,
  evidence_note,last_verified_at,created_at,updated_at,readiness_release_ref
)
values (
  'foundation','Shine Foundation','control_plane','active',
  'doug-dotcom/ShineUniverse-shine-core','confirmed',
  'sjpxqeyewahraxvidvcc','Shine Foundation','monotonic Foundation layers',
  36,'verified','deployed','foundation.gateway',
  'CI fixture','Layer 36 CI projection fixture.',
  now()+interval '7 seconds',now(),now()+interval '7 seconds',
  'foundation:layer-36:eeeeeeee'
)
on conflict (app_key) do update
set canonical_repo=excluded.canonical_repo,
    canonical_repo_status=excluded.canonical_repo_status,
    current_layer=excluded.current_layer,
    current_layer_status=excluded.current_layer_status,
    build_state=excluded.build_state,
    readiness_release_ref=excluded.readiness_release_ref,
    last_verified_at=excluded.last_verified_at,
    updated_at=excluded.updated_at;

do $layer36_aligned$
declare
  v jsonb;
begin
  select foundation.get_foundation_release_projection_health_v1(
    'production',now()+interval '8 seconds'
  ) into v;

  if v->>'state' <> 'aligned'
     or v#>>'{checks,registryMatchesBinding}' <> 'true'
     or v#>>'{checks,registryReleaseTargetExists}' <> 'true'
     or v#>>'{checks,boundReleaseExists}' <> 'true'
     or v#>>'{checks,boundReleaseLayerMatches}' <> 'true' then
    raise exception 'Layer 36 aligned projection should pass: %',v;
  end if;
end;
$layer36_aligned$;

do $layer36_dedupe$
declare
  v_first jsonb;
  v_second jsonb;
  v_count integer;
begin
  select foundation.record_foundation_release_projection_observation_v1(
    'production',now()+interval '9 seconds'
  ) into v_first;

  select foundation.record_foundation_release_projection_observation_v1(
    'production',now()+interval '10 seconds'
  ) into v_second;

  select count(*) into v_count
  from foundation.foundation_release_projection_observations
  where environment='production';

  if v_first->>'status' <> 'recorded-new'
     or v_second->>'status' <> 'unchanged'
     or v_count <> 1 then
    raise exception 'Layer 36 observer should deduplicate unchanged evidence: first %, second %, count %',
      v_first,v_second,v_count;
  end if;
end;
$layer36_dedupe$;

insert into universe.readiness_releases(
  app_key,release_ref,release_label,source_layer_ref,source_commit_ref,
  opened_at,evidence_ref,evidence_note
)
values (
  'foundation',
  'foundation:layer-35:ffffffff',
  'Intentional stale projection fixture',
  'layer:35',
  repeat('f',40),
  now()+interval '11 seconds',
  'https://example.invalid/stale-foundation-release',
  'Intentional Layer 36 stale registry fixture.'
)
on conflict (app_key,release_ref) do nothing;

update universe.app_registry
set current_layer=35,
    readiness_release_ref='foundation:layer-35:ffffffff',
    updated_at=now()+interval '11 seconds'
where app_key='foundation';

do $layer36_stale_registry$
declare
  v jsonb;
  v_record jsonb;
begin
  select foundation.get_foundation_release_projection_health_v1(
    'production',now()+interval '12 seconds'
  ) into v;

  if v->>'state' <> 'fail'
     or not (v->'reasonCodes' ? 'registry-release-ref-mismatch')
     or not (v->'reasonCodes' ? 'registry-layer-mismatch') then
    raise exception 'Layer 36 must fail closed on stale registry projection: %',v;
  end if;

  select foundation.record_foundation_release_projection_observation_v1(
    'production',now()+interval '12 seconds'
  ) into v_record;

  if v_record->>'status' <> 'recorded-new'
     or v_record->>'state' <> 'fail' then
    raise exception 'Layer 36 observer must record stale-registry transition: %',v_record;
  end if;
end;
$layer36_stale_registry$;

update universe.app_registry
set current_layer=36,
    readiness_release_ref='foundation:layer-36:eeeeeeee',
    updated_at=now()+interval '13 seconds'
where app_key='foundation';

delete from universe.readiness_releases
where app_key='foundation'
  and release_ref='foundation:layer-36:eeeeeeee';

do $layer36_missing_projection$
declare
  v jsonb;
begin
  select foundation.get_foundation_release_projection_health_v1(
    'production',now()+interval '14 seconds'
  ) into v;

  if v->>'state' <> 'fail'
     or not (v->'reasonCodes' ? 'registry-release-target-missing')
     or not (v->'reasonCodes' ? 'bound-release-ledger-missing') then
    raise exception 'Layer 36 must catch missing release projection: %',v;
  end if;
end;
$layer36_missing_projection$;

do $layer36_security$
begin
  if not has_function_privilege(
    'foundation_runtime',
    'foundation.get_foundation_release_projection_health_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must read release projection health';
  end if;

  if has_function_privilege(
    'foundation_runtime',
    'foundation.record_foundation_release_projection_observation_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must not write reconciliation observations';
  end if;

  if not has_function_privilege(
    'service_role',
    'foundation.record_foundation_release_projection_observation_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role must run reconciliation observer';
  end if;

  if has_table_privilege(
    'service_role',
    'foundation.foundation_release_projection_observations',
    'INSERT'
  ) then
    raise exception 'service_role must not bypass reconciliation recorder';
  end if;
end;
$layer36_security$;

rollback;
