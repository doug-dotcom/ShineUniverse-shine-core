begin;

-- Layer 51 isolates readiness-cause semantics by stubbing the evidence providers.
create or replace function foundation.get_service_deployment_truth_v1(p_service_id text,p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'truthState','aligned',
    'expected',jsonb_build_object(
      'version',null,
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'artifactSha256',repeat('a',64)
    ),
    'observed',jsonb_build_object('observedAt',now())
  );
$$;

create or replace function foundation.get_service_health_v1(p_service_id text,p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'healthState','unhealthy',
    'reasonCodes',jsonb_build_array('critical-p95-latency'),
    'metrics',jsonb_build_object('runtimeVersion',null,'evidenceRef','test:layer51:health')
  );
$$;

create or replace function foundation.get_dependency_graph_health_v1(p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('state','pass','cycleCount',0);
$$;

create or replace function foundation.get_foundation_dependency_rollup_v1(p_environment text default 'production',p_as_of timestamptz default now())
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'effectiveState','blocked',
    'coreServices',jsonb_build_array(
      jsonb_build_object(
        'serviceId','foundation.gateway',
        'effectiveState','blocked',
        'ownState',jsonb_build_object('operationalState','unhealthy'),
        'dependencies',jsonb_build_array(
          jsonb_build_object(
            'dependencyServiceId','foundation.defence',
            'impactScope','protected-operations',
            'impact','none'
          )
        ),
        'blockedScopes','[]'::jsonb,
        'guardedScopes','[]'::jsonb,
        'degradedScopes','[]'::jsonb
      )
    )
  );
$$;

create or replace function foundation.get_gateway_operation_registry_health_v1(p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('state','pass','routeCount',42,'invalidContractCount',0);
$$;

create or replace function foundation.get_gateway_operation_policy_coverage_v1(p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'state','pass','privilegedOperationCount',26,'coveredOperationCount',26,
    'missingPolicyCount',0,'missingAdmissionBindingCount',0,'missingDependencyScopeCount',0
  );
$$;

create or replace function foundation.get_gateway_operation_audit_health_v1(p_environment text default 'production',p_stale_after_seconds integer default 300)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('state','pass','openTraceCount',0,'brokenChainCount',0);
$$;

create or replace function foundation.get_service_native_state_v1(p_service_id text,p_environment text default 'production',p_as_of timestamptz default now())
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'operationalState','operational',
    'sourceEvidenceRef','test:layer51:defence',
    'sourceState',jsonb_build_object('observedAt',now(),'validUntil',now()+interval '1 hour')
  );
$$;

do $runtime_only$
declare v jsonb;
begin
  v:=foundation.evaluate_foundation_readiness_v1('production',now());

  if v->>'readinessState'<>'not-ready'
     or not (v->'reasonCodes' ? 'runtime-unhealthy')
     or (v->'reasonCodes' ? 'dependency-blocked')
     or v#>>'{checks,dependencyRollup,state}'<>'operational'
     or v#>>'{checks,dependencyRollup,serviceEffectiveState}'<>'blocked'
     or jsonb_array_length(v#>'{checks,dependencyRollup,blockedScopes}')<>0 then
    raise exception 'Layer 51 runtime/dependency cause separation failed: %',v;
  end if;
end;
$runtime_only$;

-- A real dependency-edge block must still remain a dependency block.
create or replace function foundation.get_service_health_v1(p_service_id text,p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'healthState','operational',
    'reasonCodes','[]'::jsonb,
    'metrics',jsonb_build_object('runtimeVersion',null,'evidenceRef','test:layer51:healthy')
  );
$$;

create or replace function foundation.get_foundation_dependency_rollup_v1(p_environment text default 'production',p_as_of timestamptz default now())
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'effectiveState','blocked',
    'coreServices',jsonb_build_array(
      jsonb_build_object(
        'serviceId','foundation.gateway',
        'effectiveState','blocked',
        'ownState',jsonb_build_object('operationalState','operational'),
        'dependencies',jsonb_build_array(
          jsonb_build_object(
            'dependencyServiceId','foundation.defence',
            'impactScope','protected-operations',
            'impact','blocked'
          )
        ),
        'blockedScopes',jsonb_build_array('protected-operations'),
        'guardedScopes','[]'::jsonb,
        'degradedScopes','[]'::jsonb
      )
    )
  );
