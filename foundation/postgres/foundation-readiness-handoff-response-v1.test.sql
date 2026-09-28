begin;

-- Minimal valid provenance chain for one Defence-addressed handoff.
insert into foundation.service_deployment_receipts(
 receipt_id,service_id,environment,provider,runtime_ref,runtime_version,artifact_sha256,
 runtime_state,source_ref,provider_evidence_ref,provider_observed_at,submitted_by,metadata,recorded_at
) values(
 '49000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 'supabase://test','49',repeat('a',64),'active',
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:49',now(),'test','{}',now()
);

insert into foundation.service_deployment_receipt_publications(
 publication_id,publication_key,receipt_id,service_id,environment,provider,runtime_version,
 artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,submitted_by,transport,
 transport_run_id,transport_run_attempt,transport_event,transport_repository,transport_ref,
 transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values(
 '49000000-0000-4000-8000-000000000002',
 'github-oidc:49:1:49000000-0000-4000-8000-000000000001',
 '49000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 '49',repeat('a',64),
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:49','accepted-new','github-actions-oidc','github-oidc','49','1','push',
 'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',
 repeat('4',40),false,'{}',now()
);

insert into foundation.foundation_release_identity_bindings(
 binding_id,release_ref,service_id,environment,foundation_layer,source_ref,runtime_version,
 artifact_sha256,deployment_receipt_id,publication_id,publication_assurance,
 readiness_state_at_bind,readiness_fingerprint_at_bind,bound_by,metadata,bound_at
) values(
 '49000000-0000-4000-8000-000000000003','foundation:layer-48:aaaaaaaa',
 'foundation.gateway','production',48,
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 '49',repeat('a',64),
 '49000000-0000-4000-8000-000000000001',
 '49000000-0000-4000-8000-000000000002',
 'github-oidc','degraded',repeat('1',32),'test','{}',now()
);

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,evidence_fingerprint,
 condition_fingerprint,observed_at
) values(
 '49000000-0000-4000-8000-000000000101','production',
 '49000000-0000-4000-8000-000000000003','foundation:layer-48:aaaaaaaa',
 'degraded',repeat('1',32),'degraded',repeat('2',32),'stable',true,'degraded','degraded',
 '["dependency-degraded"]','["protected-operations"]','[]','[]',
 '{"test":"49"}',repeat('2',32),repeat('9',32),now()
);

insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,condition_fingerprint,detection_started_at,persistence_threshold_seconds,
 persistence_seconds,snapshot,occurred_at
) values(
 '49000000-0000-4000-8000-000000000201','production:readiness','production','opened',
 'degraded','stable','warning','["dependency-degraded"]','["protected-operations"]','[]','[]',
 '49000000-0000-4000-8000-000000000101',repeat('2',32),repeat('9',32),
 now()-interval '10 minutes',300,600,'{"test":"49"}',now()
);

insert into foundation.readiness_dependency_remediation_proposals(
 proposal_id,environment,readiness_incident_event_id,condition_fingerprint,severity,
 reason_codes,affected_scopes,proposal,proposal_sha256,status,created_at
) values(
 '49000000-0000-4000-8000-000000000301','production',
 '49000000-0000-4000-8000-000000000201',repeat('9',32),'warning',
 '["dependency-degraded"]','["protected-operations"]',
 '{"test":"49-proposal"}',
 encode(extensions.digest(convert_to('{"test": "49-proposal"}'::jsonb::text,'UTF8'),'sha256'),'hex'),
 'proposed',now()
);

insert into foundation.readiness_dependency_remediation_handoffs(
 handoff_id,environment,proposal_id,readiness_incident_event_id,condition_fingerprint,
 proposal_sha256,routing_fingerprint,owner_component,dependency_service_id,routed_scopes,
 handoff,handoff_sha256,created_at
) values(
 '49000000-0000-4000-8000-000000000401','production',
 '49000000-0000-4000-8000-000000000301',
 '49000000-0000-4000-8000-000000000201',repeat('9',32),
 (select proposal_sha256 from foundation.readiness_dependency_remediation_proposals
  where proposal_id='49000000-0000-4000-8000-000000000301'),
 repeat('8',32),'universe','foundation.defence','["protected-operations"]',
 '{"test":"49-handoff"}',
 encode(extensions.digest(convert_to('{"test": "49-handoff"}'::jsonb::text,'UTF8'),'sha256'),'hex'),
 now()
);

