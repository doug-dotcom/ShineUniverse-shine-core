begin;

-- CI-only Universe projection shell. Production uses the real Universe tables.
create schema if not exists universe;

create table if not exists universe.app_registry (
  app_key text primary key,
  display_name text not null,
  category text not null,
  lifecycle text not null default 'active',
  canonical_repo text,
  canonical_repo_status text not null default 'confirmed',
  supabase_project_ref text,
  supabase_project_name text,
  layer_scheme text not null,
  current_layer integer,
  current_layer_status text not null default 'verified',
  build_state text not null default 'built',
  production_service text,
  source_of_truth text not null,
  evidence_note text,
  last_verified_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
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


-- Establish a healthy initial Gateway deployment and bind Foundation layer 40 to it.
insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer41-a',
  repeat('a',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  now()+interval '1 second',
  'test:layer41:deployment-expectation:a',
  'Layer 41 initial deployment fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer41-a',
  repeat('a',64),
  'active','healthy',
  now()+interval '1 second',
  'manual-verified',
  'test:layer41:deployment-observation:a',
  'Layer 41 initial deployment fixture.',
  '{"test":true}'::jsonb
);

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer41-a',
  now()-interval '5 minutes',
  now()+interval '2 seconds',
  100,0,0,20,25,
  0,'manual-verified',
  'test:layer41:health:a',
  'Healthy Layer 41 initial fixture.',
  '{"test":true}'::jsonb,
  now()+interval '2 seconds'
);

insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  '41000000-0000-4000-8000-000000000001'::uuid,
  '1.0.0','production','pass',
  now()+interval '3 seconds',
  now()+interval '2 hours',
  '{"test":true}'::jsonb,
  'test:layer41:defence:pass',
  now()+interval '3 seconds'
);

insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
)
values (
  '41000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer41-a',
  repeat('a',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer41:provider:a',
  now()+interval '2 seconds',
  'layer41-test',
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
  '41000000-0000-4000-8000-000000000101'::uuid,
  'github-oidc:410000:1:41000000-0000-4000-8000-000000000100',
  '41000000-0000-4000-8000-000000000100'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer41-a',
  repeat('a',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'test:layer41:provider:a',
  'accepted-new','github-actions-oidc','github-oidc',
  '410000','1','push',
  'doug-dotcom/ShineUniverse-shine-core','refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('1',40),false,'{"test":true}'::jsonb,
  now()+interval '4 seconds'
);

do $layer41_initial_audit$
declare
  v_policy jsonb;
  v_audit uuid := '41000000-0000-4000-8000-000000000110'::uuid;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/consent','production',now()+interval '5 seconds'
  ) into v_policy;

  if v_policy->>'policyState'<>'admit' then
    raise exception 'Layer 41 initial policy should admit: %',v_policy;
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
$layer41_initial_audit$;

do $layer41_initial_readiness$
declare
  v jsonb;
begin
  select foundation.evaluate_foundation_readiness_v1(
    'production',now()
  ) into v;

  if coalesce(v->>'readinessState','unknown')
       not in ('ready','restricted','degraded') then
    raise exception 'Layer 41 initial fixture must be bindable before executor tests: %',v;
  end if;
end;
$layer41_initial_readiness$;


do $layer41_initial_binding$
declare
  v jsonb;
begin
  select foundation.bind_foundation_release_identity_v1(
    40,'layer41-test','{"fixture":"initial"}'::jsonb
  ) into v;

  if v->>'status'<>'bound-new'
     or v->>'releaseRef'<>'foundation:layer-40:aaaaaaaa' then
    raise exception 'Layer 41 initial binding failed: %',v;
  end if;
end;
$layer41_initial_binding$;


-- Registry deliberately points to an older release. The current binding release is
-- also absent from the readiness release ledger.
insert into universe.readiness_releases(
  app_key,release_ref,release_label,source_layer_ref,source_commit_ref,
  opened_at,evidence_ref,evidence_note
)
values (
  'foundation',
  'foundation:layer-39:99999999',
  'Intentional stale release',
  'layer:39',
  repeat('9',40),
  now()-interval '30 minutes',
  'https://github.com/doug-dotcom/ShineUniverse-shine-core/commit/'
    ||repeat('9',40),
  'Layer 41 stale registry fixture.'
);

insert into universe.app_registry(
  app_key,display_name,category,lifecycle,canonical_repo,canonical_repo_status,
  supabase_project_ref,supabase_project_name,layer_scheme,current_layer,
  current_layer_status,build_state,production_service,source_of_truth,
  evidence_note,last_verified_at,created_at,updated_at,readiness_release_ref
)
values (
  'foundation','Shine Foundation','control_plane','active',
  'doug-dotcom/ShineUniverse-shine-core','confirmed',
  'sjpxqeyewahraxvidvcc','Shine Foundation',
  'monotonic Foundation layers',
  39,'verified','deployed','foundation.gateway',
  'Layer 41 CI fixture',
  'Intentional stale registry state.',
  now()-interval '30 minutes',now()-interval '1 hour',
  now()-interval '30 minutes',
  'foundation:layer-39:99999999'
);


-- Test-only proposal builder. SECURITY DEFINER lets the separated roles request the
-- same canonical proposal bytes without gaining direct table-read authority.
create or replace function foundation.layer41_test_proposal_v1(
  p_action_key text,
  p_bad boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer41_test_proposal$
declare
  v_incident foundation.foundation_control_plane_incident_events%rowtype;
  v_binding foundation.foundation_release_identity_bindings%rowtype;
  v_layer integer;
  v_layer_status text;
  v_build_state text;
  v_release_ref text;
begin
  select * into v_incident
  from foundation.current_foundation_control_plane_incident_state
  where incident_key='production:release_projection';

  select * into v_binding
  from foundation.current_foundation_release_identity
  where service_id='foundation.gateway'
    and environment='production';

  if p_action_key='apply-release-ledger-repair' then
    return jsonb_build_object(
      'remediationProposal','shine-foundation/remediation-proposal-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'actionKey',p_action_key,
      'incidentEventId',v_incident.event_id,
      'evidenceFingerprint',v_incident.evidence_fingerprint,
      'releaseRef',v_binding.release_ref,
      'operation',jsonb_build_object(
        'releaseLabel','Layer 40 repaired release projection',
        'sourceCommitRef',repeat('c',40),
        'evidenceRef',
          'https://github.com/doug-dotcom/ShineUniverse-shine-core/commit/'
          ||repeat('c',40),
        'evidenceNote','Layer 41 approved release-ledger repair fixture.'
      )
    );
  elsif p_action_key='apply-registry-repair' then
    select current_layer,current_layer_status,build_state,readiness_release_ref
      into v_layer,v_layer_status,v_build_state,v_release_ref
    from universe.app_registry
    where app_key='foundation';

    return jsonb_build_object(
      'remediationProposal','shine-foundation/remediation-proposal-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'actionKey',p_action_key,
      'incidentEventId',v_incident.event_id,
      'evidenceFingerprint',v_incident.evidence_fingerprint,
      'releaseRef',v_binding.release_ref,
      'operation',jsonb_build_object(
        'expectedRegistry',jsonb_build_object(
          'currentLayer',case when p_bad then v_layer+99 else v_layer end,
          'currentLayerStatus',v_layer_status,
          'buildState',v_build_state,
          'readinessReleaseRef',v_release_ref
        ),
        'evidenceNote','Layer 41 approved registry repair fixture.'
      )
    );
  elsif p_action_key='rebind-release-identity' then
    return jsonb_build_object(
      'remediationProposal','shine-foundation/remediation-proposal-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'actionKey',p_action_key,
      'incidentEventId',v_incident.event_id,
      'evidenceFingerprint',v_incident.evidence_fingerprint,
      'releaseRef',v_binding.release_ref,
      'operation',jsonb_build_object(
        'foundationLayer',40,
        'expectedBindingId',v_binding.binding_id,
        'expectedBindingReleaseRef',v_binding.release_ref,
        'evidenceNote','Layer 41 approved release rebind fixture.'
      )
    );
  end if;

  raise exception 'layer41-test-action-invalid';
end;
$layer41_test_proposal$;

revoke all on function foundation.layer41_test_proposal_v1(text,boolean)
  from public,anon,authenticated;
grant execute on function foundation.layer41_test_proposal_v1(text,boolean)
  to foundation_remediation_approver,service_role,
     foundation_remediation_executor,foundation_remediation_mutator;


-- Open a critical incident from the actual Layer-36 projection.
do $layer41_open_initial_incident$
declare
  v_observation jsonb;
  v_snapshot jsonb;
  v_observation_id uuid;
begin
  v_observation :=
    foundation.record_foundation_release_projection_observation_v1(
      'production',now()
    );
  v_snapshot := v_observation->'snapshot';
  v_observation_id := (v_observation->>'observationId')::uuid;

  if v_snapshot->>'state'<>'fail'
     or not (v_snapshot->'reasonCodes' ? 'bound-release-ledger-missing') then
    raise exception 'Layer 41 initial projection must expose missing bound release: %',
      v_snapshot;
  end if;

  insert into foundation.foundation_control_plane_incident_events(
    event_id,incident_key,environment,domain,event_type,source_state,severity,
    reason_codes,evidence_fingerprint,projection_observation_id,
    detection_started_at,persistence_threshold_seconds,persistence_seconds,
    snapshot,occurred_at,evidence_ref
  )
  values (
    '41000000-0000-4000-8000-000000000200'::uuid,
    'production:release_projection','production','release_projection',
    'opened','fail','critical',
    v_snapshot->'reasonCodes',
    v_snapshot->>'evidenceFingerprint',
    v_observation_id,
    now()-interval '10 minutes',
    300,600,
    v_snapshot,now(),
    'test:layer41:initial-incident'
  );
end;
$layer41_open_initial_incident$;


do $layer41_control_health$
declare
  v jsonb;
begin
  select foundation.get_scoped_remediation_executor_control_health_v1()
    into v;

  if v->>'state'<>'pass'
     or v->>'mutatorRoleExists'<>'true'
     or v->>'serviceRoleIsMutatorMember'<>'false'
     or v->>'approverRoleIsMutatorMember'<>'false'
     or v->>'admissionExecutorRoleIsMutatorMember'<>'false'
     or v->>'serviceRoleCanExecute'<>'false'
     or v->>'approverRoleCanExecute'<>'false'
     or v->>'admissionExecutorRoleCanExecute'<>'false'
     or v->>'mutatorRoleCanExecute'<>'true'
     or v->>'mutatorRoleCanUpdateRegistryDirectly'<>'false'
     or v->>'mutatorRoleCanInsertReleaseLedgerDirectly'<>'false'
     or v->>'mutatorRoleCanInsertExecutionEventsDirectly'<>'false'
     or v->>'activeExecutionOperationCount'<>'3'
     or v->>'autoRepairRegistered'<>'false'
     or v->>'arbitrarySqlExecution'<>'false' then
    raise exception 'Layer 41 executor isolation must pass: %',v;
  end if;
end;
$layer41_control_health$;


-- RELEASE LEDGER REPAIR: approve, consume, admit, reject tampered proposal, then execute exact proposal.
set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000301'::uuid,
  'apply-release-ledger-repair',
  '41000000-0000-4000-8000-000000000200'::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-release-ledger-repair',false)
  ),
  'human:layer41-ledger',
  'explicit-human',
  now()-interval '1 second',
  now()+interval '10 minutes'
);

