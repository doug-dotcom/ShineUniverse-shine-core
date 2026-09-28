-- Foundation Layer 35: immutable release identity binding.
-- Bind a verified Foundation layer to the exact deployed source, runtime, artefact,
-- deployment receipt and trusted publication attestation. Readiness is captured as
-- evidence at bind time but may change independently of immutable release identity.

create table foundation.foundation_release_identity_bindings (
  binding_sequence bigint generated always as identity primary key,
  binding_id uuid not null unique default gen_random_uuid(),
  release_ref text not null unique
    check (release_ref ~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  foundation_layer integer not null
    check (foundation_layer > 0),
  source_ref text not null
    check (source_ref ~ '^github://[^/]+/[^/]+/commit/[a-fA-F0-9]{40}$'),
  runtime_version text not null
    check (char_length(runtime_version) between 1 and 128),
  artifact_sha256 text not null
    check (artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  deployment_receipt_id uuid not null
    references foundation.service_deployment_receipts(receipt_id),
  publication_id uuid not null
    references foundation.service_deployment_receipt_publications(publication_id),
  publication_assurance text not null,
  readiness_state_at_bind text not null
    check (readiness_state_at_bind in ('ready','restricted','degraded')),
  readiness_fingerprint_at_bind text not null
    check (readiness_fingerprint_at_bind ~ '^[a-fA-F0-9]{32,128}$'),
  bound_by text not null
    check (bound_by ~ '^[a-z0-9][a-z0-9._:-]*$'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  bound_at timestamptz not null default now(),
  unique(
    service_id,environment,foundation_layer,source_ref,runtime_version,
    artifact_sha256,deployment_receipt_id,publication_id
  )
);

alter table foundation.foundation_release_identity_bindings enable row level security;

create policy foundation_runtime_release_identity_bindings_select
on foundation.foundation_release_identity_bindings
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_release_identity_bindings
  from public,anon,authenticated,foundation_gateway,service_role;
grant select on foundation.foundation_release_identity_bindings
  to foundation_runtime,service_role;

create index foundation_release_identity_bindings_current_idx
  on foundation.foundation_release_identity_bindings(
    service_id,environment,bound_at desc,binding_sequence desc
  );

create index foundation_release_identity_bindings_receipt_idx
  on foundation.foundation_release_identity_bindings(deployment_receipt_id);

create index foundation_release_identity_bindings_publication_idx
  on foundation.foundation_release_identity_bindings(publication_id);

create trigger foundation_release_identity_bindings_append_only
before update or delete on foundation.foundation_release_identity_bindings
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_foundation_release_identity
with (security_invoker=true)
as
select distinct on (service_id,environment)
  binding_sequence,
  binding_id,
  release_ref,
  service_id,
  environment,
  foundation_layer,
  source_ref,
  runtime_version,
  artifact_sha256,
  deployment_receipt_id,
  publication_id,
  publication_assurance,
  readiness_state_at_bind,
  readiness_fingerprint_at_bind,
  bound_by,
  metadata,
  bound_at
from foundation.foundation_release_identity_bindings
order by service_id,environment,bound_at desc,binding_sequence desc;

revoke all on foundation.current_foundation_release_identity
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_foundation_release_identity
  to foundation_runtime,service_role;


create or replace function foundation.get_foundation_release_identity_health_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $layer35_health$
declare
  v_binding foundation.foundation_release_identity_bindings%rowtype;
  v_deployment jsonb;
  v_publication jsonb;
  v_readiness jsonb;
  v_expected_source_ref text;
  v_expected_runtime_version text;
  v_expected_artifact_sha256 text;
  v_publication_receipt_id uuid;
  v_current_publication_id uuid;
  v_matches_deployment boolean := false;
  v_matches_publication boolean := false;
  v_readiness_changed boolean := false;
  v_state text := 'unknown';
  v_reason_codes text[] := '{}'::text[];
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'release-identity-environment-invalid';
  end if;

  select * into v_binding
  from foundation.current_foundation_release_identity
  where service_id='foundation.gateway'
    and environment=p_environment;

  if v_binding.binding_id is null then
    return jsonb_build_object(
      'foundationReleaseIdentityHealthResponse',
      'shine-foundation/release-identity-health-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'state','unknown',
      'reasonCodes',jsonb_build_array('release-identity-missing'),
      'binding',null
    );
  end if;

  v_deployment := foundation.get_service_deployment_truth_v1(
    'foundation.gateway',p_environment
  );
  v_publication := foundation.get_deployment_receipt_publication_health_v1(
    'foundation.gateway',p_environment,86400
  );
  v_readiness := foundation.evaluate_foundation_readiness_v1(
    p_environment,now()
  );

  v_expected_source_ref := v_deployment#>>'{expected,sourceRef}';
  v_expected_runtime_version := v_deployment#>>'{expected,version}';
  v_expected_artifact_sha256 := v_deployment#>>'{expected,artifactSha256}';

  begin
    v_publication_receipt_id := nullif(v_publication->>'receiptId','')::uuid;
  exception when invalid_text_representation then
    v_publication_receipt_id := null;
  end;

  begin
    v_current_publication_id :=
      nullif(v_publication#>>'{publication,publicationId}','')::uuid;
  exception when invalid_text_representation then
    v_current_publication_id := null;
  end;

  v_matches_deployment :=
    coalesce(v_deployment->>'truthState','unknown')='aligned'
    and v_binding.source_ref is not distinct from v_expected_source_ref
    and v_binding.runtime_version is not distinct from v_expected_runtime_version
    and lower(v_binding.artifact_sha256) =
        lower(coalesce(v_expected_artifact_sha256,''));

  v_matches_publication :=
    coalesce(v_publication->>'state','unknown') in ('pass','degraded')
    and v_binding.deployment_receipt_id is not distinct from v_publication_receipt_id
    and v_binding.publication_id is not distinct from v_current_publication_id
    and v_binding.publication_assurance is not distinct from
        coalesce(v_publication->>'assurance','none')
    and v_binding.source_ref is not distinct from v_publication->>'sourceRef'
    and v_binding.runtime_version is not distinct from v_publication->>'runtimeVersion'
    and lower(v_binding.artifact_sha256) =
        lower(coalesce(v_publication->>'artifactSha256',''));

  v_readiness_changed :=
    v_binding.readiness_fingerprint_at_bind is distinct from
      coalesce(v_readiness->>'evidenceFingerprint','');

  if coalesce(v_deployment->>'truthState','unknown')='drift' then
    v_state := 'fail';
    v_reason_codes := array_append(v_reason_codes,'deployment-drift');
  elsif coalesce(v_deployment->>'truthState','unknown')<>'aligned' then
    v_state := 'unknown';
    v_reason_codes := array_append(v_reason_codes,'deployment-truth-unknown');
  elsif not v_matches_deployment then
    v_state := 'fail';
    v_reason_codes := array_append(v_reason_codes,'release-identity-deployment-mismatch');
  elsif coalesce(v_publication->>'state','unknown')='fail' then
    v_state := 'fail';
    v_reason_codes := array_append(v_reason_codes,'publication-attestation-failed');
  elsif coalesce(v_publication->>'state','unknown')='unknown' then
    v_state := 'unknown';
    v_reason_codes := array_append(v_reason_codes,'publication-attestation-unknown');
  elsif not v_matches_publication then
    v_state := 'fail';
    v_reason_codes := array_append(v_reason_codes,'release-identity-publication-mismatch');
  elsif coalesce(v_publication->>'state','unknown')='degraded' then
    v_state := 'degraded';
    v_reason_codes := array_append(v_reason_codes,'publication-attestation-degraded');
  elsif coalesce(v_publication->>'assurance','none')<>'github-oidc' then
    v_state := 'degraded';
    v_reason_codes := array_append(v_reason_codes,'publication-assurance-not-github-oidc');
  else
    v_state := 'pass';
  end if;

  if v_readiness_changed then
    v_reason_codes := array_append(v_reason_codes,'readiness-changed-since-bind');
  end if;

  return jsonb_build_object(
    'foundationReleaseIdentityHealthResponse',
    'shine-foundation/release-identity-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'state',v_state,
    'reasonCodes',to_jsonb(v_reason_codes),
    'matchesCurrentDeployment',v_matches_deployment,
    'matchesCurrentPublication',v_matches_publication,
    'readinessChangedSinceBinding',v_readiness_changed,
    'binding',jsonb_build_object(
      'bindingId',v_binding.binding_id,
      'releaseRef',v_binding.release_ref,
      'foundationLayer',v_binding.foundation_layer,
      'sourceRef',v_binding.source_ref,
      'runtimeVersion',v_binding.runtime_version,
      'artifactSha256',v_binding.artifact_sha256,
      'deploymentReceiptId',v_binding.deployment_receipt_id,
      'publicationId',v_binding.publication_id,
      'publicationAssurance',v_binding.publication_assurance,
      'readinessStateAtBind',v_binding.readiness_state_at_bind,
      'readinessFingerprintAtBind',v_binding.readiness_fingerprint_at_bind,
      'boundBy',v_binding.bound_by,
      'boundAt',v_binding.bound_at
    ),
    'current',jsonb_build_object(
      'deploymentTruthState',v_deployment->>'truthState',
      'sourceRef',v_expected_source_ref,
      'runtimeVersion',v_expected_runtime_version,
      'artifactSha256',v_expected_artifact_sha256,
      'publicationState',v_publication->>'state',
      'publicationAssurance',v_publication->>'assurance',
      'deploymentReceiptId',v_publication->>'receiptId',
      'publicationId',v_publication#>>'{publication,publicationId}',
      'readinessState',v_readiness->>'readinessState',
      'readinessFingerprint',v_readiness->>'evidenceFingerprint'
    )
  );
end;
$layer35_health$;

revoke all on function foundation.get_foundation_release_identity_health_v1(text)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_foundation_release_identity_health_v1(text)
  to foundation_runtime,service_role;


create or replace function foundation.bind_foundation_release_identity_v1(
  p_foundation_layer integer,
  p_bound_by text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer35_bind$
declare
  v_deployment jsonb;
  v_publication jsonb;
  v_readiness jsonb;
  v_source_ref text;
  v_source_sha text;
  v_runtime_version text;
  v_artifact_sha256 text;
  v_receipt_id uuid;
  v_publication_id uuid;
  v_release_ref text;
  v_readiness_state text;
  v_readiness_fingerprint text;
  v_existing foundation.foundation_release_identity_bindings%rowtype;
  v_binding foundation.foundation_release_identity_bindings%rowtype;
  v_status text := 'bound-new';
begin
  if p_foundation_layer is null
     or p_foundation_layer<=0
     or p_foundation_layer>1000000 then
    raise exception 'release-identity-layer-invalid';
  end if;

  if p_bound_by is null
     or p_bound_by !~ '^[a-z0-9][a-z0-9._:-]*$'
     or char_length(p_bound_by)>128 then
    raise exception 'release-identity-binder-invalid';
  end if;

  if p_metadata is null
     or jsonb_typeof(p_metadata)<>'object'
     or pg_column_size(p_metadata)>16384 then
    raise exception 'release-identity-metadata-invalid';
  end if;

  v_deployment := foundation.get_service_deployment_truth_v1(
    'foundation.gateway','production'
  );
  v_publication := foundation.get_deployment_receipt_publication_health_v1(
    'foundation.gateway','production',86400
  );
  v_readiness := foundation.evaluate_foundation_readiness_v1(
    'production',now()
  );

  if coalesce(v_deployment->>'truthState','unknown')<>'aligned' then
    raise exception 'release-identity-deployment-not-aligned';
  end if;

  if coalesce(v_publication->>'state','unknown')<>'pass'
     or coalesce(v_publication->>'assurance','none')<>'github-oidc' then
    raise exception 'release-identity-publication-not-trusted';
  end if;

  v_readiness_state := coalesce(v_readiness->>'readinessState','unknown');
  if v_readiness_state not in ('ready','restricted','degraded') then
    raise exception 'release-identity-readiness-not-bindable';
  end if;

  v_source_ref := v_deployment#>>'{expected,sourceRef}';
  v_runtime_version := v_deployment#>>'{expected,version}';
  v_artifact_sha256 := lower(v_deployment#>>'{expected,artifactSha256}');
  v_source_sha := lower(substring(
    v_source_ref from '/commit/([a-fA-F0-9]{40})$'
  ));
  v_readiness_fingerprint := lower(v_readiness->>'evidenceFingerprint');

  begin
    v_receipt_id := nullif(v_publication->>'receiptId','')::uuid;
    v_publication_id :=
      nullif(v_publication#>>'{publication,publicationId}','')::uuid;
  exception when invalid_text_representation then
    raise exception 'release-identity-publication-identifiers-invalid';
  end;

  if v_source_sha is null
     or v_runtime_version is null
     or v_artifact_sha256 !~ '^[a-f0-9]{64}$'
     or v_receipt_id is null
     or v_publication_id is null
     or v_readiness_fingerprint !~ '^[a-f0-9]{32,128}$' then
    raise exception 'release-identity-current-evidence-incomplete';
  end if;

  if v_publication->>'sourceRef' is distinct from v_source_ref
     or v_publication->>'runtimeVersion' is distinct from v_runtime_version
     or lower(coalesce(v_publication->>'artifactSha256',''))<>v_artifact_sha256 then
    raise exception 'release-identity-publication-deployment-mismatch';
  end if;

  v_release_ref := format(
    'foundation:layer-%s:%s',
    p_foundation_layer,
    left(v_source_sha,8)
  );

  select * into v_existing
  from foundation.foundation_release_identity_bindings
  where release_ref=v_release_ref;

  if v_existing.binding_id is not null then
    if v_existing.foundation_layer is distinct from p_foundation_layer
       or v_existing.source_ref is distinct from v_source_ref
       or v_existing.runtime_version is distinct from v_runtime_version
       or lower(v_existing.artifact_sha256)<>v_artifact_sha256
       or v_existing.deployment_receipt_id is distinct from v_receipt_id
       or v_existing.publication_id is distinct from v_publication_id
       or v_existing.publication_assurance is distinct from
          (v_publication->>'assurance') then
      raise exception 'release-identity-conflict';
    end if;

    v_binding := v_existing;
    v_status := 'replayed-existing';
  else
    insert into foundation.foundation_release_identity_bindings(
      release_ref,service_id,environment,foundation_layer,source_ref,
      runtime_version,artifact_sha256,deployment_receipt_id,publication_id,
      publication_assurance,readiness_state_at_bind,
      readiness_fingerprint_at_bind,bound_by,metadata
    )
    values (
      v_release_ref,'foundation.gateway','production',p_foundation_layer,
      v_source_ref,v_runtime_version,v_artifact_sha256,v_receipt_id,
      v_publication_id,v_publication->>'assurance',v_readiness_state,
      v_readiness_fingerprint,p_bound_by,p_metadata
    )
    returning * into v_binding;
  end if;

  return jsonb_build_object(
    'foundationReleaseIdentityBindingResponse',
    'shine-foundation/release-identity-binding-response-v1',
    'schemaVersion','1.0.0',
    'status',v_status,
    'bindingId',v_binding.binding_id,
    'releaseRef',v_binding.release_ref,
    'foundationLayer',v_binding.foundation_layer,
    'sourceRef',v_binding.source_ref,
    'runtimeVersion',v_binding.runtime_version,
    'artifactSha256',v_binding.artifact_sha256,
    'deploymentReceiptId',v_binding.deployment_receipt_id,
    'publicationId',v_binding.publication_id,
    'publicationAssurance',v_binding.publication_assurance,
    'readinessStateAtBind',v_binding.readiness_state_at_bind,
    'readinessFingerprintAtBind',v_binding.readiness_fingerprint_at_bind,
    'health',foundation.get_foundation_release_identity_health_v1('production')
  );
end;
$layer35_bind$;

revoke all on function foundation.bind_foundation_release_identity_v1(
  integer,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.bind_foundation_release_identity_v1(
  integer,text,jsonb
) to service_role;
