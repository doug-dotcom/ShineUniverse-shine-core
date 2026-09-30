begin;

-- One Layer-74 source incident is enough to bind the synthetic Layer-76 receipts.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '77000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '10 minutes',300,600,'{"test":"layer77"}'::jsonb,
  now()-interval '5 minutes','test:layer77:case-audit-incident'
);

-- A real Layer-73 observation that one execution receipt can prove.
insert into foundation.foundation_promoted_release_case_audit_observations(
  observation_id,environment,audit_state,structural_integrity_pass,incident_state,
  active_incident_event_id,active_incident_handoff_state,case_count,invalid_count,
  active_case_count,pending_case_count,terminal_case_count,historical_case_count,
  semantic_fingerprint,changed_from_previous,snapshot,observed_at
)
values(
  '77000000-0000-4000-8000-000000000010'::uuid,
  'production','idle',true,'normal',null,'not-required',
  0,0,0,0,0,0,repeat('b',64),false,
  '{"overallState":"idle","test":"layer77"}'::jsonb,now()-interval '2 minutes'
);

-- Promotion-trust incident needed by the durable Layer-67 handoff rows.
insert into foundation.foundation_promoted_release_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,promoted_release_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '77000000-0000-4000-8000-000000000020'::uuid,
  'production:promoted_release_trust','production',
  'promoted_release_trust','opened','hold','critical',
  'promoted-release-hold',repeat('c',64),null,
  now()-interval '10 minutes',300,600,'{"test":"layer77"}'::jsonb,
  now()-interval '5 minutes','test:layer77:promotion-incident'
);

do $l77_seed_handoffs_and_receipts$
declare
  handoff_doc_ok jsonb;
  handoff_hash_ok text;
  handoff_doc_bad jsonb;
  handoff_hash_bad text;
