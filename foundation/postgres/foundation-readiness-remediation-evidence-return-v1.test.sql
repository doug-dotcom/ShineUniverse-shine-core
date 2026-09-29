begin;

insert into foundation.service_deployment_receipts(
 receipt_id,service_id,environment,provider,runtime_ref,runtime_version,artifact_sha256,
 runtime_state,source_ref,provider_evidence_ref,provider_observed_at,submitted_by,metadata,recorded_at
) values(
 '52000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 'supabase://test','52',repeat('a',64),'active',
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:52',now(),'test','{}',now()
);

insert into foundation.service_deployment_receipt_publications(
 publication_id,publication_key,receipt_id,service_id,environment,provider,runtime_version,
 artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,submitted_by,transport,
 transport_run_id,transport_run_attempt,transport_event,transport_repository,transport_ref,
 transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values(
 '52000000-0000-4000-8000-000000000002',
 'github-oidc:52:1:52000000-0000-4000-8000-000000000001',
 '52000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 '52',repeat('a',64),
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 'test:52','accepted-new','github-actions-oidc','github-oidc','52','1','push',
 'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',
 repeat('5',40),false,'{}',now()
);

insert into foundation.foundation_release_identity_bindings(
 binding_id,release_ref,service_id,environment,foundation_layer,source_ref,runtime_version,
 artifact_sha256,deployment_receipt_id,publication_id,publication_assurance,
 readiness_state_at_bind,readiness_fingerprint_at_bind,bound_by,metadata,bound_at
) values(
 '52000000-0000-4000-8000-000000000003','foundation:layer-51:aaaaaaaa',
 'foundation.gateway','production',51,
 'github://doug-dotcom/ShineUniverse-shine-core/commit/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
 '52',repeat('a',64),
 '52000000-0000-4000-8000-000000000001',
 '52000000-0000-4000-8000-000000000002',
 'github-oidc','degraded',repeat('1',32),'test','{}',now()
);

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,evidence_fingerprint,
 condition_fingerprint,observed_at
) values(
 '52000000-0000-4000-8000-000000000101','production',
 '52000000-0000-4000-8000-000000000003','foundation:layer-51:aaaaaaaa',
 'degraded',repeat('1',32),'degraded',repeat('2',32),'stable',true,'degraded','degraded',
 '["dependency-degraded"]','["protected-operations"]','[]','[]',
 '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}',
 repeat('2',32),repeat('9',32),now()
);

insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,condition_fingerprint,detection_started_at,persistence_threshold_seconds,
 persistence_seconds,snapshot,occurred_at
) values(
 '52000000-0000-4000-8000-000000000201','production:readiness','production','opened',
 'degraded','stable','warning','["dependency-degraded"]','["protected-operations"]','[]','[]',
 '52000000-0000-4000-8000-000000000101',repeat('2',32),repeat('9',32),
 now()-interval '10 minutes',300,600,
 '{"current":{"privilegedOperationsMode":"degraded","workerOperationsMode":"degraded"}}',now()
);

insert into foundation.readiness_dependency_remediation_proposals(
 proposal_id,environment,readiness_incident_event_id,condition_fingerprint,severity,
 reason_codes,affected_scopes,proposal,proposal_sha256,status,created_at
) values(
 '52000000-0000-4000-8000-000000000301','production',
 '52000000-0000-4000-8000-000000000201',repeat('9',32),'warning',
 '["dependency-degraded"]','["protected-operations"]',
 '{"test":"52-proposal"}',
 encode(extensions.digest(convert_to('{"test": "52-proposal"}'::jsonb::text,'UTF8'),'sha256'),'hex'),
 'proposed',now()
);

insert into foundation.readiness_dependency_remediation_handoffs(
 handoff_id,environment,proposal_id,readiness_incident_event_id,condition_fingerprint,
 proposal_sha256,routing_fingerprint,owner_component,dependency_service_id,routed_scopes,
 handoff,handoff_sha256,created_at
) values(
 '52000000-0000-4000-8000-000000000401','production',
 '52000000-0000-4000-8000-000000000301',
 '52000000-0000-4000-8000-000000000201',repeat('9',32),
 (select proposal_sha256 from foundation.readiness_dependency_remediation_proposals
  where proposal_id='52000000-0000-4000-8000-000000000301'),
 repeat('8',32),'universe','foundation.defence','["protected-operations"]',
 '{"test":"52-handoff","requestedWork":["investigate","return-fresh-evidence"],"prohibitedWork":["execute-unapproved-change"]}',
 encode(
   extensions.digest(
     convert_to(
       '{"test":"52-handoff","requestedWork":["investigate","return-fresh-evidence"],"prohibitedWork":["execute-unapproved-change"]}'::jsonb::text,
       'UTF8'
     ),
     'sha256'
   ),
   'hex'
 ),
 now()
);

create or replace function foundation.get_readiness_dependency_remediation_handoff_status_v1(
 p_handoff_id uuid
)
returns jsonb language sql stable security definer set search_path='' as $current$
 select jsonb_build_object(
   'state','current','usable',true,'integrityVerified',true,
   'handoffId',p_handoff_id,'proposalState','current'
 );
$current$;

