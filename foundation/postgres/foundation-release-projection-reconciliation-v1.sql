-- Foundation Layer 36: continuous registry/release/binding reconciliation.
-- Detect divergence between Universe registry projection, release ledger and the
-- immutable Foundation release identity. Record only meaningful evidence changes.

create table foundation.foundation_release_projection_observations (
  observation_sequence bigint generated always as identity primary key,
  observation_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  reconciliation_state text not null
    check (reconciliation_state in ('aligned','degraded','unknown','fail')),
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  reason_codes jsonb not null default '[]'::jsonb
    check (jsonb_typeof(reason_codes)='array'),
  snapshot jsonb not null
    check (jsonb_typeof(snapshot)='object'),
  observed_at timestamptz not null default now(),
  recorded_at timestamptz not null default now()
);

alter table foundation.foundation_release_projection_observations enable row level security;

create policy foundation_runtime_release_projection_observations_select
on foundation.foundation_release_projection_observations
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_release_projection_observations
  from public,anon,authenticated,foundation_gateway,service_role;
grant select on foundation.foundation_release_projection_observations
  to foundation_runtime,service_role;

create index foundation_release_projection_observations_current_idx
  on foundation.foundation_release_projection_observations(
    environment,observed_at desc,observation_sequence desc
  );

create trigger foundation_release_projection_observations_append_only
before update or delete on foundation.foundation_release_projection_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_foundation_release_projection_observation
with (security_invoker=true)
as
select distinct on (environment)
  observation_sequence,
  observation_id,
  environment,
  reconciliation_state,
  evidence_fingerprint,
  reason_codes,
  snapshot,
  observed_at,
  recorded_at
from foundation.foundation_release_projection_observations
order by environment,observed_at desc,observation_sequence desc;

revoke all on foundation.current_foundation_release_projection_observation
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_foundation_release_projection_observation
  to foundation_runtime,service_role;