reset role;

set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000302'::uuid,
  '41000000-0000-4000-8000-000000000301'::uuid,
  'apply-release-ledger-repair',
  '41000000-0000-4000-8000-000000000200'::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-release-ledger-repair',false)
  ),
  now()
);

reset role;

set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '41000000-0000-4000-8000-000000000303'::uuid,
  '41000000-0000-4000-8000-000000000304'::uuid,
  '41000000-0000-4000-8000-000000000301'::uuid,
  'apply-release-ledger-repair',
  '41000000-0000-4000-8000-000000000200'::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-release-ledger-repair',false)
  ),
  now()
);

reset role;

set local role foundation_remediation_mutator;

select foundation.execute_scoped_remediation_v1(
  '41000000-0000-4000-8000-000000000305'::uuid,
  '41000000-0000-4000-8000-000000000306'::uuid,
  '41000000-0000-4000-8000-000000000304'::uuid,
  jsonb_set(
    foundation.layer41_test_proposal_v1('apply-release-ledger-repair',false),
    '{operation,releaseLabel}',
    '"Tampered release label"'::jsonb
  ),
  now()
);

reset role;

do $layer41_tamper_did_not_consume$
declare
  v_count integer;
begin
  select count(*) into v_count
  from foundation.remediation_execution_events
  where admission_id='41000000-0000-4000-8000-000000000304'::uuid
    and event_type='denied'
    and reason_code='remediation-execution-proposal-hash-mismatch';

  if v_count<>1 then
    raise exception 'Tampered proposal must be denied without consuming admission';
  end if;

  if exists (
    select 1 from foundation.remediation_execution_events
    where admission_id='41000000-0000-4000-8000-000000000304'::uuid
      and event_type in ('executed','failed')
  ) then
    raise exception 'Tampered proposal unexpectedly consumed admission';
  end if;
