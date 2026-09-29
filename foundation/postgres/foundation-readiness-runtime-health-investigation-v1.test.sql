begin;

insert into foundation.service_deployment_receipts(
 receipt_id,service_id,environment,provider,runtime_ref,runtime_version,artifact_sha256,
 runtime_state,source_ref,provider_evidence_ref,provider_observed_at,submitted_by,metadata,recorded_at
) values(
 '56000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 'supabase://test','56',repeat('a',64),'active',
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:56',now(),'test','{}',now()
);

insert into foundation.service_deployment_receipt_publications(
 publication_id,publication_key,receipt_id,service_id,environment,provider,runtime_version,
 artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,submitted_by,transport,
 transport_run_id,transport_run_attempt,transport_event,transport_repository,transport_ref,
 transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values(
 '56000000-0000-4000-8000-000000000002',
 'github-oidc:56:1:56000000-0000-4000-8000-000000000001',
 '56000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 '56',repeat('a',64),
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:56','accepted-new','github-actions-oidc','github-oidc','56','1','push',
 'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',
 repeat('5',40),false,'{}',now()
);

insert into foundation.foundation_release_identity_bindings(
 binding_id,release_ref,service_id,environment,foundation_layer,source_ref,runtime_version,
 artifact_sha256,deployment_receipt_id,publication_id,publication_assurance,
 readiness_state_at_bind,readiness_fingerprint_at_bind,bound_by,metadata,bound_at
) values(
 '56000000-0000-4000-8000-000000000003','foundation:layer-55:aaaaaaaa',
 'foundation.gateway','production',55,
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 '56',repeat('a',64),
 '56000000-0000-4000-8000-000000000001',
 '56000000-0000-4000-8000-000000000002',
 'github-oidc','degraded',repeat('1',32),'test','{}',now()
);

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,evidence_fingerprint,
 condition_fingerprint,observed_at
) values(
 '56000000-0000-4000-8000-000000000101','production',
 '56000000-0000-4000-8000-000000000003','foundation:layer-55:aaaaaaaa',
 'degraded',repeat('1',32),'not-ready',repeat('2',32),'not-bindable',true,'blocked','blocked',
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
 '56000000-0000-4000-8000-000000000201','production:readiness','production','changed',
 'not-ready','not-bindable','critical','["runtime-unhealthy"]','[]','[]','[]',
 '56000000-0000-4000-8000-000000000101',repeat('2',32),repeat('9',32),
 now()-interval '10 minutes',300,600,
 '{"current":{"privilegedOperationsMode":"blocked","workerOperationsMode":"blocked"}}',now()
);