begin
  handoff_doc_ok:=jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoff',
      'shine-foundation/promoted-release-owner-handoff-v1',
    'schemaVersion','1.0.0',
    'handoffId','77000000-0000-4000-8000-000000000030',
    'test','layer77-ok'
  );
  handoff_hash_ok:=encode(
    extensions.digest(convert_to(handoff_doc_ok::text,'UTF8'),'sha256'),'hex'
  );

  insert into foundation.foundation_promoted_release_owner_handoffs(
    handoff_id,environment,incident_event_id,incident_evidence_fingerprint,
    incident_state,cause_class,source_domain,response_plan_fingerprint,
    owner_service_id,owner_component,requested_actions,handoff,handoff_sha256,
    created_at
  )
  values(
    '77000000-0000-4000-8000-000000000030'::uuid,
    'production','77000000-0000-4000-8000-000000000020'::uuid,repeat('c',64),
    'critical','case-chain-gap','foundation',''||repeat('d',64),
    'foundation.gateway','test-owner','[]'::jsonb,handoff_doc_ok,handoff_hash_ok,
    now()-interval '2 minutes'
  );

  handoff_doc_bad:=jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoff',
      'shine-foundation/promoted-release-owner-handoff-v1',
    'schemaVersion','1.0.0',
    'handoffId','77000000-0000-4000-8000-000000000031',
    'test','layer77-mismatch'
  );
  handoff_hash_bad:=encode(
    extensions.digest(convert_to(handoff_doc_bad::text,'UTF8'),'sha256'),'hex'
  );

  insert into foundation.foundation_promoted_release_owner_handoffs(
    handoff_id,environment,incident_event_id,incident_evidence_fingerprint,
    incident_state,cause_class,source_domain,response_plan_fingerprint,
    owner_service_id,owner_component,requested_actions,handoff,handoff_sha256,
    created_at
  )
  values(
    '77000000-0000-4000-8000-000000000031'::uuid,
    'production','77000000-0000-4000-8000-000000000020'::uuid,repeat('c',64),
    'critical','case-chain-gap','foundation',repeat('e',64),
    'foundation.gateway','test-owner','[]'::jsonb,handoff_doc_bad,handoff_hash_bad,
    now()-interval '2 minutes'
  );

  -- Verified observation.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  )
  values(
    '77000000-0000-4000-8000-000000000101'::uuid,'production',
    '77000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('1',64),'executed','test-layer77-observation-executed',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
    jsonb_build_object(
      'foundationPromotedReleaseCaseAuditObservationRecord',
        'shine-foundation/promoted-release-case-audit-observation-record-v1',
      'schemaVersion','1.0.0','environment','production',
      'status','recorded-heartbeat',
      'observationId','77000000-0000-4000-8000-000000000010',
      'semanticFingerprint',repeat('b',64)
    ),
    '{}'::jsonb,now()-interval '1 minute'
  );

  -- Missing observation.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  )
  values(
    '77000000-0000-4000-8000-000000000102'::uuid,'production',
    '77000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('2',64),'executed','test-layer77-observation-missing',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
    jsonb_build_object(
      'foundationPromotedReleaseCaseAuditObservationRecord',
        'shine-foundation/promoted-release-case-audit-observation-record-v1',
      'schemaVersion','1.0.0','environment','production',
      'status','recorded-heartbeat',
      'observationId','77000000-0000-4000-8000-000000000099',
      'semanticFingerprint',repeat('b',64)
    ),
    '{}'::jsonb,now()-interval '1 minute'
  );

  -- Observation row exists but action-result fingerprint does not match.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  )
  values(
    '77000000-0000-4000-8000-000000000103'::uuid,'production',
    '77000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('3',64),'executed','test-layer77-observation-mismatch',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
    jsonb_build_object(
      'foundationPromotedReleaseCaseAuditObservationRecord',
        'shine-foundation/promoted-release-case-audit-observation-record-v1',
      'schemaVersion','1.0.0','environment','production',
      'status','recorded-heartbeat',
      'observationId','77000000-0000-4000-8000-000000000010',
      'semanticFingerprint',repeat('f',64)
    ),
    '{}'::jsonb,now()-interval '1 minute'
  );

  -- Verified handoff.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  )
  values(
    '77000000-0000-4000-8000-000000000104'::uuid,'production',
    '77000000-0000-4000-8000-000000000001'::uuid,
    'materialise-current-owner-handoff','case-chain-gap',
    repeat('4',64),'executed','test-layer77-handoff-executed',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
    jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponse',
        'shine-foundation/promoted-release-owner-handoff-response-v1',
      'schemaVersion','1.0.0','environment','production',
      'status','generated',
      'handoffId','77000000-0000-4000-8000-000000000030',
      'incidentEventId','77000000-0000-4000-8000-000000000020',
      'ownerServiceId','foundation.gateway',
      'ownerComponent','test-owner',
      'responsePlanFingerprint',repeat('d',64),
      'handoffSha256',handoff_hash_ok
    ),
    '{}'::jsonb,now()-interval '1 minute'
  );

  -- Handoff exists and stored hash is internally valid, but the receipt claims
  -- a different hash. Layer 77 must preserve that mismatch.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
  )
  values(
    '77000000-0000-4000-8000-000000000105'::uuid,'production',
    '77000000-0000-4000-8000-000000000001'::uuid,
    'materialise-current-owner-handoff','case-chain-gap',
    repeat('5',64),'executed','test-layer77-handoff-mismatch',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
    jsonb_build_object(
      'foundationPromotedReleaseOwnerHandoffResponse',
        'shine-foundation/promoted-release-owner-handoff-response-v1',
      'schemaVersion','1.0.0','environment','production',
      'status','generated',
      'handoffId','77000000-0000-4000-8000-000000000031',
      'incidentEventId','77000000-0000-4000-8000-000000000020',
      'ownerServiceId','foundation.gateway',
      'ownerComponent','test-owner',
      'responsePlanFingerprint',repeat('e',64),
      'handoffSha256',repeat('0',64)
    ),
    '{}'::jsonb,now()-interval '1 minute'
  );

  -- Denied execution is not eligible for Layer-77 verification.
  insert into foundation.case_audit_safe_response_exec_events(
    event_id,environment,incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,before_snapshot,requested_at
  )
  values(
    '77000000-0000-4000-8000-000000000106'::uuid,'production',
    '77000000-0000-4000-8000-000000000001'::uuid,
    'record-fresh-promotion-case-audit-observation','observer-freshness',
    repeat('6',64),'denied','test-layer77-denied',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,now()-interval '1 minute'
  );
end;
$l77_seed_handoffs_and_receipts$;


set local role service_role;

do $l77_verification$
declare
  r jsonb;
  replay jsonb;
  s jsonb;
  obs_count_before bigint;
  obs_count_after bigint;
  handoff_count_before bigint;
  handoff_count_after bigint;