create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer36_health$
declare
  v_registry_exists boolean := false;
  v_release_ledger_exists boolean := false;

  v_registry_layer integer;
  v_registry_layer_status text;
  v_registry_build_state text;
  v_registry_release_ref text;
  v_registry_canonical_repo text;
  v_registry_repo_status text;
  v_registry_last_verified_at timestamptz;

  v_binding_id uuid;
  v_binding_layer integer;
  v_binding_release_ref text;
  v_binding_source_ref text;
  v_binding_runtime_version text;
  v_binding_artifact_sha256 text;
  v_binding_bound_at timestamptz;

  v_registry_target_exists boolean := false;
  v_binding_release_exists boolean := false;

  v_release_layer_ref text;
  v_release_source_commit_ref text;
  v_release_evidence_ref text;
  v_release_opened_at timestamptz;

  v_binding_release_layer_ref text;
  v_binding_release_source_commit_ref text;
  v_binding_release_evidence_ref text;

  v_identity_health jsonb;
  v_identity_state text;

  v_state text := 'aligned';
  v_reasons text[] := '{}'::text[];
  v_fingerprint_payload jsonb;
  v_fingerprint text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'release-projection-environment-invalid';
  end if;

  v_registry_exists := to_regclass('universe.app_registry') is not null;
  v_release_ledger_exists := to_regclass('universe.readiness_releases') is not null;

  select
    binding_id,
    foundation_layer,
    release_ref,
    source_ref,
    runtime_version,
    artifact_sha256,
    bound_at
  into
    v_binding_id,
    v_binding_layer,
    v_binding_release_ref,
    v_binding_source_ref,
    v_binding_runtime_version,
    v_binding_artifact_sha256,
    v_binding_bound_at
  from foundation.current_foundation_release_identity
  where service_id='foundation.gateway'
    and environment=p_environment;

  if v_binding_id is not null then
    v_identity_health :=
      foundation.get_foundation_release_identity_health_v1(p_environment);
    v_identity_state := coalesce(v_identity_health->>'state','unknown');
  else
    v_identity_health := null;
    v_identity_state := 'unknown';
  end if;

  if v_registry_exists then
    select
      current_layer,
      current_layer_status,
      build_state,
      readiness_release_ref,
      canonical_repo,
      canonical_repo_status,
      last_verified_at
    into
      v_registry_layer,
      v_registry_layer_status,
      v_registry_build_state,
      v_registry_release_ref,
      v_registry_canonical_repo,
      v_registry_repo_status,
      v_registry_last_verified_at
    from universe.app_registry
    where app_key='foundation';
  end if;

  if v_release_ledger_exists and v_registry_release_ref is not null then
    select
      true,
      source_layer_ref,
      source_commit_ref,
      evidence_ref,
      opened_at
    into
      v_registry_target_exists,
      v_release_layer_ref,
      v_release_source_commit_ref,
      v_release_evidence_ref,
      v_release_opened_at
    from universe.readiness_releases
    where app_key='foundation'
      and release_ref=v_registry_release_ref;

    v_registry_target_exists := coalesce(v_registry_target_exists,false);
  end if;

  if v_release_ledger_exists and v_binding_release_ref is not null then
    select
      true,
      source_layer_ref,
      source_commit_ref,
      evidence_ref
    into
      v_binding_release_exists,
      v_binding_release_layer_ref,
      v_binding_release_source_commit_ref,
      v_binding_release_evidence_ref
    from universe.readiness_releases
    where app_key='foundation'
      and release_ref=v_binding_release_ref;

    v_binding_release_exists := coalesce(v_binding_release_exists,false);
  end if;

  if not v_registry_exists or not v_release_ledger_exists then
    v_state := 'unknown';
    v_reasons := array_append(v_reasons,'universe-release-projection-schema-missing');
  elsif v_binding_id is null then
    v_state := 'fail';
    v_reasons := array_append(v_reasons,'release-identity-binding-missing');
  elsif v_registry_layer is null then
    v_state := 'fail';
    v_reasons := array_append(v_reasons,'foundation-registry-row-missing');
  else
    if v_registry_release_ref is null then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'registry-release-ref-missing');
    end if;

    if v_registry_release_ref is distinct from v_binding_release_ref then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'registry-release-ref-mismatch');
    end if;

    if v_registry_layer is distinct from v_binding_layer then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'registry-layer-mismatch');
    end if;

    if v_registry_release_ref is not null and not v_registry_target_exists then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'registry-release-target-missing');
    end if;

    if not v_binding_release_exists then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'bound-release-ledger-missing');
    elsif v_binding_release_layer_ref is distinct from
          format('layer:%s',v_binding_layer) then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'bound-release-layer-mismatch');
    end if;

    if v_registry_target_exists
       and v_release_layer_ref is distinct from format('layer:%s',v_registry_layer) then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'registry-release-layer-mismatch');
    end if;

    if v_registry_target_exists
       and (
         nullif(v_release_source_commit_ref,'') is null
         or nullif(v_release_evidence_ref,'') is null
       ) then
      if v_state='aligned' then
        v_state := 'degraded';
      end if;
      v_reasons := array_append(v_reasons,'registry-release-evidence-incomplete');
    end if;

    if v_registry_canonical_repo is distinct from
       'doug-dotcom/ShineUniverse-shine-core'
       or v_registry_repo_status is distinct from 'confirmed' then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'registry-canonical-repo-invalid');
    end if;

    if v_registry_layer_status is distinct from 'verified'
       or v_registry_build_state is distinct from 'deployed' then
      if v_state='aligned' then
        v_state := 'degraded';
      end if;
      v_reasons := array_append(v_reasons,'registry-release-not-fully-verified');
    end if;

    if v_identity_state='fail' then
      v_state := 'fail';
      v_reasons := array_append(v_reasons,'release-identity-health-failed');
    elsif v_identity_state='unknown' then
      if v_state<>'fail' then
        v_state := 'unknown';
      end if;
      v_reasons := array_append(v_reasons,'release-identity-health-unknown');
    elsif v_identity_state='degraded' then
      if v_state='aligned' then
        v_state := 'degraded';
      end if;
      v_reasons := array_append(v_reasons,'release-identity-health-degraded');
    end if;
  end if;

  v_fingerprint_payload := jsonb_build_object(
    'state',v_state,
    'reasonCodes',to_jsonb(v_reasons),
    'environment',p_environment,
    'registryExists',v_registry_exists,
    'releaseLedgerExists',v_release_ledger_exists,
    'registryLayer',v_registry_layer,
    'registryLayerStatus',v_registry_layer_status,
    'registryBuildState',v_registry_build_state,
    'registryReleaseRef',v_registry_release_ref,
    'registryCanonicalRepo',v_registry_canonical_repo,
    'registryRepoStatus',v_registry_repo_status,
    'bindingId',v_binding_id,
    'bindingLayer',v_binding_layer,
    'bindingReleaseRef',v_binding_release_ref,
    'bindingSourceRef',v_binding_source_ref,
    'bindingRuntimeVersion',v_binding_runtime_version,
    'bindingArtifactSha256',v_binding_artifact_sha256,
    'registryTargetExists',v_registry_target_exists,
    'bindingReleaseExists',v_binding_release_exists,
    'registryReleaseLayerRef',v_release_layer_ref,
    'registryReleaseSourceCommitRef',v_release_source_commit_ref,
    'registryReleaseEvidenceRef',v_release_evidence_ref,
    'bindingReleaseLayerRef',v_binding_release_layer_ref,
    'bindingReleaseSourceCommitRef',v_binding_release_source_commit_ref,
    'bindingReleaseEvidenceRef',v_binding_release_evidence_ref,
    'releaseIdentityState',v_identity_state
  );

  v_fingerprint := md5(v_fingerprint_payload::text);

  return jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
    'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'reasonCodes',to_jsonb(v_reasons),
    'evidenceFingerprint',v_fingerprint,
    'registry',case
      when not v_registry_exists or v_registry_layer is null then null
      else jsonb_build_object(
        'appKey','foundation',
        'currentLayer',v_registry_layer,
        'currentLayerStatus',v_registry_layer_status,
        'buildState',v_registry_build_state,
        'readinessReleaseRef',v_registry_release_ref,
        'canonicalRepo',v_registry_canonical_repo,
        'canonicalRepoStatus',v_registry_repo_status,
        'lastVerifiedAt',v_registry_last_verified_at
      )
    end,
    'binding',case
      when v_binding_id is null then null
      else jsonb_build_object(
        'bindingId',v_binding_id,
        'foundationLayer',v_binding_layer,
        'releaseRef',v_binding_release_ref,
        'sourceRef',v_binding_source_ref,
        'runtimeVersion',v_binding_runtime_version,
        'artifactSha256',v_binding_artifact_sha256,
        'boundAt',v_binding_bound_at
      )
    end,
    'releaseLedger',case
      when not v_registry_target_exists then null
      else jsonb_build_object(
        'releaseRef',v_registry_release_ref,
        'sourceLayerRef',v_release_layer_ref,
        'sourceCommitRef',v_release_source_commit_ref,
        'evidenceRef',v_release_evidence_ref,
        'openedAt',v_release_opened_at
      )
    end,
    'releaseIdentityHealth',v_identity_health,
    'checks',jsonb_build_object(
      'registrySchemaPresent',v_registry_exists,
      'releaseLedgerSchemaPresent',v_release_ledger_exists,
      'registryMatchesBinding',
        v_registry_layer is not distinct from v_binding_layer
        and v_registry_release_ref is not distinct from v_binding_release_ref,
      'registryReleaseTargetExists',v_registry_target_exists,
      'boundReleaseExists',v_binding_release_exists,
      'boundReleaseLayerMatches',
        v_binding_release_layer_ref is not distinct from format('layer:%s',v_binding_layer),
      'canonicalRepoConfirmed',
        v_registry_canonical_repo is not distinct from
          'doug-dotcom/ShineUniverse-shine-core'
        and v_registry_repo_status is not distinct from 'confirmed'
    )
  );