end;
$layer41_tamper_did_not_consume$;

set local role foundation_remediation_mutator;

select foundation.execute_scoped_remediation_v1(
  '41000000-0000-4000-8000-000000000307'::uuid,
  '41000000-0000-4000-8000-000000000308'::uuid,
  '41000000-0000-4000-8000-000000000304'::uuid,
  foundation.layer41_test_proposal_v1('apply-release-ledger-repair',false),
  now()
);

reset role;

do $layer41_ledger_repaired$
declare
  v_status jsonb;
begin
  if not exists (
    select 1
    from universe.readiness_releases
    where app_key='foundation'
      and release_ref='foundation:layer-40:aaaaaaaa'
      and source_layer_ref='layer:40'
      and source_commit_ref=repeat('c',40)
  ) then
    raise exception 'Approved release-ledger repair was not applied';
  end if;

  select foundation.get_remediation_execution_admission_status_v1(
    '41000000-0000-4000-8000-000000000304'::uuid
  ) into v_status;

  if v_status->>'status'<>'consumed'
     or v_status->>'mayAttemptExecution'<>'false'
     or v_status#>>'{consumingExecution,eventType}'<>'executed' then
    raise exception 'Executed admission must be consumed: %',v_status;
  end if;
end;
$layer41_ledger_repaired$;


-- Refresh the incident evidence after the ledger mutation.
do $layer41_refresh_after_ledger$
declare
  v_observation jsonb;
  v_transition jsonb;
begin
  v_observation :=
    foundation.record_foundation_release_projection_observation_v1(
      'production',now()
    );

  v_transition :=
    foundation.transition_foundation_control_plane_incident_v1(
      'production',
      v_observation->'snapshot',
      (v_observation->>'observationId')::uuid,
      now(),
      300
    );

  if v_transition->>'eventType'<>'changed'
     or v_transition->>'sourceState'<>'fail' then
    raise exception 'Ledger repair should leave registry mismatch as changed incident: %',
      v_transition;
  end if;
end;
$layer41_refresh_after_ledger$;


-- REGISTRY REPAIR: an approved but wrong before-state must fail and consume its admission.
set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000311'::uuid,
  'apply-registry-repair',
  (
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
      ->>'incidentEventId'
  )::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-registry-repair',true)
  ),
  'human:layer41-registry-bad',
  'explicit-human',
  now()-interval '1 second',
  now()+interval '10 minutes'
);

reset role;

set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000312'::uuid,
  '41000000-0000-4000-8000-000000000311'::uuid,
  'apply-registry-repair',
  (
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
      ->>'incidentEventId'
  )::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-registry-repair',true)
  ),
  now()
);

reset role;

set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '41000000-0000-4000-8000-000000000313'::uuid,
  '41000000-0000-4000-8000-000000000314'::uuid,
  '41000000-0000-4000-8000-000000000311'::uuid,
  'apply-registry-repair',
  (
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
      ->>'incidentEventId'
  )::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-registry-repair',true)
  ),
  now()
);

reset role;

set local role foundation_remediation_mutator;

select foundation.execute_scoped_remediation_v1(
  '41000000-0000-4000-8000-000000000315'::uuid,
  '41000000-0000-4000-8000-000000000316'::uuid,
  '41000000-0000-4000-8000-000000000314'::uuid,
  foundation.layer41_test_proposal_v1('apply-registry-repair',true),
  now()
);

reset role;

do $layer41_bad_registry_consumed$
declare
  v_layer integer;
  v_status jsonb;