begin
  select count(*) into obs_count_before
  from foundation.foundation_promoted_release_case_audit_observations;
  select count(*) into handoff_count_before
  from foundation.foundation_promoted_release_owner_handoffs;

  r:=foundation.run_case_audit_safe_response_verification_v1(
    '77000000-0000-4000-8000-000000000101'::uuid,now()
  );
  if r->>'status'<>'recorded'
     or r->>'verificationState'<>'verified'
     or r->>'reasonCode'<>'case-audit-safe-response-observation-durable'
     or r->>'targetReexecuted'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 77 verified observation proof invalid: %',r;
  end if;

  replay:=foundation.run_case_audit_safe_response_verification_v1(
    '77000000-0000-4000-8000-000000000101'::uuid,now()
  );
  if replay->>'status'<>'existing'
     or replay->>'verificationId'<>r->>'verificationId'
     or replay->>'verificationState'<>'verified' then
    raise exception 'Layer 77 replay must preserve first proof: %',replay;
  end if;

  r:=foundation.run_case_audit_safe_response_verification_v1(
    '77000000-0000-4000-8000-000000000102'::uuid,now()
  );
  if r->>'verificationState'<>'missing'
     or r->>'reasonCode'<>'case-audit-safe-response-observation-missing' then
    raise exception 'Layer 77 missing observation proof invalid: %',r;
  end if;

  r:=foundation.run_case_audit_safe_response_verification_v1(
    '77000000-0000-4000-8000-000000000103'::uuid,now()
  );
  if r->>'verificationState'<>'mismatch'
     or r->>'reasonCode'<>'case-audit-safe-response-observation-mismatch' then
    raise exception 'Layer 77 observation mismatch proof invalid: %',r;
  end if;

  r:=foundation.run_case_audit_safe_response_verification_v1(
    '77000000-0000-4000-8000-000000000104'::uuid,now()
  );
  if r->>'verificationState'<>'verified'
     or r->>'reasonCode'<>'case-audit-safe-response-handoff-durable' then
    raise exception 'Layer 77 verified handoff proof invalid: %',r;
  end if;

  r:=foundation.run_case_audit_safe_response_verification_v1(
    '77000000-0000-4000-8000-000000000105'::uuid,now()
  );
  if r->>'verificationState'<>'mismatch'
     or r->>'reasonCode'<>'case-audit-safe-response-handoff-mismatch' then
    raise exception 'Layer 77 handoff mismatch proof invalid: %',r;
  end if;

  r:=foundation.run_case_audit_safe_response_verification_v1(
    '77000000-0000-4000-8000-000000000106'::uuid,now()
  );
  if r->>'status'<>'not-applicable'
     or r->>'reasonCode'<>'case-audit-safe-response-execution-not-successful' then
    raise exception 'Layer 77 denied execution eligibility invalid: %',r;
  end if;

  select count(*) into obs_count_after
  from foundation.foundation_promoted_release_case_audit_observations;
  select count(*) into handoff_count_after
  from foundation.foundation_promoted_release_owner_handoffs;

  if obs_count_after<>obs_count_before
     or handoff_count_after<>handoff_count_before then
    raise exception 'Layer 77 verification unexpectedly re-ran a target';
  end if;

  s:=foundation.get_case_audit_safe_response_verification_summary_v1(
    'production',25
  );
  if s->>'totalCount'<>'5'
     or s->>'verifiedCount'<>'2'
     or s->>'missingCount'<>'1'
     or s->>'mismatchCount'<>'2'
     or s->>'targetReexecuted'<>'false'
     or s->>'mutationPerformed'<>'false' then
    raise exception 'Layer 77 verification summary invalid: %',s;
  end if;
end;
$l77_verification$;

reset role;


do $l77_evaluator$
declare e jsonb;
begin
  e:=foundation.evaluate_case_audit_safe_response_execution_v1(
    '77000000-0000-4000-8000-000000000104'::uuid
  );
  if e->>'status'<>'evaluated'
     or e->>'verificationState'<>'verified'
     or e#>>'{checks,storedDocumentHashValid}'<>'true'
     or e->>'targetReexecuted'<>'false'
     or e->>'mutationPerformed'<>'false' then
    raise exception 'Layer 77 independent evaluator invalid: %',e;
  end if;
end;
$l77_evaluator$;


do $l77_privileges$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_safe_response_verification_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_safe_response_verification_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_safe_response_verification_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_safe_response_verification_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_safe_response_verification_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_safe_response_verifications',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.evaluate_case_audit_safe_response_execution_v1(uuid)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_safe_response_verification_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.evaluate_case_audit_safe_response_execution_v1(uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_safe_response_verification_summary_v1(text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 77 privilege boundary invalid';
  end if;
end;
$l77_privileges$;


do $l77_append_only$
declare id uuid;
begin
  select verification_id into id
  from foundation.case_audit_safe_response_verifications
  limit 1;

  begin
    update foundation.case_audit_safe_response_verifications
    set reason_code='mutation'
    where verification_id=id;
    raise exception 'Layer 77 verification history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l77_append_only$;

rollback;