end;
$layer36_health$;

revoke all on function foundation.get_foundation_release_projection_health_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_foundation_release_projection_health_v1(
  text,timestamptz
) to foundation_runtime,service_role;


create or replace function foundation.record_foundation_release_projection_observation_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer36_record$
declare
  v_snapshot jsonb;
  v_fingerprint text;
  v_state text;
  v_reasons jsonb;
  v_latest foundation.foundation_release_projection_observations%rowtype;
  v_observation_id uuid;
begin
  v_snapshot :=
    foundation.get_foundation_release_projection_health_v1(
      p_environment,p_as_of
    );

  v_fingerprint := v_snapshot->>'evidenceFingerprint';
  v_state := coalesce(v_snapshot->>'state','unknown');
  v_reasons := coalesce(v_snapshot->'reasonCodes','[]'::jsonb);

  select * into v_latest
  from foundation.current_foundation_release_projection_observation
  where environment=p_environment;

  if v_latest.observation_id is not null
     and v_latest.evidence_fingerprint=v_fingerprint then
    return jsonb_build_object(
      'foundationReleaseProjectionObservationResponse',
      'shine-foundation/release-projection-observation-response-v1',
      'schemaVersion','1.0.0',
      'status','unchanged',
      'observationId',v_latest.observation_id,
      'state',v_state,
      'evidenceFingerprint',v_fingerprint,
      'snapshot',v_snapshot
    );
  end if;

  insert into foundation.foundation_release_projection_observations(
    environment,reconciliation_state,evidence_fingerprint,
    reason_codes,snapshot,observed_at
  )
  values (
    p_environment,v_state,v_fingerprint,
    v_reasons,v_snapshot,p_as_of
  )
  returning observation_id into v_observation_id;

  return jsonb_build_object(
    'foundationReleaseProjectionObservationResponse',
    'shine-foundation/release-projection-observation-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded-new',
    'observationId',v_observation_id,
    'state',v_state,
    'evidenceFingerprint',v_fingerprint,
    'snapshot',v_snapshot
  );
end;
$layer36_record$;

revoke all on function foundation.record_foundation_release_projection_observation_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.record_foundation_release_projection_observation_v1(
  text,timestamptz
) to service_role;
