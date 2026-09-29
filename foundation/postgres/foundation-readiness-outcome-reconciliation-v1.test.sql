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



do $layer53_security$
begin
  if not has_function_privilege(
    'service_role',
    'foundation.run_readiness_dependency_remediation_evidence_retest_v1(uuid,timestamptz,integer,integer)',
    'EXECUTE'
  ) then raise exception 'service_role must control evidence-triggered retest'; end if;

  if has_function_privilege(
    'shine_defence_runtime',
    'foundation.run_readiness_dependency_remediation_evidence_retest_v1(uuid,timestamptz,integer,integer)',
    'EXECUTE'
  ) then raise exception 'Defence owner must not trigger canonical retest'; end if;

  if has_function_privilege(
    'foundation_runtime',
    'foundation.run_readiness_dependency_remediation_evidence_retest_v1(uuid,timestamptz,integer,integer)',
    'EXECUTE'
  ) then raise exception 'Foundation read runtime must not trigger canonical retest'; end if;

  if has_table_privilege(
    'service_role',
    'foundation.readiness_dependency_remediation_evidence_retests',
    'INSERT'
  ) then raise exception 'service_role must not directly insert retest proof'; end if;

  if has_table_privilege(
    'shine_defence_runtime',
    'foundation.readiness_dependency_remediation_evidence_retests',
    'SELECT'
  ) then raise exception 'Defence must not directly read Foundation retest proof ledger'; end if;
end;
$layer53_security$;

set local role shine_defence_runtime;

select foundation.respond_readiness_dependency_remediation_handoff_v1(
  '52000000-0000-4000-8000-000000000401',
  'accepted',
  'accepted-for-independent-retest-fixture',
  'Owner accepts investigation only; Foundation retains retest authority.',
  now()
);

select foundation.return_readiness_dependency_remediation_evidence_v1(
  '52000000-0000-4000-8000-000000000401',
  'resolved',
  'Owner reports resolved, but this claim must not become readiness truth.',
  jsonb_build_array(
    'Owner-side evidence is current.',
    'Owner-side checks report the routed scope resolved.'
  ),
  jsonb_build_array('test:layer53:owner-evidence'),
  'Foundation should independently retest canonical readiness.',
  now()
);

reset role;

-- Canonical Foundation evidence deliberately remains degraded even though the
-- owner reported "resolved". This proves the owner outcome is not used as truth.
create or replace function foundation.get_foundation_readiness_drift_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $layer53_drift$
  select jsonb_build_object(
    'foundationReadinessDriftResponse','shine-foundation/readiness-drift-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'binding',jsonb_build_object(
      'bindingId','52000000-0000-4000-8000-000000000003',
      'releaseRef','foundation:layer-51:aaaaaaaa',
      'readinessStateAtBind','degraded',
      'readinessFingerprintAtBind',repeat('1',32)
    ),
    'current',jsonb_build_object(
      'readinessState','degraded',
      'readinessFingerprint',repeat('3',32),
      'safeMode','degraded',
      'privilegedOperationsMode','degraded',
      'workerOperationsMode','degraded'
    ),
    'driftState','operational-degradation',
    'deploymentIdentityStable',true,
    'reasonCodes',jsonb_build_array('dependency-degraded'),
    'degradedScopes',jsonb_build_array('protected-operations'),
    'guardedScopes','[]'::jsonb,
    'blockedScopes','[]'::jsonb,
    'requiresReleaseRebind',false,
    'requiresMonitoring',true,
    'privilegedOperationsRestricted',true
  );
$layer53_drift$;

set local role service_role;

do $layer53_run$
declare
  eid uuid;
  first_run jsonb;
  replay jsonb;
