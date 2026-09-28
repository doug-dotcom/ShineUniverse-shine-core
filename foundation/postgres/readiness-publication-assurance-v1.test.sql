begin;

-- Complete deterministic Layer-34 fixture: exact deployment, health, Defence,
-- current-runtime audit proof, deployment receipt and trusted OIDC publication.

insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://test/functions/foundation-gateway',
  'layer34-a',
  repeat('a',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  now()+interval '1 second',
  'test:layer34:deployment-expectation:a',
  'Layer 34 provenance readiness fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://test/functions/foundation-gateway',
  'layer34-a',
  repeat('a',64),
  'active','unknown',
  now()+interval '1 second',
  'manual-verified',
  'test:layer34:deployment-observation:a',
  'Layer 34 provenance readiness fixture.',
  '{"test":true}'::jsonb
);

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer34-a',
  now()-interval '5 minutes',
  now()+interval '2 seconds',
  100,0,0,20,25,
  0,'manual-verified',
  'test:layer34:health:a',
  'Healthy Layer 34 fixture.',
  '{"test":true}'::jsonb,
  now()+interval '2 seconds'
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '34000000-0000-4000-8000-000000000001'::uuid,
  '1.0.0','production','pass',
  now()+interval '3 seconds',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer34:defence:pass',
  now()+interval '3 seconds'
);

insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
)
values (
  '34000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'supabase://test/functions/foundation-gateway',
  'layer34-a',
  repeat('a',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer34:provider:a',
  now()+interval '1 second',
  'layer34-test',
  '{"test":true}'::jsonb,
  now()+interval '1 second'
);

insert into foundation.service_deployment_receipt_publications(
  publication_key,receipt_id,service_id,environment,provider,runtime_version,
  artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,
  submitted_by,transport,transport_run_id,transport_run_attempt,transport_event,
  transport_repository,transport_ref,transport_workflow_ref,transport_workflow_sha,
  rollback,metadata,published_at
)
values (
  'github-oidc:340000:1:34000000-0000-4000-8000-000000000100',
  '34000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer34-a',
  repeat('a',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer34:provider:a',
  'accepted-new',
  'github-actions-oidc',
  'github-oidc',
  '340000','1','push',
  'doug-dotcom/ShineUniverse-shine-core',
  'refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('1',40),
  false,
  '{"test":true}'::jsonb,
  now()+interval '4 seconds'
);

do $layer34_audit$
declare
  v_policy jsonb;
  v_audit uuid := '34000000-0000-4000-8000-000000000200'::uuid;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/consent','production',now()+interval '5 seconds'
  ) into v_policy;

  if v_policy->>'policyState' <> 'admit' then
    raise exception 'Layer 34 ready fixture policy should admit: %',v_policy;
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
$layer34_audit$;


do $layer34_pass$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '7 seconds'
  ) into v;

  if v#>>'{checks,publicationAttestation,state}' <> 'pass'
     or v#>>'{checks,publicationAttestation,assurance}' <> 'github-oidc'
     or v#>>'{checks,publicationAttestation,matchesDeployment}' <> 'true' then
    raise exception 'current OIDC publication should be trusted and match deployment: %',v;
  end if;

  if v->'reasonCodes' ? 'deployment-publication-attestation-missing'
     or v->'reasonCodes' ? 'deployment-publication-attestation-degraded'
     or v->'reasonCodes' ? 'deployment-publication-attestation-mismatch' then
    raise exception 'trusted matching publication must not add provenance reasons: %',v;
  end if;

  if v->>'readinessState' <> 'ready' then
    raise exception 'clean control plane with matching OIDC publication should be ready: %',v;
  end if;
end;
$layer34_pass$;


-- A newer manual publication for the same immutable deployment should degrade assurance
-- without changing operational modes.
insert into foundation.service_deployment_receipt_publications(
  publication_key,receipt_id,service_id,environment,provider,runtime_version,
  artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,
  submitted_by,transport,transport_run_id,transport_run_attempt,transport_event,
  transport_repository,transport_ref,transport_workflow_ref,transport_workflow_sha,
  rollback,metadata,published_at
)
values (
  'test:layer34:manual',
  '34000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer34-a',
  repeat('a',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer34:provider:a',
  'replayed-existing',
  'layer34-test',
  'manual-verified',
  null,null,null,null,null,null,null,
  false,
  '{"test":true}'::jsonb,
  now()+interval '8 seconds'
);

do $layer34_degraded$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '9 seconds'
  ) into v;

  if v#>>'{checks,publicationAttestation,state}' <> 'degraded' then
    raise exception 'manual publication should degrade provenance assurance: %',v;
  end if;

  if v->>'readinessState' <> 'degraded' then
    raise exception 'degraded provenance should degrade readiness: %',v;
  end if;

  if v->>'safeMode' <> 'normal'
     or v->>'privilegedOperationsMode' <> 'normal'
     or v->>'workerOperationsMode' <> 'normal' then
    raise exception 'provenance degradation must not masquerade as runtime degradation: %',v;
  end if;

  if not (v->'reasonCodes' ? 'deployment-publication-attestation-degraded') then
    raise exception 'degraded provenance reason must be explicit: %',v;
  end if;