create or replace function foundation.evaluate_foundation_readiness_v1(
 p_environment text default 'production',
 p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $layer56_readiness$
 select jsonb_build_object(
   'readinessState','not-ready',
   'reasonCodes',jsonb_build_array('runtime-unhealthy'),
   'privilegedOperationsMode','blocked',
   'workerOperationsMode','blocked',
   'checks',jsonb_build_object(
     'health',jsonb_build_object(
       'state','unhealthy',
       'evidenceRef','test:layer56:health-window',
       'reasonCodes',jsonb_build_array('critical-p95-latency'),
       'runtimeVersion','56'
     ),
     'dependencyRollup',jsonb_build_object(
       'state','operational',
       'serviceEffectiveState','blocked',
       'degradedScopes','[]'::jsonb,
       'guardedScopes','[]'::jsonb,
       'blockedScopes','[]'::jsonb
     )
   )
 );
$layer56_readiness$;

create or replace function foundation.get_service_health_v1(
 p_service_id text,
 p_environment text default 'production'
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $layer56_health$
 select jsonb_build_object(
   'serviceId',p_service_id,
   'environment',p_environment,
   'healthState','unhealthy',
   'reasonCodes',jsonb_build_array('critical-p95-latency'),
   'metrics',jsonb_build_object(
     'runtimeVersion','56',
     'windowStartedAt',now()-interval '55 minutes',
     'windowEndedAt',now()-interval '1 minute',
     'requestCount',12,
     'response4xxCount',0,
     'response5xxCount',0,
     'response5xxRate',0,
     'avgLatencyMs',6500.125,
     'p95LatencyMs',10040.250,
     'runtimeErrorCount',0,
     'evidenceSource','healthcheck',
     'evidenceRef','test:layer56:health-window'
   ),
   'policy',jsonb_build_object(
     'policyVersion','1.1.0',
     'warningP95Ms',5000,
     'criticalP95Ms',10000,
     'warning5xxRate',0.1,
     'critical5xxRate',0.5,
     'warningRuntimeErrorCount',1,
     'criticalRuntimeErrorCount',2,
     'evidenceRef','test:layer56:health-policy'
   )
 );
$layer56_health$;

create or replace function foundation.get_service_deployment_truth_v1(
 p_service_id text,
 p_environment text default 'production'
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $layer56_deployment$
 select jsonb_build_object(
   'truthState','aligned',
   'expected',jsonb_build_object(
     'version','56',
     'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
     'artifactSha256',repeat('a',64)
   ),
   'observed',jsonb_build_object(
     'runtimeVersion','56',
     'observedAt',now()
   )
 );
$layer56_deployment$;

do $layer56_routing$
declare
 dep jsonb;
 runtime jsonb;
 plan jsonb;
begin
 dep:=foundation.evaluate_readiness_incident_response_v1(
   'propose-dependency-remediation','production'
 );
 runtime:=foundation.evaluate_readiness_incident_response_v1(
   'propose-runtime-health-investigation','production'
 );
 plan:=foundation.get_readiness_incident_containment_plan_v1('production');

 if dep->>'decision'<>'not-applicable'
    or dep->>'reasonCode'<>'readiness-incident-not-dependency-caused'
    or dep->>'dependencyCause'<>'false'
    or dep->>'runtimeCause'<>'true'
    or (dep->>'dependencyScopeCount')::integer<>0 then
   raise exception 'Layer 56 dependency routing must reject runtime-only incident: %',dep;
 end if;

 if runtime->>'decision'<>'admit'
    or runtime->>'requiredControl'<>'operator-investigation-proposal'
    or runtime->>'reasonCode'<>'persistent-runtime-health-incident-investigation'
    or runtime->>'runtimeCause'<>'true'
    or runtime->>'dependencyCause'<>'false' then
   raise exception 'Layer 56 runtime investigation routing invalid: %',runtime;
 end if;

 if plan->>'recommendedAction'<>'maintain-safe-mode-and-propose-runtime-health-investigation'
    or plan->>'automaticRuntimeRepair'<>'false'
    or plan->>'releaseRebindAllowedByThisPolicy'<>'false' then
   raise exception 'Layer 56 containment plan invalid: %',plan;
 end if;
end;
$layer56_routing$;

do $layer56_security$
begin
 if not has_function_privilege(
   'service_role',
   'foundation.propose_readiness_runtime_health_investigation_v1(text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'service_role must generate runtime-health investigation proposal'; end if;

 if has_function_privilege(
   'foundation_runtime',
   'foundation.propose_readiness_runtime_health_investigation_v1(text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'foundation_runtime must not generate runtime-health proposal'; end if;

 if has_function_privilege(
   'shine_defence_runtime',
   'foundation.propose_readiness_runtime_health_investigation_v1(text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'Defence must not generate shine-core runtime-health proposal'; end if;

 if has_table_privilege(
   'service_role',
   'foundation.readiness_runtime_health_investigation_proposals',
   'INSERT'
 ) then raise exception 'service_role must not bypass runtime-health proposal generator'; end if;
end;
$layer56_security$;

set local role service_role;

do $layer56_proposal$
declare
 v jsonb;
 replay jsonb;
 s jsonb;
 pid uuid;
 stored_hash text;
begin
 v:=foundation.propose_readiness_runtime_health_investigation_v1(
   'production',now()
 );

 if v->>'proposed'<>'true'
    or v->>'status'<>'generated'
    or v->>'ownerComponent'<>'shine-core'
    or v->>'healthState'<>'unhealthy'
    or v->>'executionAuthorityGranted'<>'false'
    or v->>'approvalGranted'<>'false'
    or v->>'executesRemediation'<>'false'
    or v->'proposal'->>'serviceId'<>'foundation.gateway'
    or v->'proposal'->>'ownerComponent'<>'shine-core'
    or v->'proposal'#>>'{health,metrics,p95LatencyMs}'<>'10040.250'
    or v->'proposal'#>>'{health,policy,criticalP95Ms}'<>'10000'
    or not ((v->'proposal'->'prohibitedWork') ? 'relax-health-thresholds-to-clear-readiness')
    or not ((v->'proposal'->'prohibitedWork') ? 'redeploy-runtime-without-separate-admission')
    or not ((v->'proposal'->'prohibitedWork') ? 'rebind-foundation-release')
    or v->'proposal'->>'readinessChanged'<>'false'
    or v->'proposal'->>'incidentClosurePerformed'<>'false' then
   raise exception 'Layer 56 runtime-health proposal invalid: %',v;
 end if;

 pid:=(v->>'proposalId')::uuid;

 replay:=foundation.propose_readiness_runtime_health_investigation_v1(
   'production',now()
 );

 if replay->>'status'<>'existing'
    or replay->>'proposalId'<>pid::text
    or replay->>'proposalSha256'<>v->>'proposalSha256' then
   raise exception 'Layer 56 proposal replay must preserve first packet: % %',v,replay;
 end if;

 s:=foundation.get_readiness_runtime_health_investigation_proposal_status_v1(pid);

 if s->>'state'<>'current'
    or s->>'usable'<>'true'
    or s->>'integrityVerified'<>'true'
    or s->>'ownerComponent'<>'shine-core'
    or s->>'executionAuthorityGranted'<>'false'
    or s->>'executesRemediation'<>'false' then
   raise exception 'Layer 56 proposal status invalid: %',s;
 end if;

 select encode(
   extensions.digest(convert_to(proposal::text,'UTF8'),'sha256'),
   'hex'
 )
 into stored_hash
 from foundation.readiness_runtime_health_investigation_proposals
 where proposal_id=pid;

 if stored_hash<>v->>'proposalSha256' then
   raise exception 'Layer 56 proposal hash mismatch';
 end if;
end;
$layer56_proposal$;

reset role;

rollback;
