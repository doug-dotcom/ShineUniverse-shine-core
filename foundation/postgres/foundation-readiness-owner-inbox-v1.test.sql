begin;

insert into foundation.service_deployment_receipts(
 receipt_id,service_id,environment,provider,runtime_ref,runtime_version,artifact_sha256,
 runtime_state,source_ref,provider_evidence_ref,provider_observed_at,submitted_by,metadata,recorded_at
) values(
 '50000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 'supabase://test','50',repeat('a',64),'active',
 'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
 'test:50',now(),'test','{}',now()
);

insert into foundation.service_deployment_receipt_publications(
 publication_id,publication_key,receipt_id,service_id,environment,provider,runtime_version,
 artifact_sha256,source_ref,provider_evidence_ref,publication_outcome,submitted_by,transport,
 transport_run_id,transport_run_attempt,transport_event,transport_repository,transport_ref,
 transport_workflow_ref,transport_workflow_sha,rollback,metadata,published_at
) values(
 '50000000-0000-4000-8000-000000000002',
 'github-oidc:50:1:50000000-0000-4000-8000-000000000001',
 '50000000-0000-4000-8000-000000000001','foundation.gateway','production','supabase-edge',
 '50',repeat('a',64),
 'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
 'test:50','accepted-new','github-actions-oidc','github-oidc','50','1','push',
 'doug-dotcom/ShineUniverse-shine-core','refs/heads/main','test/workflow@main',
 repeat('5',40),false,'{}',now()
);

insert into foundation.foundation_release_identity_bindings(
 binding_id,release_ref,service_id,environment,foundation_layer,source_ref,runtime_version,
 artifact_sha256,deployment_receipt_id,publication_id,publication_assurance,
 readiness_state_at_bind,readiness_fingerprint_at_bind,bound_by,metadata,bound_at
) values(
 '50000000-0000-4000-8000-000000000003','foundation:layer-49:bbbbbbbb',
 'foundation.gateway','production',49,
 'github://doug-dotcom/ShineUniverse-shine-core/commit/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
 '50',repeat('a',64),
 '50000000-0000-4000-8000-000000000001',
 '50000000-0000-4000-8000-000000000002',
 'github-oidc','degraded',repeat('1',32),'test','{}',now()
);

insert into foundation.foundation_readiness_drift_observations(
 observation_id,environment,binding_id,release_ref,readiness_state_at_bind,
 readiness_fingerprint_at_bind,current_readiness_state,current_readiness_fingerprint,
 drift_state,deployment_identity_stable,privileged_operations_mode,worker_operations_mode,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,snapshot,evidence_fingerprint,
 condition_fingerprint,observed_at
) values(
 '50000000-0000-4000-8000-000000000101','production',
 '50000000-0000-4000-8000-000000000003','foundation:layer-49:bbbbbbbb',
 'degraded',repeat('1',32),'degraded',repeat('2',32),'stable',true,'degraded','degraded',
 '["dependency-degraded"]','["protected-operations"]','[]','[]',
 '{"test":"50"}',repeat('2',32),repeat('9',32),now()
);

insert into foundation.foundation_readiness_incident_events(
 event_id,incident_key,environment,event_type,readiness_state,drift_state,severity,
 reason_codes,degraded_scopes,guarded_scopes,blocked_scopes,readiness_drift_observation_id,
 evidence_fingerprint,condition_fingerprint,detection_started_at,persistence_threshold_seconds,
 persistence_seconds,snapshot,occurred_at
) values(
 '50000000-0000-4000-8000-000000000201','production:readiness','production','opened',
 'degraded','stable','warning','["dependency-degraded"]','["protected-operations"]','[]','[]',
 '50000000-0000-4000-8000-000000000101',repeat('2',32),repeat('9',32),
 now()-interval '10 minutes',300,600,'{"test":"50"}',now()
);

insert into foundation.readiness_dependency_remediation_proposals(
 proposal_id,environment,readiness_incident_event_id,condition_fingerprint,severity,
 reason_codes,affected_scopes,proposal,proposal_sha256,status,created_at
) values(
 '50000000-0000-4000-8000-000000000301','production',
 '50000000-0000-4000-8000-000000000201',repeat('9',32),'warning',
 '["dependency-degraded"]','["protected-operations"]',
 '{"test":"50-proposal"}',
 encode(extensions.digest(convert_to('{"test": "50-proposal"}'::jsonb::text,'UTF8'),'sha256'),'hex'),
 'proposed',now()
);

