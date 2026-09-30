begin;

-- Layer 59 tests the new closure invariant independently of mutable production
-- fixtures by replacing the two read-only evidence readers inside this rollback.

create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer59_projection_good$
  select jsonb_build_object(
    'foundationReleaseProjectionHealthResponse','shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','degraded',
    'reasonCodes',jsonb_build_array('release-identity-health-degraded'),
    'evidenceFingerprint',repeat('5',32),
    'checks',jsonb_build_object(
      'registryMatchesBinding',true,
      'registryReleaseTargetExists',true,
      'boundReleaseExists',true,
      'boundReleaseLayerMatches',true,
      'canonicalRepoConfirmed',true
    ),
    'binding',jsonb_build_object(
      'bindingId','59000000-0000-4000-8000-000000000001',
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      'runtimeVersion','90',
      'artifactSha256',repeat('a',64)
    ),
    'registry',jsonb_build_object(
      'appKey','foundation',
      'currentLayer',58,
      'currentLayerStatus','verified',
      'buildState','deployed',
      'readinessReleaseRef','foundation:layer-58:eeeeeeee',
      'canonicalRepo','doug-dotcom/ShineUniverse-shine-core',
      'canonicalRepoStatus','confirmed'
    ),
    'releaseLedger',jsonb_build_object(
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceLayerRef','layer:58',
      'sourceCommitRef',repeat('e',40),
      'evidenceRef','https://github.com/doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40)
    )
  );
$layer59_projection_good$;

create or replace function foundation.get_service_deployment_truth_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer59_deployment_good$
  select jsonb_build_object(
    'deploymentTruthResponse','shine-foundation/deployment-truth-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',p_service_id,
    'environment',p_environment,
    'truthState','aligned',
    'expected',jsonb_build_object(
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'version','90',
      'artifactSha256',repeat('a',64)
    ),
    'observed',jsonb_build_object(
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'version','90',
      'artifactSha256',repeat('a',64)
    )
  );
$layer59_deployment_good$;

do $layer59_good$
declare v jsonb;
begin
  v:=foundation.get_foundation_canonical_source_truth_v1('production',now());

  if v->>'state'<>'pass'
     or v#>>'{checks,projectionStructurallyClosed}'<>'true'
     or v#>>'{checks,boundReleaseSourceCommitMatches}'<>'true'
     or v#>>'{checks,boundReleaseEvidenceMatches}'<>'true'
     or v#>>'{checks,deploymentSourceMatchesBinding}'<>'true'
     or v->>'runtimeHealthAffectsSourceTruth'<>'false' then
    raise exception 'Layer 59 canonical source truth should pass on structurally closed degraded runtime evidence: %',v;
  end if;
end;
$layer59_good$;

-- A ledger row at the correct layer is not enough: its commit and evidence URL
-- must match the immutable binding exactly.
create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer59_projection_bad_provenance$
  select jsonb_build_object(
    'foundationReleaseProjectionHealthResponse','shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','aligned',
    'reasonCodes','[]'::jsonb,
    'evidenceFingerprint',repeat('6',32),
    'checks',jsonb_build_object(
      'registryMatchesBinding',true,
      'registryReleaseTargetExists',true,
      'boundReleaseExists',true,
      'boundReleaseLayerMatches',true,
      'canonicalRepoConfirmed',true
    ),
    'binding',jsonb_build_object(
      'bindingId','59000000-0000-4000-8000-000000000001',
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('a',64)
    ),
    'registry',jsonb_build_object(
      'appKey','foundation',
      'currentLayer',58,
      'currentLayerStatus','verified',
      'buildState','deployed',
      'readinessReleaseRef','foundation:layer-58:eeeeeeee',
      'canonicalRepo','doug-dotcom/ShineUniverse-shine-core',
      'canonicalRepoStatus','confirmed'
    ),
    'releaseLedger',jsonb_build_object(
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceLayerRef','layer:58',
      'sourceCommitRef',repeat('f',40),
      'evidenceRef','https://github.com/doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('f',40)
    )
  );
$layer59_projection_bad_provenance$;

do $layer59_bad_provenance$
declare v jsonb;
begin
  v:=foundation.get_foundation_canonical_source_truth_v1('production',now());

  if v->>'state'<>'fail'
     or not (v->'reasonCodes' ? 'bound-release-source-commit-mismatch')
     or not (v->'reasonCodes' ? 'bound-release-evidence-ref-mismatch') then
    raise exception 'Layer 59 must fail closed on release-ledger provenance drift: %',v;
  end if;
end;
$layer59_bad_provenance$;

-- Restore structurally closed projection and make only deployment provenance stale.
create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer59_projection_good_again$
  select jsonb_build_object(
    'state','degraded',
    'reasonCodes',jsonb_build_array('release-identity-health-degraded'),
    'checks',jsonb_build_object(
      'registryMatchesBinding',true,
      'registryReleaseTargetExists',true,
      'boundReleaseExists',true,
      'boundReleaseLayerMatches',true,
      'canonicalRepoConfirmed',true
    ),
    'binding',jsonb_build_object(
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('a',64)
    ),
    'registry',jsonb_build_object(
      'currentLayer',58,
      'currentLayerStatus','verified',
      'buildState','deployed',
      'readinessReleaseRef','foundation:layer-58:eeeeeeee',
      'canonicalRepo','doug-dotcom/ShineUniverse-shine-core',
      'canonicalRepoStatus','confirmed'
    ),
    'releaseLedger',jsonb_build_object(
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceLayerRef','layer:58',
      'sourceCommitRef',repeat('e',40),
      'evidenceRef','https://github.com/doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40)
    )
  );
$layer59_projection_good_again$;

create or replace function foundation.get_service_deployment_truth_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer59_deployment_bad$
  select jsonb_build_object(
    'truthState','aligned',
    'expected',jsonb_build_object(
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('f',40),
      'version','90',
      'artifactSha256',repeat('a',64)
    ),
    'observed',jsonb_build_object(
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('f',40),
      'version','90',
      'artifactSha256',repeat('a',64)
    )
  );
$layer59_deployment_bad$;

do $layer59_bad_deployment$
declare v jsonb;
begin
  v:=foundation.get_foundation_canonical_source_truth_v1('production',now());

  if v->>'state'<>'fail'
     or not (v->'reasonCodes' ? 'deployment-source-ref-mismatch') then
    raise exception 'Layer 59 must fail closed when deployment source diverges from immutable binding: %',v;
  end if;
end;
$layer59_bad_deployment$;

-- Restore the good deployment stub and prove the assertion boundary.
create or replace function foundation.get_service_deployment_truth_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer59_deployment_good_again$
  select jsonb_build_object(
    'truthState','aligned',
    'expected',jsonb_build_object(
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'version','90',
      'artifactSha256',repeat('a',64)
    ),
    'observed',jsonb_build_object(
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'version','90',
      'artifactSha256',repeat('a',64)
    )
  );
$layer59_deployment_good_again$;

set local role service_role;
select foundation.assert_foundation_canonical_source_truth_v1('production',now());
reset role;

do $layer59_privileges$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_foundation_canonical_source_truth_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_canonical_source_truth_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_canonical_source_truth_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.assert_foundation_canonical_source_truth_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.assert_foundation_canonical_source_truth_v1(text,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 59 function privilege boundary is incorrect';
  end if;
end;
$layer59_privileges$;

rollback;
