begin;

-- Layer 43 classifies post-bind readiness drift without rewriting release identity.
-- Use deterministic readers so classification is isolated from the CI runner.

create or replace function foundation.evaluate_foundation_readiness_v1(
  p_environment text default 'production',p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $ready$
 select jsonb_build_object(
  'foundationReadinessResponse','shine-foundation/control-plane-readiness-response-v1',
  'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
  'readinessState','degraded','safeMode','degraded',
  'privilegedOperationsMode','degraded','workerOperationsMode','degraded',
  'reasonCodes',jsonb_build_array('dependency-degraded'),
  'evidenceFingerprint',repeat('7',32),
  'checks',jsonb_build_object('dependencyRollup',jsonb_build_object(
    'state','degraded','degradedScopes',jsonb_build_array('protected-operations','identity-operations'),
    'guardedScopes','[]'::jsonb,'blockedScopes','[]'::jsonb
  ))
 );
$ready$;

create or replace function foundation.get_service_deployment_truth_v1(
  p_service_id text,p_environment text default 'production'
)
returns jsonb language sql stable security definer set search_path='' as $dep$
 select jsonb_build_object(
  'deploymentTruthResponse','shine-foundation/deployment-truth-response-v1',
  'serviceId',p_service_id,'environment',p_environment,'truthState','aligned',
  'expected',jsonb_build_object('sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','version','43','artifactSha256',repeat('a',64))
 );
$dep$;

create or replace function foundation.get_foundation_release_identity_health_v1(
  p_environment text default 'production'
)
returns jsonb language sql stable security definer set search_path='' as $identity$
 select jsonb_build_object(
  'foundationReleaseIdentityHealthResponse','shine-foundation/release-identity-health-response-v1',
  'state','pass','matchesCurrentDeployment',true,'matchesCurrentPublication',true
 );
$identity$;

-- Build one valid immutable binding chain for Layer 43.
insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
) values (
  '43000000-0000-4000-8000-000000000002'::uuid,'foundation.gateway','production',
  'supabase-edge','supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  '43',repeat('a',64),'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer43:provider',now(),'layer43-test','{"test":true}'::jsonb,now()
);

insert into foundation.service_deployment_receipt_publications(
  publication_id,publication_key,receipt_id,service_id,environment,provider,
  runtime_version,artifact_sha256,source_ref,provider_evidence_ref,
  publication_outcome,submitted_by,transport,transport_run_id,
  transport_run_attempt,transport_event,transport_repository,transport_ref,
  transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values (
  '43000000-0000-4000-8000-000000000003'::uuid,
  'github-oidc:430000:1:43000000-0000-4000-8000-000000000002',
  '43000000-0000-4000-8000-000000000002'::uuid,'foundation.gateway','production',
  'supabase-edge','43',repeat('a',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer43:provider','accepted-new','github-actions-oidc','github-oidc',
  '430000','1','push','doug-dotcom/ShineUniverse-shine-core','refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('4',40),false,'{"test":true}'::jsonb,now()
);

insert into foundation.foundation_release_identity_bindings(
  binding_id,release_ref,service_id,environment,foundation_layer,source_ref,
  runtime_version,artifact_sha256,deployment_receipt_id,publication_id,
  publication_assurance,readiness_state_at_bind,readiness_fingerprint_at_bind,
  bound_by,metadata,bound_at
) values (
  '43000000-0000-4000-8000-000000000001'::uuid,'foundation:layer-42:aaaaaaaa',
  'foundation.gateway','production',42,
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  '43',repeat('a',64),'43000000-0000-4000-8000-000000000002'::uuid,
  '43000000-0000-4000-8000-000000000003'::uuid,'github-oidc',
  'ready',repeat('6',32),'layer43-test','{}'::jsonb,now()
);

do $degraded$
declare v jsonb;
begin
 select foundation.get_foundation_readiness_drift_v1('production',now()) into v;
 if v->>'driftState'<>'operational-degradation'
    or v->>'deploymentIdentityStable'<>'true'
    or v->>'requiresReleaseRebind'<>'false'
    or v->>'requiresMonitoring'<>'true'
    or v->>'privilegedOperationsRestricted'<>'true'
    or not (v->'reasonCodes' ? 'dependency-degraded')
    or not (v->'degradedScopes' ? 'protected-operations') then
   raise exception 'Dependency degradation must be attributed without rebind: %',v;
 end if;
end;
$degraded$;

select foundation.record_foundation_readiness_drift_observation_v1('production',now());

do $recorded$
declare v foundation.foundation_readiness_drift_observations%rowtype;
begin
 select * into v from foundation.foundation_readiness_drift_observations
 where binding_id='43000000-0000-4000-8000-000000000001'::uuid
 order by observation_sequence desc limit 1;
 if v.drift_state<>'operational-degradation'
    or not v.deployment_identity_stable
    or v.privileged_operations_mode<>'degraded'
    or not (v.degraded_scopes ? 'protected-operations') then
   raise exception 'Recorded drift evidence invalid: %',row_to_json(v);
 end if;
end;
$recorded$;

-- Stable readiness fingerprint should classify stable.
create or replace function foundation.evaluate_foundation_readiness_v1(
  p_environment text default 'production',p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $stable$
 select jsonb_build_object(
  'foundationReadinessResponse','shine-foundation/control-plane-readiness-response-v1',
  'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
  'readinessState','ready','safeMode','normal',
  'privilegedOperationsMode','normal','workerOperationsMode','normal',
  'reasonCodes','[]'::jsonb,'evidenceFingerprint',repeat('6',32),
  'checks',jsonb_build_object('dependencyRollup',jsonb_build_object(
    'state','operational','degradedScopes','[]'::jsonb,
    'guardedScopes','[]'::jsonb,'blockedScopes','[]'::jsonb
  ))
 );
$stable$;

do $stable_test$
declare v jsonb;
begin
 select foundation.get_foundation_readiness_drift_v1('production',now()) into v;
 if v->>'driftState'<>'stable'
    or v->>'requiresMonitoring'<>'false'
    or v->>'requiresReleaseRebind'<>'false'
    or v->>'privilegedOperationsRestricted'<>'false' then
   raise exception 'Matching readiness fingerprint must be stable: %',v;
 end if;
end;
$stable_test$;

-- Deployment mismatch is identity drift, not operational degradation.
create or replace function foundation.get_service_deployment_truth_v1(
  p_service_id text,p_environment text default 'production'
)
returns jsonb language sql stable security definer set search_path='' as $depdrift$
 select jsonb_build_object(
  'deploymentTruthResponse','shine-foundation/deployment-truth-response-v1',
  'serviceId',p_service_id,'environment',p_environment,'truthState','drift'
 );
$depdrift$;

do $identity_drift$
declare v jsonb;
begin
 select foundation.get_foundation_readiness_drift_v1('production',now()) into v;
 if v->>'driftState'<>'identity-drift'
    or v->>'deploymentIdentityStable'<>'false'
    or v->>'requiresReleaseRebind'<>'true' then
   raise exception 'Deployment drift must require release identity handling: %',v;
 end if;
end;
$identity_drift$;

rollback;