begin
  select evidence_return_id into eid
  from foundation.readiness_dependency_remediation_evidence_returns
  where handoff_id='52000000-0000-4000-8000-000000000401';

  first_run:=foundation.run_readiness_dependency_remediation_evidence_retest_v1(
    eid,now(),300,900
  );

  if first_run->>'status'<>'recorded'
     or first_run->>'ownerReportedOutcome'<>'resolved'
     or first_run->>'canonicalReadinessState'<>'degraded'
     or first_run->>'independentRetest'<>'true'
     or first_run->>'ownerOutcomeAcceptedAsReadiness'<>'false'
     or first_run->>'sourceEvidenceUsedAsTriggerOnly'<>'true'
     or first_run->>'readinessChangedByOwnerEvidence'<>'false'
     or first_run->>'approvalGranted'<>'false'
     or first_run->>'executionAuthorityGranted'<>'false'
     or first_run->>'executesRemediation'<>'false' then
    raise exception 'Layer 53 independent retest response invalid: %',first_run;
  end if;

  replay:=foundation.run_readiness_dependency_remediation_evidence_retest_v1(
    eid,now(),300,900
  );

  if replay->>'status'<>'existing'
     or replay->>'evidenceRetestId'<>first_run->>'evidenceRetestId'
     or replay->>'retestCycleId'<>first_run->>'retestCycleId'
     or replay->>'retestProofSha256'<>first_run->>'retestProofSha256'
     or replay->>'canonicalReadinessState'<>'degraded' then
    raise exception 'Layer 53 replay must preserve first canonical retest: % %',
      first_run,replay;
  end if;
end;
$layer53_run$;

reset role;

do $layer53_integrity$
declare
  r foundation.readiness_dependency_remediation_evidence_retests%rowtype;
  c foundation.foundation_readiness_retest_cycles%rowtype;
  expected text;
  s jsonb;
begin
  select * into r
  from foundation.readiness_dependency_remediation_evidence_retests
  limit 1;

  if r.evidence_retest_id is null then
    raise exception 'Layer 53 retest proof missing';
  end if;

  expected:=encode(
    extensions.digest(convert_to(r.retest_proof::text,'UTF8'),'sha256'),
    'hex'
  );

  select * into c
  from foundation.foundation_readiness_retest_cycles
  where cycle_id=r.retest_cycle_id;

  if expected<>r.retest_proof_sha256
     or c.cycle_id is null
     or c.readiness_state<>'degraded'
     or r.owner_reported_outcome<>'resolved'
     or r.canonical_readiness_state<>'degraded' then
    raise exception 'Layer 53 persisted proof invalid';
  end if;

  s:=foundation.get_readiness_dependency_remediation_evidence_retest_status_v1(
    r.evidence_return_id
  );

  if s->>'state'<>'completed'
     or s->>'integrityVerified'<>'true'
     or s->>'ownerReportedOutcome'<>'resolved'
     or s->>'canonicalReadinessState'<>'degraded'
     or s->>'ownerOutcomeAcceptedAsReadiness'<>'false'
     or s->>'independentRetest'<>'true'
     or s->>'executionAuthorityGranted'<>'false' then
    raise exception 'Layer 53 status invalid: %',s;
  end if;
end;
$layer53_integrity$;

do $layer54_classifier$
declare
  v jsonb;
begin
  v:=foundation.classify_readiness_dependency_remediation_outcome_v1(
    'resolved','degraded','ready',repeat('1',32),repeat('2',32)
  );
  if v->>'canonicalOutcome'<>'resolved'
     or v->>'verdict'<>'confirmed' then
    raise exception 'Layer 54 resolved confirmation failed: %',v;
  end if;

  v:=foundation.classify_readiness_dependency_remediation_outcome_v1(
    'improved','not-ready','degraded',repeat('1',32),repeat('2',32)
  );
  if v->>'canonicalOutcome'<>'improved'
     or v->>'verdict'<>'confirmed' then
    raise exception 'Layer 54 improvement confirmation failed: %',v;
  end if;

  v:=foundation.classify_readiness_dependency_remediation_outcome_v1(
    'resolved','degraded','degraded',repeat('1',32),repeat('2',32)
  );
  if v->>'canonicalOutcome'<>'unchanged'
     or v->>'verdict'<>'contradicted'
     or v->>'conditionChanged'<>'true' then
    raise exception 'Layer 54 contradiction classification failed: %',v;
  end if;

  v:=foundation.classify_readiness_dependency_remediation_outcome_v1(
    'inconclusive','degraded','restricted',repeat('1',32),repeat('2',32)
  );
  if v->>'canonicalOutcome'<>'improved'
     or v->>'verdict'<>'unresolved' then
    raise exception 'Layer 54 inconclusive reconciliation failed: %',v;
  end if;
end;
$layer54_classifier$;

