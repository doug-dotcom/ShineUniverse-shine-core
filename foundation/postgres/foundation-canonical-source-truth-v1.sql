-- Foundation Layer 59: canonical source-of-truth closure.
-- A green build is not sufficient evidence that production truth converged.
-- This reader independently cross-checks the immutable binding, Universe projection,
-- release-ledger provenance and current deployment identity without treating runtime
-- health degradation as a source-of-truth mismatch.

create or replace function foundation.get_foundation_canonical_source_truth_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer59_truth$
declare
  v_projection jsonb;
  v_deployment jsonb;
  v_binding jsonb;
  v_registry jsonb;
  v_release jsonb;
  v_binding_layer integer;
  v_source_ref text;
  v_source_sha text;
  v_expected_release_ref text;
  v_expected_evidence_ref text;
  v_reasons text[] := '{}'::text[];
  v_state text := 'pass';
  v_checks jsonb;
  v_fingerprint_payload jsonb;
  v_fingerprint text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'canonical-source-truth-environment-invalid';
  end if;

  v_projection :=
    foundation.get_foundation_release_projection_health_v1(
      p_environment,p_as_of
    );
  v_deployment :=
    foundation.get_service_deployment_truth_v1(
      'foundation.gateway',p_environment
    );

  v_binding := v_projection->'binding';
  v_registry := v_projection->'registry';
  v_release := v_projection->'releaseLedger';

  begin
    v_binding_layer := nullif(v_binding->>'foundationLayer','')::integer;
  exception when others then
    v_binding_layer := null;
  end;

  v_source_ref := nullif(v_binding->>'sourceRef','');
  v_source_sha := lower(
    substring(coalesce(v_source_ref,'')
      from '/commit/([a-fA-F0-9]{40})$')
  );

  if v_binding_layer is not null and v_source_sha is not null then
    v_expected_release_ref :=
      format('foundation:layer-%s:%s',v_binding_layer,left(v_source_sha,8));
    v_expected_evidence_ref :=
      'https://github.com/doug-dotcom/ShineUniverse-shine-core/commit/'
      ||v_source_sha;
  end if;

  v_checks := jsonb_build_object(
    'projectionStructurallyClosed',
      coalesce(v_projection->>'state','unknown') in ('aligned','degraded')
      and coalesce(v_projection#>>'{checks,registryMatchesBinding}','false')='true'
      and coalesce(v_projection#>>'{checks,registryReleaseTargetExists}','false')='true'
      and coalesce(v_projection#>>'{checks,boundReleaseExists}','false')='true'
      and coalesce(v_projection#>>'{checks,boundReleaseLayerMatches}','false')='true'
      and coalesce(v_projection#>>'{checks,canonicalRepoConfirmed}','false')='true',
    'bindingSourceRefValid',v_source_sha is not null,
    'bindingReleaseRefMatchesSource',
      v_expected_release_ref is not null
      and v_binding->>'releaseRef' is not distinct from v_expected_release_ref,
    'registryLayerMatchesBinding',
      v_binding_layer is not null
      and nullif(v_registry->>'currentLayer','')::integer
          is not distinct from v_binding_layer,
    'registryReleaseRefMatchesBinding',
      v_registry->>'readinessReleaseRef'
        is not distinct from v_binding->>'releaseRef',
    'registryVerified',
      v_registry->>'currentLayerStatus'='verified'
      and v_registry->>'buildState'='deployed',
    'canonicalRepoConfirmed',
      v_registry->>'canonicalRepo'='doug-dotcom/ShineUniverse-shine-core'
      and v_registry->>'canonicalRepoStatus'='confirmed',
    'boundReleaseLedgerPresent',
      jsonb_typeof(v_release)='object'
      and nullif(v_release->>'releaseRef','') is not null,
    'boundReleaseLayerMatches',
      v_binding_layer is not null
      and v_release->>'sourceLayerRef'
          is not distinct from format('layer:%s',v_binding_layer),
    'boundReleaseSourceCommitMatches',
      v_source_sha is not null
      and lower(coalesce(v_release->>'sourceCommitRef',''))
          is not distinct from v_source_sha,
    'boundReleaseEvidenceMatches',
      v_expected_evidence_ref is not null
      and v_release->>'evidenceRef'
          is not distinct from v_expected_evidence_ref,
    'deploymentAligned',
      v_deployment->>'truthState'='aligned',
    'deploymentSourceMatchesBinding',
      v_source_ref is not null
      and v_deployment#>>'{expected,sourceRef}'
          is not distinct from v_source_ref,
    'deploymentRuntimeMatchesBinding',
      nullif(v_binding->>'runtimeVersion','') is not null
      and v_deployment#>>'{expected,version}'
          is not distinct from v_binding->>'runtimeVersion',
    'deploymentArtifactMatchesBinding',
      nullif(v_binding->>'artifactSha256','') is not null
      and lower(coalesce(v_deployment#>>'{expected,artifactSha256}',''))
          is not distinct from lower(v_binding->>'artifactSha256')
  );

  if jsonb_typeof(v_binding) is distinct from 'object' then
    v_reasons := array_append(v_reasons,'foundation-release-binding-missing');
  end if;

  if jsonb_typeof(v_registry) is distinct from 'object' then
    v_reasons := array_append(v_reasons,'foundation-registry-projection-missing');
  end if;

  if coalesce(v_checks->>'projectionStructurallyClosed','false')<>'true' then
    v_reasons := array_append(v_reasons,'release-projection-not-structurally-closed');
  end if;
  if coalesce(v_checks->>'bindingSourceRefValid','false')<>'true' then
    v_reasons := array_append(v_reasons,'binding-source-ref-invalid');
  end if;
  if coalesce(v_checks->>'bindingReleaseRefMatchesSource','false')<>'true' then
    v_reasons := array_append(v_reasons,'binding-release-ref-source-mismatch');
  end if;
  if coalesce(v_checks->>'registryLayerMatchesBinding','false')<>'true' then
    v_reasons := array_append(v_reasons,'registry-layer-mismatch');
  end if;
  if coalesce(v_checks->>'registryReleaseRefMatchesBinding','false')<>'true' then
    v_reasons := array_append(v_reasons,'registry-release-ref-mismatch');
  end if;
  if coalesce(v_checks->>'registryVerified','false')<>'true' then
    v_reasons := array_append(v_reasons,'registry-not-verified');
  end if;
  if coalesce(v_checks->>'canonicalRepoConfirmed','false')<>'true' then
    v_reasons := array_append(v_reasons,'registry-canonical-repo-invalid');
  end if;
  if coalesce(v_checks->>'boundReleaseLedgerPresent','false')<>'true' then
    v_reasons := array_append(v_reasons,'bound-release-ledger-missing');
  end if;
  if coalesce(v_checks->>'boundReleaseLayerMatches','false')<>'true' then
    v_reasons := array_append(v_reasons,'bound-release-layer-mismatch');
  end if;
  if coalesce(v_checks->>'boundReleaseSourceCommitMatches','false')<>'true' then
    v_reasons := array_append(v_reasons,'bound-release-source-commit-mismatch');
  end if;
  if coalesce(v_checks->>'boundReleaseEvidenceMatches','false')<>'true' then
    v_reasons := array_append(v_reasons,'bound-release-evidence-ref-mismatch');
  end if;
  if coalesce(v_checks->>'deploymentAligned','false')<>'true' then
    v_reasons := array_append(v_reasons,'deployment-truth-not-aligned');
  end if;
  if coalesce(v_checks->>'deploymentSourceMatchesBinding','false')<>'true' then
    v_reasons := array_append(v_reasons,'deployment-source-ref-mismatch');
  end if;
  if coalesce(v_checks->>'deploymentRuntimeMatchesBinding','false')<>'true' then
    v_reasons := array_append(v_reasons,'deployment-runtime-version-mismatch');
  end if;
  if coalesce(v_checks->>'deploymentArtifactMatchesBinding','false')<>'true' then
    v_reasons := array_append(v_reasons,'deployment-artifact-mismatch');
  end if;

  if cardinality(v_reasons)>0 then
    v_state := 'fail';
  end if;

  v_fingerprint_payload := jsonb_build_object(
    'state',v_state,
    'environment',p_environment,
    'reasonCodes',to_jsonb(v_reasons),
    'checks',v_checks,
    'binding',v_binding,
    'registry',v_registry,
    'releaseLedger',v_release,
    'deploymentExpected',v_deployment->'expected'
  );
  v_fingerprint := md5(v_fingerprint_payload::text);

  return jsonb_build_object(
    'foundationCanonicalSourceTruthResponse',
      'shine-foundation/canonical-source-truth-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'reasonCodes',to_jsonb(v_reasons),
    'evidenceFingerprint',v_fingerprint,
    'checks',v_checks,
    'binding',v_binding,
    'registry',v_registry,
    'releaseLedger',v_release,
    'deployment',jsonb_build_object(
      'truthState',v_deployment->>'truthState',
      'expected',v_deployment->'expected',
      'observed',v_deployment->'observed'
    ),
    'runtimeHealthAffectsSourceTruth',false
  );
end;
$layer59_truth$;

revoke all on function foundation.get_foundation_canonical_source_truth_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_foundation_canonical_source_truth_v1(
  text,timestamptz
) to foundation_runtime,service_role;


create or replace function foundation.assert_foundation_canonical_source_truth_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer59_assert$
declare
  v_truth jsonb;
begin
  v_truth :=
    foundation.get_foundation_canonical_source_truth_v1(
      p_environment,p_as_of
    );

  if v_truth->>'state'<>'pass' then
    raise exception using
      errcode='23514',
      message='foundation-canonical-source-truth-not-closed',
      detail=left(v_truth::text,4000);
  end if;

  return v_truth;
end;
$layer59_assert$;

revoke all on function foundation.assert_foundation_canonical_source_truth_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.assert_foundation_canonical_source_truth_v1(
  text,timestamptz
) to service_role;