end;
$layer34_degraded$;


-- Restore strongest publication assurance with a newer OIDC re-attestation.
insert into foundation.service_deployment_receipt_publications(
  publication_key,receipt_id,service_id,environment,provider,runtime_version,
  artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,
  submitted_by,transport,transport_run_id,transport_run_attempt,transport_event,
  transport_repository,transport_ref,transport_workflow_ref,transport_workflow_sha,
  rollback,metadata,published_at
)
values (
  'github-oidc:340001:1:34000000-0000-4000-8000-000000000100',
  '34000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer34-a',
  repeat('a',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer34:provider:a',
  'replayed-existing',
  'github-actions-oidc',
  'github-oidc',
  '340001','1','push',
  'doug-dotcom/ShineUniverse-shine-core',
  'refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('4',40),
  false,
  '{"test":true}'::jsonb,
  now()+interval '10 seconds'
);

do $layer34_restored$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '11 seconds'
  ) into v;

  if v->>'readinessState' <> 'ready'
     or v#>>'{checks,publicationAttestation,state}' <> 'pass' then
    raise exception 'fresh OIDC re-attestation should restore ready provenance: %',v;
  end if;
end;
$layer34_restored$;


-- A newer deployment receipt without a publication attestation prevents READY.
insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
)
values (
  '34000000-0000-4000-8000-000000000101'::uuid,
  'foundation.gateway','production','supabase-edge',
  'supabase://test/functions/foundation-gateway',
  'layer34-b',
  repeat('b',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'test:layer34:future-receipt',
  now()+interval '12 seconds',
  'layer34-test',
  '{"test":true}'::jsonb,
  now()+interval '12 seconds'
);

do $layer34_unknown$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '13 seconds'
  ) into v;

  if v#>>'{checks,publicationAttestation,state}' <> 'unknown' then
    raise exception 'unattested current receipt should make publication assurance unknown: %',v;
  end if;

  if v->>'readinessState' <> 'unknown' then
    raise exception 'missing current publication attestation must prevent ready: %',v;
  end if;

  if not (v->'reasonCodes' ? 'deployment-publication-attestation-missing') then
    raise exception 'missing publication reason must be explicit: %',v;
  end if;
end;
$layer34_unknown$;


-- Even strong OIDC assurance is unsafe if it attests a receipt that disagrees with
-- current canonical deployment truth.
insert into foundation.service_deployment_receipt_publications(
  publication_key,receipt_id,service_id,environment,provider,runtime_version,
  artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,
  submitted_by,transport,transport_run_id,transport_run_attempt,transport_event,
  transport_repository,transport_ref,transport_workflow_ref,transport_workflow_sha,
  rollback,metadata,published_at
)
values (
  'github-oidc:340002:1:34000000-0000-4000-8000-000000000101',
  '34000000-0000-4000-8000-000000000101'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer34-b',
  repeat('b',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'test:layer34:future-receipt',
  'replayed-existing',
  'github-actions-oidc',
  'github-oidc',
  '340002','1','push',
  'doug-dotcom/ShineUniverse-shine-core',
  'refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('5',40),
  false,
  '{"test":true}'::jsonb,
  now()+interval '14 seconds'
);

do $layer34_mismatch$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()+interval '15 seconds'
  ) into v;

  if v#>>'{checks,publicationAttestation,state}' <> 'pass'
     or v#>>'{checks,publicationAttestation,matchesDeployment}' <> 'false' then
    raise exception 'future receipt should have valid OIDC assurance but mismatch current deployment: %',v;
  end if;

  if v->>'readinessState' <> 'not-ready' then
    raise exception 'trusted publication for wrong deployment must be not-ready: %',v;
  end if;

  if not (v->'reasonCodes' ? 'deployment-publication-attestation-mismatch') then
    raise exception 'deployment/publication mismatch reason must be explicit: %',v;
  end if;
end;
$layer34_mismatch$;


do $layer34_security$
begin
  if not has_function_privilege(
    'foundation_runtime',
    'foundation.evaluate_foundation_readiness_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must still evaluate readiness';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.evaluate_foundation_readiness_v1(text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'anon must not evaluate provenance-aware readiness';
  end if;
end;
$layer34_security$;

rollback;