insert into foundation.readiness_dependency_remediation_handoffs(
 handoff_id,environment,proposal_id,readiness_incident_event_id,condition_fingerprint,
 proposal_sha256,routing_fingerprint,owner_component,dependency_service_id,routed_scopes,
 handoff,handoff_sha256,created_at
) values(
 '50000000-0000-4000-8000-000000000401','production',
 '50000000-0000-4000-8000-000000000301',
 '50000000-0000-4000-8000-000000000201',repeat('9',32),
 (select proposal_sha256 from foundation.readiness_dependency_remediation_proposals
  where proposal_id='50000000-0000-4000-8000-000000000301'),
 repeat('8',32),'universe','foundation.defence','["protected-operations"]',
 '{"test":"50-handoff","requestedWork":["investigate"],"prohibitedWork":["execute-unapproved-change"]}',
 encode(
   extensions.digest(
     convert_to(
       '{"test":"50-handoff","requestedWork":["investigate"],"prohibitedWork":["execute-unapproved-change"]}'::jsonb::text,
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
   'foundation.get_readiness_dependency_remediation_owner_inbox_v1(text,integer)',
   'EXECUTE'
 ) then raise exception 'service role must not read Defence owner inbox'; end if;

 if has_function_privilege(
   'foundation_runtime',
   'foundation.get_readiness_dependency_remediation_owner_inbox_v1(text,integer)',
   'EXECUTE'
 ) then raise exception 'Foundation runtime must not read Defence owner inbox'; end if;

 if not has_function_privilege(
   'shine_defence_runtime',
   'foundation.get_readiness_dependency_remediation_owner_inbox_v1(text,integer)',
   'EXECUTE'
 ) then raise exception 'Defence runtime must read its owner inbox'; end if;

 if has_table_privilege(
   'shine_defence_runtime',
   'foundation.readiness_dependency_remediation_handoffs',
   'SELECT'
 ) then raise exception 'Defence runtime must not receive direct handoff table SELECT'; end if;
end;
$security$;

set local role shine_defence_runtime;

do $pending$
declare inbox jsonb; item jsonb;
begin
 inbox:=foundation.get_readiness_dependency_remediation_owner_inbox_v1('production',25);
 item:=inbox->'items'->0;

 if (inbox->>'pendingCount')::integer<>1
    or (inbox->>'visibleCount')::integer<>1
    or inbox->>'hasMore'<>'false'
    or item->>'handoffId'<>'50000000-0000-4000-8000-000000000401'
    or item->>'ownerComponent'<>'universe'
    or item->>'dependencyServiceId'<>'foundation.defence'
    or item->>'handoffState'<>'current'
    or item->>'responseState'<>'pending'
    or item->>'integrityVerified'<>'true'
    or item->>'approvalGranted'<>'false'
    or item->>'executionAuthorityGranted'<>'false'
    or item->>'executesAction'<>'false' then
   raise exception 'Layer 50 pending inbox invalid: %',inbox;
 end if;
end;
$pending$;

reset role;

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

do $stale_excluded$
declare inbox jsonb;
begin
 inbox:=foundation.get_readiness_dependency_remediation_owner_inbox_v1('production',25);
 if (inbox->>'pendingCount')::integer<>0
    or jsonb_array_length(inbox->'items')<>0 then
   raise exception 'Stale handoff must not appear in owner inbox: %',inbox;
 end if;
end;
$stale_excluded$;

reset role;

create or replace function foundation.get_readiness_dependency_remediation_handoff_status_v1(
 p_handoff_id uuid
)
returns jsonb language sql stable security definer set search_path='' as $current_again$
 select jsonb_build_object(
   'state','current','usable',true,'integrityVerified',true,
   'handoffId',p_handoff_id,'proposalState','current'
 );
$current_again$;

set local role shine_defence_runtime;

select foundation.respond_readiness_dependency_remediation_handoff_v1(
 '50000000-0000-4000-8000-000000000401',
 'accepted',
 'accepted-for-investigation',
 'Layer 50 confirms the inbox item can flow into the existing owner acknowledgement path.',
 now()
);

do $responded_excluded$
declare inbox jsonb;
begin
 inbox:=foundation.get_readiness_dependency_remediation_owner_inbox_v1('production',25);
 if (inbox->>'pendingCount')::integer<>0
    or jsonb_array_length(inbox->'items')<>0
    or inbox->>'executionAuthorityGranted'<>'false'
    or inbox->>'approvalGranted'<>'false' then
   raise exception 'Acknowledged handoff must leave pending inbox: %',inbox;
 end if;
end;
$responded_excluded$;

reset role;

rollback;