begin
  select current_layer into v_layer
  from universe.app_registry
  where app_key='foundation';

  if v_layer<>39 then
    raise exception 'Failed registry repair must roll back registry mutation';
  end if;

  select foundation.get_remediation_execution_admission_status_v1(
    '41000000-0000-4000-8000-000000000314'::uuid
  ) into v_status;

  if v_status->>'status'<>'consumed'
     or v_status#>>'{consumingExecution,eventType}'<>'failed' then
    raise exception 'Failed mutation must consume admission fail-safe: %',v_status;
  end if;
end;
$layer41_bad_registry_consumed$;


-- Fresh approval/admission with the correct exact before-state.
set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000321'::uuid,
  'apply-registry-repair',
  (
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
      ->>'incidentEventId'
  )::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
  ),
  'human:layer41-registry-good',
  'explicit-human',
  now()-interval '1 second',
  now()+interval '10 minutes'
);

reset role;

set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000322'::uuid,
  '41000000-0000-4000-8000-000000000321'::uuid,
  'apply-registry-repair',
  (
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
      ->>'incidentEventId'
  )::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
  ),
  now()
);

reset role;

set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '41000000-0000-4000-8000-000000000323'::uuid,
  '41000000-0000-4000-8000-000000000324'::uuid,
  '41000000-0000-4000-8000-000000000321'::uuid,
  'apply-registry-repair',
  (
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
      ->>'incidentEventId'
  )::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('apply-registry-repair',false)
  ),
  now()
);

reset role;

set local role foundation_remediation_mutator;

select foundation.execute_scoped_remediation_v1(
  '41000000-0000-4000-8000-000000000325'::uuid,
  '41000000-0000-4000-8000-000000000326'::uuid,
  '41000000-0000-4000-8000-000000000324'::uuid,
  foundation.layer41_test_proposal_v1('apply-registry-repair',false),
  now()
);

reset role;

do $layer41_registry_repaired$
declare
  v jsonb;
begin
  if not exists (
    select 1
    from universe.app_registry
    where app_key='foundation'
      and current_layer=40
      and current_layer_status='verified'
      and build_state='deployed'
      and readiness_release_ref='foundation:layer-40:aaaaaaaa'
  ) then
    raise exception 'Approved registry repair was not applied';
  end if;

  select foundation.get_foundation_release_projection_health_v1(
    'production',now()
  ) into v;

  if v->>'state'<>'aligned' then
    raise exception 'Release ledger + registry repairs should restore alignment: %',v;
  end if;

  perform foundation.run_foundation_control_plane_incident_sentinel_v1(
    'production',now(),300
  );
end;
$layer41_registry_repaired$;


-- Simulate a new live runtime. The current immutable binding remains on deployment A,
-- so release identity/projection should fail until the scoped rebind executes.
insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer41-b',
  repeat('b',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  now()+interval '20 seconds',
  'test:layer41:deployment-expectation:b',
  'Layer 41 replacement deployment fixture.'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,
  evidence_note,metadata
)
values (
  'foundation.gateway','production',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer41-b',
  repeat('b',64),
  'active','healthy',
  now()+interval '20 seconds',
  'manual-verified',
  'test:layer41:deployment-observation:b',
  'Layer 41 replacement deployment fixture.',
  '{"test":true}'::jsonb
);

insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
  runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','layer41-b',
  now()-interval '5 minutes',
  now()+interval '21 seconds',
  100,0,0,18,22,
  0,'manual-verified',
  'test:layer41:health:b',
  'Healthy Layer 41 replacement fixture.',
  '{"test":true}'::jsonb,
  now()+interval '21 seconds'
);

insert into foundation.service_deployment_receipts(
  receipt_id,service_id,environment,provider,runtime_ref,runtime_version,
  artifact_sha256,runtime_state,source_ref,provider_evidence_ref,
  provider_observed_at,submitted_by,metadata,recorded_at
)
values (
  '41000000-0000-4000-8000-000000000120'::uuid,
  'foundation.gateway','production','supabase-edge',
  'supabase://sjpxqeyewahraxvidvcc/functions/foundation-gateway',
  'layer41-b',
  repeat('b',64),
  'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'test:layer41:provider:b',
  now()+interval '20 seconds',
  'layer41-test',
  '{"test":true}'::jsonb,
  now()+interval '20 seconds'
);