$$;

do $real_dependency$
declare v jsonb;
begin
  v:=foundation.evaluate_foundation_readiness_v1('production',now());

  if v->>'readinessState'<>'not-ready'
     or not (v->'reasonCodes' ? 'dependency-blocked')
     or (v->'reasonCodes' ? 'runtime-unhealthy')
     or v#>>'{checks,dependencyRollup,state}'<>'blocked'
     or not (v#>'{checks,dependencyRollup,blockedScopes}' ? 'protected-operations') then
    raise exception 'Layer 51 real dependency block semantics failed: %',v;
  end if;
end;
$real_dependency$;

-- Dependency proposal must fail closed as "not applicable" rather than throwing
-- when an active readiness incident has no dependency scopes.
insert into foundation.service_deployment_receipts(
 receipt_id,service_id,environment,provider,runtime_ref,runtime_version,artifact_sha256,
 runtime_state,source_ref,provider_evidence_ref,provider_observed_at,submitted_by,metadata,recorded_at
) values(
 '51000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 'supabase://test','51',repeat('a',64),'active',
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:51',now(),'test','{}',now()
);

insert into foundation.service_deployment_receipt_publications(
 publication_id,publication_key,receipt_id,service_id,environment,provider,runtime_version,
 artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,submitted_by,transport,
 transport_run_id,transport_run_attempt,transport_event,transport_repository,transport_ref,
 transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values(
 '51000000-0000-4000-8000-000000000002',
 'github-oidc:51:1:51000000-0000-4000-8000-000000000001',
 '51000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 '51',repeat('a',64),
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:51','accepted-new','github-actions-oidc','github-oidc','51','1','push',
 'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',
 repeat('5',40),false,'{}',now()
);

insert into foundation.foundation_release_identity_bindings(
 binding_id,release_ref,service_id,environment,foundation_layer,source_ref,runtime_version,
 artifact_sha256,deployment_receipt_id,publication_id,publication_assurance,
 readiness_state_at_bind,readiness_fingerprint_at_bind,bound_by,metadata,bound_at
) values(
 '51000000-0000-4000-8000-000000000003','foundation:layer-50:aaaaaaaa',
 'foundation.gateway','production',50,
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 '51',repeat('a',64),
 '51000000-0000-4000-8000-000000000001',
 '51000000-0000-4000-8000-000000000002',
 'github-oidc','degraded',repeat('1',32),'test','{}',now()
);

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,evidence_fingerprint,
 condition_fingerprint,observed_at
) values(
 '51000000-0000-4000-8000-000000000101','production',
 '51000000-0000-4000-8000-000000000003','foundation:layer-50:aaaaaaaa',
 'degraded',repeat('1',32),'not-ready',repeat('2',32),'stable',true,'blocked','blocked',
 '["runtime-unhealthy"]','[]','[]','[]',
 '{"current":{"privilegedOperationsMode":"blocked","workerOperationsMode":"blocked"}}',
 repeat('2',32),repeat('9',32),now()
);

insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,condition_fingerprint,detection_started_at,persistence_threshold_seconds,
 persistence_seconds,snapshot,occurred_at
) values(
 '51000000-0000-4000-8000-000000000201','production:readiness','production','changed',
 'not-ready','stable','critical','["runtime-unhealthy"]','[]','[]','[]',
 '51000000-0000-4000-8000-000000000101',repeat('2',32),repeat('9',32),
 now()-interval '10 minutes',300,600,
 '{"current":{"privilegedOperationsMode":"blocked","workerOperationsMode":"blocked"}}',now()
);

create or replace function foundation.evaluate_readiness_incident_response_v1(p_action_key text,p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('decision','admit');
$$;

do $no_dependency_scope$
declare v jsonb;
begin
  v:=foundation.propose_readiness_dependency_remediation_v1('production',now());

  if v->>'proposed'<>'false'
     or v->>'status'<>'not-applicable'
     or v->>'reasonCode'<>'readiness-remediation-no-dependency-scopes'
     or v->>'executionAuthorityGranted'<>'false'
     or v->>'approvalGranted'<>'false' then
    raise exception 'Layer 51 no-scope dependency proposal must be non-applicable: %',v;
  end if;
end;
$no_dependency_scope$;

rollback;
