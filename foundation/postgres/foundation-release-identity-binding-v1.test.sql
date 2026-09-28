begin;

-- Deterministic Layer-35 fixture: an aligned gateway deployment with healthy runtime
-- evidence, complete current-runtime audit proof and a trusted GitHub-OIDC publication.

insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer35-c',
  repeat('c',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/cccccccccccccccccccccccccccccccccccccccc',
  now()-interval '3 seconds',
  'test:layer35:deployment-expectation:c',
  'Layer 35 immutable release identity fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer35-c',
  repeat('c',64),
  'active','healthy',
  now()-interval '3 seconds',
  'manual-verified',
  'test:layer35:deployment-observation:c',
  'Layer 35 immutable release identity fixture.',
  '{"test":true}'::jsonb
);

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer35-c',
  now()-interval '5 minutes',
  now()-interval '2 seconds',
  100,0,0,20,25,
  0,'manual-verified',
  'test:layer35:health:c',
  'Healthy Layer 35 fixture.',
  '{"test":true}'::jsonb,
  now()-interval '2 seconds'
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '35000000-0000-4000-8000-000000000001'::uuid,
  '1.0.0','production','pass',
  now()-interval '1 second',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer35:defence:pass',
  now()-interval '1 second'
);

insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
)
values (
  '35000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer35-c',
  repeat('c',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/cccccccccccccccccccccccccccccccccccccccc',
  'test:layer35:provider:c',
  now()-interval '2 seconds',
  'layer35-test',
  '{"test":true}'::jsonb,
  now()-interval '2 seconds'
);

insert into foundation.service_deployment_receipt_publications(
  publication_id,publication_key,receipt_id,service_id,environment,provider,
  runtime_version,artifact_sha256,source_ref,provider_evidence_ref,
  publication_outcome,submitted_by,transport,transport_run_id,
  transport_run_attempt,transport_event,transport_repository,transport_ref,
  transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
)
values (
  '35000000-0000-4000-8000-000000000101'::uuid,
  'github-oidc:350000:1:35000000-0000-4000-8000-000000000100',
  '35000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer35-c',
  repeat('c',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/cccccccccccccccccccccccccccccccccccccccc',
  'test:layer35:provider:c',
  'accepted-new',
  'github-actions-oidc',
  'github-oidc',
  '350000','1','push',
  'doug-dotcom/ShineUniverse-shine-core',
  'refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('3',40),
  false,
  '{"test":true}'::jsonb,
  now()-interval '1 second'
);

do $layer35_audit$
declare
  v_policy jsonb;
  v_audit uuid := '35000000-0000-4000-8000-000000000200'::uuid;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/consent','production',now()
  ) into v_policy;

  if v_policy->>'policyState' <> 'admit' then
    raise exception 'Layer 35 fixture policy should admit: %',v_policy;
  end if;

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'policy','POST','/v1/grants/consent','production',
    v_policy,null,null,null,now()
  );

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'outcome','POST','/v1/grants/consent','production',
    null,401,'unauthenticated',null,now()
  );
end;
$layer35_audit$;


do $layer35_bind$
declare
  v jsonb;
  v_health jsonb;
begin
  select foundation.bind_foundation_release_identity_v1(
    35,'layer35-test','{"test":true}'::jsonb
  ) into v;

  if v->>'status' <> 'bound-new'
     or v->>'releaseRef' <> 'foundation:layer-35:cccccccc'
     or v->>'runtimeVersion' <> 'layer35-c'
     or v->>'publicationAssurance' <> 'github-oidc' then
    raise exception 'Layer 35 release binding should capture exact deployment identity: %',v;
  end if;

  v_health := v->'health';

  if v_health->>'state' <> 'pass'
     or v_health->>'matchesCurrentDeployment' <> 'true'
     or v_health->>'matchesCurrentPublication' <> 'true' then
    raise exception 'Fresh immutable release identity should pass health: %',v_health;
  end if;

  if v_health->>'readinessChangedSinceBinding' <> 'false' then
    raise exception 'Fresh binding should capture current readiness fingerprint: %',v_health;
  end if;
end;
$layer35_bind$;


do $layer35_replay$
declare
  v jsonb;
begin
  select foundation.bind_foundation_release_identity_v1(
    35,'layer35-test','{"secondCall":true}'::jsonb
  ) into v;

  if v->>'status' <> 'replayed-existing'
     or v->>'releaseRef' <> 'foundation:layer-35:cccccccc' then
    raise exception 'Identical release binding must be idempotent: %',v;
  end if;
end;
$layer35_replay$;


do $layer35_security$
begin
  if not has_function_privilege(
    'service_role',
    'foundation.bind_foundation_release_identity_v1(integer,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'service_role must be allowed to bind verified release identity';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.bind_foundation_release_identity_v1(integer,text,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'foundation.bind_foundation_release_identity_v1(integer,text,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'foundation_runtime',
    'foundation.bind_foundation_release_identity_v1(integer,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Release identity binder must remain control-plane only';
  end if;

  if has_table_privilege(
    'service_role',
    'foundation.foundation_release_identity_bindings',
    'INSERT'
  ) or has_table_privilege(
    'foundation_runtime',
    'foundation.foundation_release_identity_bindings',
    'INSERT'
  ) then
    raise exception 'Release identity ledger must only be written through binder';
  end if;

  if not has_function_privilege(
    'foundation_runtime',
    'foundation.get_foundation_release_identity_health_v1(text)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must be able to read release identity health';
  end if;
end;
$layer35_security$;


-- New canonical deployment truth without a corresponding publication must invalidate
-- the previous immutable binding rather than leaving stale green metadata.
insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer35-d',
  repeat('d',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/dddddddddddddddddddddddddddddddddddddddd',
  now()+interval '1 second',
  'test:layer35:deployment-expectation:d',
  'Intentional Layer 35 drift fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer35-d',
  repeat('d',64),
  'active','healthy',
  now()+interval '1 second',
  'manual-verified',
  'test:layer35:deployment-observation:d',
  'Intentional Layer 35 drift fixture.',
  '{"test":true}'::jsonb
);

do $layer35_drift$
declare
  v jsonb;
  v_bind_failed boolean := false;
begin
  select foundation.get_foundation_release_identity_health_v1('production')
    into v;

  if v->>'state' <> 'fail'
     or v->>'matchesCurrentDeployment' <> 'false'
     or not (v->'reasonCodes' ? 'release-identity-deployment-mismatch') then
    raise exception 'Release identity must fail closed when canonical deployment moves: %',v;
  end if;

  begin
    perform foundation.bind_foundation_release_identity_v1(
      36,'layer35-test','{"test":"drift"}'::jsonb
    );
  exception when others then
    v_bind_failed := true;
  end;

  if not v_bind_failed then
    raise exception 'Binder must refuse a deployment without matching trusted publication/readiness';
  end if;
end;
$layer35_drift$;

rollback;