insert into foundation.service_deployment_receipt_publications(
  publication_id,publication_key,receipt_id,service_id,environment,provider,
  runtime_version,artifact_sha256,source_ref,provider_evidence_ref,
  publication_outcome,submitted_by,transport,transport_run_id,
  transport_run_attempt,transport_event,transport_repository,transport_ref,
  transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
)
values (
  '41000000-0000-4000-8000-000000000121'::uuid,
  'github-oidc:410001:1:41000000-0000-4000-8000-000000000120',
  '41000000-0000-4000-8000-000000000120'::uuid,
  'foundation.gateway','production','supabase-edge',
  'layer41-b',
  repeat('b',64),
  'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'test:layer41:provider:b',
  'accepted-new','github-actions-oidc','github-oidc',
  '410001','1','push',
  'doug-dotcom/ShineUniverse-shine-core','refs/heads/main',
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
  repeat('2',40),false,'{"test":true}'::jsonb,
  now()+interval '22 seconds'
);

do $layer41_replacement_audit$
declare
  v_policy jsonb;
  v_audit uuid := '41000000-0000-4000-8000-000000000130'::uuid;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/consent','production',now()+interval '23 seconds'
  ) into v_policy;

  if v_policy->>'policyState'<>'admit' then
    raise exception 'Layer 41 replacement policy should admit: %',v_policy;
  end if;

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'policy','POST','/v1/grants/consent','production',
    v_policy,null,null,null,now()+interval '23 seconds'
  );

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,'outcome','POST','/v1/grants/consent','production',
    null,401,'unauthenticated',null,now()+interval '24 seconds'
  );
end;
$layer41_replacement_audit$;


do $layer41_open_rebind_incident$
declare
  v_health jsonb;
  v_observation jsonb;
  v_snapshot jsonb;
  v_observation_id uuid;
begin
  v_health :=
    foundation.get_foundation_release_identity_health_v1('production');

  if v_health->>'state'<>'fail'
     or not (v_health->'reasonCodes' ? 'release-identity-deployment-mismatch') then
    raise exception 'Runtime B must make binding A stale before rebind: %',v_health;
  end if;

  v_observation :=
    foundation.record_foundation_release_projection_observation_v1(
      'production',now()
    );
  v_snapshot := v_observation->'snapshot';
  v_observation_id := (v_observation->>'observationId')::uuid;

  if v_snapshot->>'state'<>'fail' then
    raise exception 'Runtime replacement must fail release projection before rebind: %',
      v_snapshot;
  end if;

  insert into foundation.foundation_control_plane_incident_events(
    event_id,incident_key,environment,domain,event_type,source_state,severity,
    reason_codes,evidence_fingerprint,projection_observation_id,
    detection_started_at,persistence_threshold_seconds,persistence_seconds,
    snapshot,occurred_at,evidence_ref
  )
  values (
    '41000000-0000-4000-8000-000000000400'::uuid,
    'production:release_projection','production','release_projection',
    'opened','fail','critical',
    v_snapshot->'reasonCodes',
    v_snapshot->>'evidenceFingerprint',
    v_observation_id,
    now()-interval '10 minutes',
    300,600,
    v_snapshot,now(),
    'test:layer41:rebind-incident'
  );
end;
$layer41_open_rebind_incident$;


-- RELEASE REBIND: exact proposal is approved/admitted/executed, but does not
-- silently update Universe registry or release ledger.
set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000401'::uuid,
  'rebind-release-identity',
  '41000000-0000-4000-8000-000000000400'::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('rebind-release-identity',false)
  ),
  'governance:layer41-rebind',
  'external-governance',
  now()-interval '1 second',
  now()+interval '10 minutes'
);

reset role;

set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '41000000-0000-4000-8000-000000000402'::uuid,
  '41000000-0000-4000-8000-000000000401'::uuid,
  'rebind-release-identity',
  '41000000-0000-4000-8000-000000000400'::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('rebind-release-identity',false)
  ),
  now()
);

reset role;

set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '41000000-0000-4000-8000-000000000403'::uuid,
  '41000000-0000-4000-8000-000000000404'::uuid,
  '41000000-0000-4000-8000-000000000401'::uuid,
  'rebind-release-identity',
  '41000000-0000-4000-8000-000000000400'::uuid,
  foundation.get_remediation_proposal_sha256_v1(
    foundation.layer41_test_proposal_v1('rebind-release-identity',false)
  ),
  now()
);

