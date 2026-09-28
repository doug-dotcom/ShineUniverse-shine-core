-- Foundation Layer 32: register the GitHub-OIDC deployment receipt ingest runtime.

insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,
  required_for_core,lifecycle,metadata
)
values (
  'foundation.deployment-receipt-ingest',
  'Foundation Deployment Receipt Ingest',
  'shine-core',
  'supabase-edge-function',
  'shine-foundation/deployment-receipt-publisher-v1',
  false,
  'active',
  jsonb_build_object(
    'projectRef','sjpxqeyewahraxvidvcc',
    'functionSlug','foundation-deployment-receipt-ingest',
    'verifyJwt',false,
    'authentication','github-oidc',
    'managementPlane',true
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
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
select
  'foundation.deployment-receipt-ingest',
  'production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-deployment-receipt-ingest',
  '1',
  'ba07c8dbf0f2334ae719f4e8323e223f8ab539705bcd4b4ca51dd7e40baaa596',
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/002ac12476d133afaa3ac82bf6691ffa3fae53bc',
  now(),
  'foundation:source-binding:deployment-receipt-ingest:v1:002ac12476d133afaa3ac82bf6691ffa3fae53bc',
  'Layer 32 exact-source binding for GitHub-OIDC deployment receipt ingest v1.'
where not exists (
  select 1
  from foundation.service_deployment_expectations
  where service_id='foundation.deployment-receipt-ingest'
    and environment='production'
    and expected_version='1'
    and expected_artifact_sha256='ba07c8dbf0f2334ae719f4e8323e223f8ab539705bcd4b4ca51dd7e40baaa596'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
select
  'foundation.deployment-receipt-ingest',
  'production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-deployment-receipt-ingest',
  '1',
  'ba07c8dbf0f2334ae719f4e8323e223f8ab539705bcd4b4ca51dd7e40baaa596',
  'active',
  'unknown',
  now(),
  'supabase-api',
  'supabase:edge-function:foundation-deployment-receipt-ingest:v1',
  'Supabase reports OIDC deployment receipt ingest v1 ACTIVE; live OIDC workflow returned HTTP 200 and anonymous request returned HTTP 401.',
  jsonb_build_object(
    'verifyJwt',false,
    'authentication','github-oidc',
    'workflowRun',36389217864,
    'anonymousProbeStatus',401
  )
where not exists (
  select 1
  from foundation.service_deployment_observations
  where service_id='foundation.deployment-receipt-ingest'
    and environment='production'
    and runtime_version='1'
    and artifact_sha256='ba07c8dbf0f2334ae719f4e8323e223f8ab539705bcd4b4ca51dd7e40baaa596'
);
