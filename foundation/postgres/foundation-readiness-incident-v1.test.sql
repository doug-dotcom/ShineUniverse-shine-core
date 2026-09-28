begin;

-- Deterministic observations prove debounce, escalation, change and recovery.
insert into foundation.service_deployment_receipts(
 receipt_id,service_id,environment,provider,runtime_ref,runtime_version,artifact_sha256,
 runtime_state,source_ref,provider_evidence_ref,provider_observed_at,submitted_by,metadata,recorded_at
) values(
 '44000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 'supabase://test','44',repeat('a',64),'active',
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:44',now(),'test','{}',now()
);
insert into foundation.service_deployment_receipt_publications(
 publication_id,publication_key,receipt_id,service_id,environment,provider,runtime_version,
 artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,submitted_by,transport,
 transport_run_id,transport_run_attempt,transport_event,transport_repository,transport_ref,
 transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values(
 '44000000-0000-4000-8000-000000000002','github-oidc:44:1:44000000-0000-4000-8000-000000000001',
 '44000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge','44',
 repeat('a',64),'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:44','accepted-new','github-actions-oidc','github-oidc','44','1','push',
 'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',repeat('4',40),false,'{}',now()
);
insert into foundation.foundation_release_identity_bindings(
 binding_id,release_ref,service_id,environment,foundation_layer,source_ref,runtime_version,
 artifact_sha256,deployment_receipt_id,publication_id,publication_assurance,
 readiness_state_at_bind,readiness_fingerprint_at_bind,bound_by,metadata,bound_at
) values(
 '44000000-0000-4000-8000-000000000003','foundation:layer-43:aaaaaaaa','foundation.gateway','production',43,
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','44',
 repeat('a',64),'44000000-0000-4000-8000-000000000001','44000000-0000-4000-8000-000000000002',
 'github-oidc','ready',repeat('1',32),'test','{}',now()
);

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,readiness_fingerprint_at_bind,
 current_readiness_state,current_readiness_fingerprint,drift_state,deployment_identity_stable,
 privileged_operations_mode,worker_operations_mode,reason_codes,degraded_scopes,guarded_scopes,
 blocked_scopes,snapshot,evidence_fingerprint,observed_at
) values
('44000000-0000-4000-8000-000000000101','production','44000000-0000-4000-8000-000000000003',
 'foundation:layer-43:aaaaaaaa','ready',repeat('1',32),'degraded',repeat('2',32),'operational-degradation',true,
 'degraded','degraded','["dependency-degraded"]','["protected-operations"]','[]','[]','{"test":"degraded"}',repeat('2',32),now()),
('44000000-0000-4000-8000-000000000102','production','44000000-0000-4000-8000-000000000003',
 'foundation:layer-43:aaaaaaaa','ready',repeat('1',32),'not-ready',repeat('3',32),'not-bindable',true,
 'blocked','blocked','["dependency-blocked"]','[]','[]','["protected-operations"]','{"test":"blocked"}',repeat('3',32),now()),
('44000000-0000-4000-8000-000000000103','production','44000000-0000-4000-8000-000000000003',
 'foundation:layer-43:aaaaaaaa','ready',repeat('1',32),'ready',repeat('1',32),'stable',true,
 'normal','normal','[]','[]','[]','[]','{"test":"ready"}',repeat('1',32),now());

do $lifecycle$
declare v jsonb; base timestamptz:=now();
begin
 v:=foundation.transition_foundation_readiness_incident_v1('production','44000000-0000-4000-8000-000000000101',base,300);
 if v->>'eventType'<>'detected' or v->>'watching'<>'true' then raise exception 'First degraded sample must watch: %',v; end if;

 v:=foundation.transition_foundation_readiness_incident_v1('production','44000000-0000-4000-8000-000000000101',base+interval '299 seconds',300);
 if v->>'eventType'<>'none' then raise exception 'Subthreshold degradation must not open: %',v; end if;

 v:=foundation.transition_foundation_readiness_incident_v1('production','44000000-0000-4000-8000-000000000101',base+interval '300 seconds',300);
 if v->>'eventType'<>'opened' or v->>'active'<>'true' or v->>'severity'<>'warning' then raise exception 'Persistent degradation must open warning: %',v; end if;

 v:=foundation.transition_foundation_readiness_incident_v1('production','44000000-0000-4000-8000-000000000102',base+interval '301 seconds',300);
 if v->>'eventType'<>'changed' or v->>'severity'<>'critical' then raise exception 'Blocked readiness must change to critical: %',v; end if;

 v:=foundation.transition_foundation_readiness_incident_v1('production','44000000-0000-4000-8000-000000000103',base+interval '302 seconds',300);
 if v->>'eventType'<>'recovered' or v->>'active'<>'false' then raise exception 'Ready observation must recover: %',v; end if;
end;
$lifecycle$;

do $summary$
declare v jsonb;
begin
 v:=foundation.get_foundation_readiness_incident_summary_v1('production');
 if v->>'state'<>'normal' or v->>'activeIncidentCount'<>'0' or v->>'watchCount'<>'0' then
  raise exception 'Recovered lifecycle must be normal: %',v;
 end if;
end;
$summary$;

rollback;