reset role;

set local role foundation_remediation_mutator;

select foundation.execute_scoped_remediation_v1(
  '41000000-0000-4000-8000-000000000405'::uuid,
  '41000000-0000-4000-8000-000000000406'::uuid,
  '41000000-0000-4000-8000-000000000404'::uuid,
  foundation.layer41_test_proposal_v1('rebind-release-identity',false),
  now()
);

reset role;


do $layer41_rebind_applied_narrowly$
declare
  v_binding foundation.foundation_release_identity_bindings%rowtype;
  v_status jsonb;
begin
  select * into v_binding
  from foundation.current_foundation_release_identity
  where service_id='foundation.gateway'
    and environment='production';

  if v_binding.foundation_layer<>40
     or v_binding.release_ref<>'foundation:layer-40:bbbbbbbb'
     or v_binding.runtime_version<>'layer41-b' then
    raise exception 'Approved release rebind did not bind runtime B: %',
      row_to_json(v_binding);
  end if;

  if not exists (
    select 1
    from universe.app_registry
    where app_key='foundation'
      and current_layer=40
      and readiness_release_ref='foundation:layer-40:aaaaaaaa'
  ) then
    raise exception 'Release rebind must not silently rewrite registry projection';
  end if;

  if exists (
    select 1
    from universe.readiness_releases
    where app_key='foundation'
      and release_ref='foundation:layer-40:bbbbbbbb'
  ) then
    raise exception 'Release rebind must not silently create Universe release projection';
  end if;

  select foundation.get_remediation_execution_admission_status_v1(
    '41000000-0000-4000-8000-000000000404'::uuid
  ) into v_status;

  if v_status->>'status'<>'consumed'
     or v_status#>>'{consumingExecution,eventType}'<>'executed' then
    raise exception 'Rebind admission must be consumed exactly once: %',v_status;
  end if;
end;
$layer41_rebind_applied_narrowly$;


-- Replay of a consumed admission is denied and cannot mutate again.
set local role foundation_remediation_mutator;

select foundation.execute_scoped_remediation_v1(
  '41000000-0000-4000-8000-000000000407'::uuid,
  '41000000-0000-4000-8000-000000000408'::uuid,
  '41000000-0000-4000-8000-000000000404'::uuid,
  foundation.layer41_test_proposal_v1('rebind-release-identity',false),
  now()
);

reset role;

do $layer41_replay_denied$
declare
  v_count integer;
begin
  select count(*) into v_count
  from foundation.remediation_execution_events
  where admission_id='41000000-0000-4000-8000-000000000404'::uuid
    and event_type='denied'
    and reason_code='remediation-execution-admission-already-consumed';

  if v_count<>1 then
    raise exception 'Consumed execution admission must deny replay';
  end if;
end;
$layer41_replay_denied$;


do $layer41_security$
begin
  if has_function_privilege(
    'service_role',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role must not execute scoped remediation';
  end if;

  if has_function_privilege(
    'foundation_remediation_approver',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) or has_function_privilege(
    'foundation_remediation_executor',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'approval/admission roles must not perform mutation';
  end if;

  if not has_function_privilege(
    'foundation_remediation_mutator',
    'foundation.execute_scoped_remediation_v1(uuid,uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'mutator role must execute scoped remediation function';
  end if;

  if pg_has_role(
    'service_role','foundation_remediation_mutator','MEMBER'
  ) or pg_has_role(
    'foundation_remediation_approver',
    'foundation_remediation_mutator','MEMBER'
  ) or pg_has_role(
    'foundation_remediation_executor',
    'foundation_remediation_mutator','MEMBER'
  ) then
    raise exception 'mutator authority must remain separately held';
  end if;

  if has_table_privilege(
    'foundation_remediation_mutator',
    'universe.app_registry','UPDATE'
  ) or has_table_privilege(
    'foundation_remediation_mutator',
    'universe.readiness_releases','INSERT'
  ) or has_table_privilege(
    'foundation_remediation_mutator',
    'foundation.remediation_execution_events','INSERT'
  ) then
    raise exception 'mutator role must not bypass SECURITY DEFINER executor';
  end if;
end;
$layer41_security$;

rollback;
