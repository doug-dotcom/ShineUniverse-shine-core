begin;

insert into foundation.service_deployment_receipts(
 receipt_id,service_id,environment,provider,runtime_ref,runtime_version,artifact_sha256,
 runtime_state,source_ref,provider_evidence_ref,provider_observed_at,submitted_by,metadata,recorded_at
) values(
 '48000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 'supabase://test','48',repeat('a',64),'active',
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:48',now(),'test','{}',now()
);

insert into foundation.service_deployment_receipt_publications(
 publication_id,publication_key,receipt_id,service_id,environment,provider,runtime_version,
 artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,submitted_by,transport,
 transport_run_id,transport_run_attempt,transport_event,transport_repository,transport_ref,
 transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values(
 '48000000-0000-4000-8000-000000000002',
 'github-oidc:48:1:48000000-0000-4000-8000-000000000001',
 '48000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 '48',repeat('a',64),
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:48','accepted-new','github-actions-oidc','github-oidc','48','1','push',
 'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',
 repeat('4',40),false,'{}',now()
);

insert into foundation.foundation_release_identity_bindings(
 binding_id,release_ref,service_id,environment,foundation_layer,source_ref,runtime_version,
 artifact_sha256,deployment_receipt_id,publication_id,publication_assurance,
 readiness_state_at_bind,readiness_fingerprint_at_bind,bound_by,metadata,bound_at
) values(
 '48000000-0000-4000-8000-000000000003','foundation:layer-47:aaaaaaaa',
 'foundation.gateway','production',47,
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 '48',repeat('a',64),'48000000-0000-4000-8000-000000000001',
 '48000000-0000-4000-8000-000000000002','github-oidc','degraded',repeat('1',32),
 'test','{}',now()
);

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,evidence_fingerprint,
 condition_fingerprint,observed_at
) values(
 '48000000-0000-4000-8000-000000000101','production',
 '48000000-0000-4000-8000-000000000003','foundation:layer-47:aaaaaaaa',
 'degraded',repeat('1',32),'degraded',repeat('2',32),'stable',true,'degraded','degraded',
 '["dependency-degraded"]','["context-operations","protected-operations"]','[]','[]',
 '{"test":"48"}',repeat('2',32),repeat('8',32),now()
);

insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,condition_fingerprint,detection_started_at,persistence_threshold_seconds,
 persistence_seconds,snapshot,occurred_at
) values(
 '48000000-0000-4000-8000-000000000201','production:readiness','production','opened',
 'degraded','stable','warning','["dependency-degraded"]',
 '["context-operations","protected-operations"]','[]','[]',
 '48000000-0000-4000-8000-000000000101',repeat('2',32),repeat('8',32),
 now()-interval '10 minutes',300,600,'{"test":"48"}',now()
);

insert into foundation.readiness_dependency_remediation_proposals(
 proposal_id,environment,readiness_incident_event_id,condition_fingerprint,severity,
 reason_codes,affected_scopes,proposal,proposal_sha256,status,created_at
) values(
 '48000000-0000-4000-8000-000000000301','production',
 '48000000-0000-4000-8000-000000000201',repeat('8',32),'warning',
 '["dependency-degraded"]','["context-operations","protected-operations"]',
 '{"readinessDependencyRemediationProposal":"shine-foundation/readiness-dependency-remediation-proposal-v1","test":"48"}',
 encode(extensions.digest(convert_to('{"test": "48", "readinessDependencyRemediationProposal": "shine-foundation/readiness-dependency-remediation-proposal-v1"}'::jsonb::text,'UTF8'),'sha256'),'hex'),
 'proposed',now()
);

create or replace function foundation.get_readiness_dependency_proposal_status_v1(p_proposal_id uuid)
returns jsonb language sql stable security definer set search_path='' as $s$
 select jsonb_build_object('state','current','usable',true,'integrityVerified',true);
$s$;

set local role service_role;
select foundation.generate_readiness_dependency_remediation_handoff_v1(
 '48000000-0000-4000-8000-000000000301',now()
);
reset role;

do $assert$
declare h foundation.readiness_dependency_remediation_handoffs%rowtype;s jsonb;
begin
 select * into h from foundation.readiness_dependency_remediation_handoffs
 order by handoff_sequence desc limit 1;

 if h.handoff_id is null
    or h.owner_component<>'universe'
    or h.dependency_service_id<>'foundation.defence'
    or jsonb_array_length(h.routed_scopes)<>2
    or h.handoff->>'approvalGranted'<>'false'
    or h.handoff->>'executionAuthorityGranted'<>'false'
    or h.handoff->>'executesAction'<>'false' then
   raise exception 'Layer 48 handoff invalid: %',row_to_json(h);
 end if;

 s:=foundation.get_readiness_dependency_remediation_handoff_status_v1(h.handoff_id);
 if s->>'state'<>'current' or s->>'integrityVerified'<>'true' then
   raise exception 'Layer 48 handoff should be current: %',s;
 end if;
end;
$assert$;

do $security$
begin
 if has_function_privilege(
   'foundation_runtime',
   'foundation.generate_readiness_dependency_remediation_handoff_v1(uuid,timestamptz)',
   'EXECUTE'
 ) then raise exception 'runtime must not generate handoffs'; end if;

 if has_table_privilege(
   'service_role',
   'foundation.readiness_dependency_remediation_handoffs',
   'INSERT'
 ) then raise exception 'service role must not bypass handoff generator'; end if;
end;
$security$;

rollback;