do $security$
begin
 if has_function_privilege(
   'service_role',
   'foundation.return_readiness_dependency_remediation_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'service role must not return Defence evidence'; end if;

 if has_function_privilege(
   'foundation_runtime',
   'foundation.return_readiness_dependency_remediation_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'Foundation runtime must not return Defence evidence'; end if;

 if not has_function_privilege(
   'shine_defence_runtime',
   'foundation.return_readiness_dependency_remediation_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
   'EXECUTE'
 ) then raise exception 'Defence runtime must return its evidence'; end if;

 if has_table_privilege(
   'shine_defence_runtime',
   'foundation.readiness_dependency_remediation_evidence_returns',
   'INSERT'
 ) then raise exception 'Defence runtime must not directly insert evidence rows'; end if;

 if has_table_privilege(
   'shine_defence_runtime',
   'foundation.readiness_dependency_remediation_evidence_returns',
   'SELECT'
 ) then raise exception 'Defence runtime must not directly read evidence ledger'; end if;
end;
$security$;

set local role shine_defence_runtime;

select foundation.respond_readiness_dependency_remediation_handoff_v1(
 '52000000-0000-4000-8000-000000000401',
 'accepted',
 'accepted-for-investigation',
 'Layer 52 fixture accepts investigation and evidence return only.',
 now()
);

do $return_and_replay$
declare first_return jsonb; second_return jsonb;
begin
 first_return:=foundation.return_readiness_dependency_remediation_evidence_v1(
   '52000000-0000-4000-8000-000000000401',
   'improved',
   'Defence collected fresh evidence and reports improvement; Foundation must independently retest.',
   jsonb_build_array(
     'Defence posture evidence is current.',
     'The routed dependency scope shows improved owner-side evidence.'
   ),
   jsonb_build_array('test:layer52:defence-posture','test:layer52:dependency-proof'),
   'Run an independent Foundation semantic readiness retest.',
   now()
 );

 if first_return->>'status'<>'recorded'
    or first_return->>'ownerReportedOutcome'<>'improved'
    or first_return->>'requiresIndependentRetest'<>'true'
    or first_return->>'readinessChanged'<>'false'
    or first_return->>'approvalGranted'<>'false'
    or first_return->>'executionAuthorityGranted'<>'false'
    or first_return->>'executesAction'<>'false' then
   raise exception 'Layer 52 evidence return invalid: %',first_return;
 end if;

 second_return:=foundation.return_readiness_dependency_remediation_evidence_v1(
   '52000000-0000-4000-8000-000000000401',
   'resolved',
   'A replay must not replace the authoritative first return.',
   jsonb_build_array('replay'),
   '[]'::jsonb,
   null,
   now()
 );

 if second_return->>'status'<>'existing'
    or second_return->>'evidenceReturnId'<>first_return->>'evidenceReturnId'
    or second_return->>'evidenceReturnSha256'<>first_return->>'evidenceReturnSha256'
    or second_return->>'ownerReportedOutcome'<>'improved' then
   raise exception 'Layer 52 replay must preserve first evidence: % %',first_return,second_return;
 end if;
end;
$return_and_replay$;

do $status_current$
declare s jsonb;
begin
 s:=foundation.get_readiness_dependency_remediation_evidence_return_status_v1(
   '52000000-0000-4000-8000-000000000401'
 );

 if s->>'state'<>'current'
    or s->>'integrityVerified'<>'true'
    or s->>'ownerReportedOutcome'<>'improved'
    or s->>'requiresIndependentRetest'<>'true'
    or s->>'readinessChanged'<>'false'
    or s->>'approvalGranted'<>'false'
    or s->>'executionAuthorityGranted'<>'false'
    or s->>'executesAction'<>'false' then
   raise exception 'Layer 52 current status invalid: %',s;
 end if;
end;
$status_current$;

reset role;

do $integrity$
declare stored foundation.readiness_dependency_remediation_evidence_returns%rowtype;
 expected text;
begin
 select * into stored
 from foundation.readiness_dependency_remediation_evidence_returns
 where handoff_id='52000000-0000-4000-8000-000000000401';

 expected:=encode(
   extensions.digest(convert_to(stored.evidence_return::text,'UTF8'),'sha256'),
   'hex'
 );

 if stored.evidence_return_sha256<>expected
    or stored.owner_reported_outcome<>'improved'
    or stored.response_id is null then
   raise exception 'Layer 52 stored evidence integrity invalid';
 end if;
end;
$integrity$;

create or replace function foundation.get_readiness_dependency_remediation_handoff_status_v1(
 p_handoff_id uuid
)
returns jsonb language sql stable security definer set search_path='' as $stale$
 select jsonb_build_object(
   'state','stale','usable',false,'integrityVerified',true,
   'handoffId',p_handoff_id,'proposalState','stale'
 );
$stale$;

set local role shine_defence_runtime;

do $stale_status$
declare s jsonb;
begin
 s:=foundation.get_readiness_dependency_remediation_evidence_return_status_v1(
   '52000000-0000-4000-8000-000000000401'
 );

 if s->>'state'<>'stale'
    or s->>'integrityVerified'<>'true'
    or s->>'readinessChanged'<>'false'
    or s->>'executionAuthorityGranted'<>'false' then
   raise exception 'Layer 52 evidence must stale with handoff: %',s;
 end if;
end;
$stale_status$;

rollback;