-- Isolate acknowledgement semantics from Layer-48 routing internals.
create or replace function foundation.get_readiness_dependency_remediation_handoff_status_v1(
 p_handoff_id uuid
)
returns jsonb language sql stable security definer set search_path='' as $current$
 select jsonb_build_object(
   'state','current','usable',true,'integrityVerified',true,
   'handoffId',p_handoff_id,'proposalState','current'
 );
$current$;

do $security_before$
begin
 if has_function_privilege(
   'service_role',
   'foundation.respond_readiness_dependency_remediation_handoff_v1(uuid,text,text,text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'service role must not acknowledge Defence handoff'; end if;

 if has_function_privilege(
   'foundation_runtime',
   'foundation.respond_readiness_dependency_remediation_handoff_v1(uuid,text,text,text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'Foundation runtime must not acknowledge Defence handoff'; end if;

 if not has_function_privilege(
   'shine_defence_runtime',
   'foundation.respond_readiness_dependency_remediation_handoff_v1(uuid,text,text,text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'Defence runtime must be able to acknowledge its handoff'; end if;
end;
$security_before$;

set local role shine_defence_runtime;

select foundation.respond_readiness_dependency_remediation_handoff_v1(
 '49000000-0000-4000-8000-000000000401',
 'accepted',
 'accepted-for-investigation',
 'Defence accepted ownership for investigation and fresh-evidence return only.',
 now()
);

reset role;

do $accepted$
declare r foundation.readiness_dependency_remediation_handoff_responses%rowtype;s jsonb;h text;
begin
 select * into r from foundation.readiness_dependency_remediation_handoff_responses
 where handoff_id='49000000-0000-4000-8000-000000000401';

 h:=encode(extensions.digest(convert_to(r.response::text,'UTF8'),'sha256'),'hex');

 if r.response_id is null
    or r.response_state<>'accepted'
    or r.dependency_service_id<>'foundation.defence'
    or r.owner_component<>'universe'
    or r.response_sha256<>h
    or r.response->>'acknowledgesOwnership'<>'true'
    or r.response->>'executionAuthorityGranted'<>'false'
    or r.response->>'approvalGranted'<>'false'
    or r.response->>'executesAction'<>'false' then
   raise exception 'Layer 49 acceptance receipt invalid: %',row_to_json(r);
 end if;

 s:=foundation.get_readiness_dependency_remediation_handoff_response_status_v1(r.handoff_id);
 if s->>'state'<>'accepted'
    or s->>'integrityVerified'<>'true'
    or s->>'acknowledgesOwnership'<>'true'
    or s->>'executionAuthorityGranted'<>'false' then
   raise exception 'Accepted response status invalid: %',s;
 end if;
end;
$accepted$;

-- Response is single-use/idempotent.
set local role shine_defence_runtime;
do $repeat$
declare v jsonb;
begin
 v:=foundation.respond_readiness_dependency_remediation_handoff_v1(
   '49000000-0000-4000-8000-000000000401',
   'rejected',
   'second-response-forbidden',
   null,
   now()
 );
 if v->>'status'<>'existing'
    or v->>'responseState'<>'accepted' then
   raise exception 'Existing response must remain authoritative: %',v;
 end if;
end;
$repeat$;
reset role;

-- A later stale handoff makes the accepted response stale too.
create or replace function foundation.get_readiness_dependency_remediation_handoff_status_v1(
 p_handoff_id uuid
)
returns jsonb language sql stable security definer set search_path='' as $stale$
 select jsonb_build_object(
   'state','stale','usable',false,'integrityVerified',true,
   'handoffId',p_handoff_id,'proposalState','stale'
 );
$stale$;

do $stale_status$
declare s jsonb;
begin
 s:=foundation.get_readiness_dependency_remediation_handoff_response_status_v1(
   '49000000-0000-4000-8000-000000000401'
 );
 if s->>'state'<>'stale'
    or s->>'executionAuthorityGranted'<>'false' then
   raise exception 'Acknowledgement must stale with its handoff: %',s;
 end if;
end;
$stale_status$;

rollback;