do $layer54_security$
begin
  if not has_function_privilege(
    'service_role',
    'foundation.reconcile_readiness_dependency_remediation_outcome_v1(uuid,timestamptz)',
    'EXECUTE'
  ) then raise exception 'service_role must reconcile owner outcome'; end if;

  if has_function_privilege(
    'shine_defence_runtime',
    'foundation.reconcile_readiness_dependency_remediation_outcome_v1(uuid,timestamptz)',
    'EXECUTE'
  ) then raise exception 'Defence owner must not reconcile its own claim'; end if;

  if has_function_privilege(
    'foundation_runtime',
    'foundation.reconcile_readiness_dependency_remediation_outcome_v1(uuid,timestamptz)',
    'EXECUTE'
  ) then raise exception 'Foundation read runtime must not write reconciliation proof'; end if;

  if has_table_privilege(
    'service_role',
    'foundation.readiness_dependency_remediation_outcome_reconciliations',
    'INSERT'
  ) then raise exception 'service_role must not directly insert reconciliation proof'; end if;

  if has_table_privilege(
    'shine_defence_runtime',
    'foundation.readiness_dependency_remediation_outcome_reconciliations',
    'SELECT'
  ) then raise exception 'Defence must not directly read reconciliation ledger'; end if;
end;
$layer54_security$;

set local role service_role;

do $layer54_reconcile$
declare
  erid uuid;
  first_result jsonb;
  replay jsonb;
begin
  select evidence_retest_id into erid
  from foundation.readiness_dependency_remediation_evidence_retests
  limit 1;

  first_result:=
    foundation.reconcile_readiness_dependency_remediation_outcome_v1(
      erid,now()
    );

  if first_result->>'status'<>'recorded'
     or first_result->>'ownerReportedOutcome'<>'resolved'
     or first_result->>'canonicalOutcome'<>'unchanged'
     or first_result->>'verdict'<>'contradicted'
     or first_result->>'readinessChanged'<>'false'
     or first_result->>'incidentClosurePerformed'<>'false'
     or first_result->>'approvalGranted'<>'false'
     or first_result->>'executionAuthorityGranted'<>'false'
     or first_result->>'executesRemediation'<>'false' then
    raise exception 'Layer 54 end-to-end reconciliation invalid: %',first_result;
  end if;

  replay:=
    foundation.reconcile_readiness_dependency_remediation_outcome_v1(
      erid,now()
    );

  if replay->>'status'<>'existing'
     or replay->>'reconciliationId'<>first_result->>'reconciliationId'
     or replay->>'reconciliationSha256'<>first_result->>'reconciliationSha256'
     or replay->>'verdict'<>'contradicted' then
    raise exception 'Layer 54 replay must preserve first reconciliation: % %',
      first_result,replay;
  end if;
end;
$layer54_reconcile$;

reset role;

do $layer54_integrity$
declare
  x foundation.readiness_dependency_remediation_outcome_reconciliations%rowtype;
  expected text;
  s jsonb;
begin
  select * into x
  from foundation.readiness_dependency_remediation_outcome_reconciliations
  limit 1;

  if x.reconciliation_id is null then
    raise exception 'Layer 54 reconciliation proof missing';
  end if;

  expected:=encode(
    extensions.digest(convert_to(x.reconciliation::text,'UTF8'),'sha256'),
    'hex'
  );

  if expected<>x.reconciliation_sha256
     or x.owner_reported_outcome<>'resolved'
     or x.canonical_outcome<>'unchanged'
     or x.verdict<>'contradicted'
     or x.canonical_readiness_state<>'degraded' then
    raise exception 'Layer 54 stored reconciliation invalid';
  end if;

  s:=foundation.get_readiness_dependency_remediation_outcome_reconciliation_status_v1(
    x.evidence_retest_id
  );

  if s->>'state'<>'completed'
     or s->>'integrityVerified'<>'true'
     or s->>'ownerReportedOutcome'<>'resolved'
     or s->>'canonicalOutcome'<>'unchanged'
     or s->>'verdict'<>'contradicted'
     or s->>'readinessChanged'<>'false'
     or s->>'incidentClosurePerformed'<>'false'
     or s->>'executionAuthorityGranted'<>'false' then
    raise exception 'Layer 54 reconciliation status invalid: %',s;
  end if;
end;
$layer54_integrity$;

rollback;
