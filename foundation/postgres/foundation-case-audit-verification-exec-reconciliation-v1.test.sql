begin;

-- Shared Layer-74 source incident.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '82000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer82"}'::jsonb,
  now()-interval '20 minutes','test:layer82:case-audit-incident'
);

-- Shared durable Layer-73 evidence.
insert into foundation.foundation_promoted_release_case_audit_observations(
  observation_id,environment,audit_state,structural_integrity_pass,incident_state,
  active_incident_event_id,active_incident_handoff_state,case_count,invalid_count,
  active_case_count,pending_case_count,terminal_case_count,historical_case_count,
  semantic_fingerprint,changed_from_previous,snapshot,observed_at
)
values(
  '82000000-0000-4000-8000-000000000010'::uuid,
  'production','idle',true,'normal',null,'not-required',
  0,0,0,0,0,0,
  foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer82"}'::jsonb
  ),
  false,'{"overallState":"idle","test":"layer82"}'::jsonb,
  now()-interval '15 minutes'
);

-- Layer-79 incident referenced by the synthetic Layer-81 execution receipts.
insert into foundation.case_audit_verify_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '82000000-0000-4000-8000-000000000201'::uuid,
  'production:case_audit_verification_coverage','production',
  'case_audit_verification_coverage','opened','gap','critical',
  'case-audit-safe-response-verification-overdue',repeat('9',64),
  now()-interval '15 minutes',300,600,'{"test":"layer82"}'::jsonb,
  now()-interval '5 minutes','test:layer82:verification-incident'
);


do $l82_seed_targets$
declare
  fp text;
  action_result jsonb;
  i integer;
  event_id uuid;
begin
  fp:=foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
    '{"overallState":"idle","test":"layer82"}'::jsonb
  );

  for i in 1..5 loop
    event_id:=(
      '82000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;

    action_result:=jsonb_build_object(
      'foundationPromotedReleaseCaseAuditObservationRecord',
        'shine-foundation/promoted-release-case-audit-observation-record-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'status','recorded-heartbeat',
      'observationId','82000000-0000-4000-8000-000000000010',
      'semanticFingerprint',case
        when i=5 then repeat('f',64)
        else fp
      end
    );

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      event_id,'production',
      '82000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      repeat(i::text,64),'executed','test-layer82-target-executed',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,action_result,'{}'::jsonb,
      now()-interval '12 minutes'
    );
  end loop;
end;
$l82_seed_targets$;


-- Real Layer-77 proofs for targets 101 and 103.
do $l82_real_layer77$
declare
  r jsonb;
begin
  r:=foundation.run_case_audit_safe_response_verification_v1(
    '82000000-0000-4000-8000-000000000101'::uuid,now()
  );
  if r->>'status'<>'recorded'
     or r->>'verificationState'<>'verified' then
    raise exception 'Layer 82 seed proof 101 invalid: %',r;
  end if;

  r:=foundation.run_case_audit_safe_response_verification_v1(
    '82000000-0000-4000-8000-000000000103'::uuid,now()
  );
  if r->>'status'<>'recorded'
     or r->>'verificationState'<>'verified' then
    raise exception 'Layer 82 seed proof 103 invalid: %',r;
  end if;
end;
$l82_real_layer77$;


-- Target 104: a syntactically present Layer-77 row with an invalid proof hash.
insert into foundation.case_audit_safe_response_verifications(
  verification_id,execution_event_id,environment,incident_event_id,
  action_key,execution_policy_fingerprint,verification_state,reason_code,
  durable_evidence_id,durable_evidence_fingerprint,durable_evidence_snapshot,
  execution_action_result,verification_proof,verification_proof_sha256,
  verified_at
)
select
  '82000000-0000-4000-8000-000000000904'::uuid,
  e.event_id,e.environment,e.incident_event_id,e.action_key,e.policy_fingerprint,
  'verified','case-audit-safe-response-observation-durable',
  '82000000-0000-4000-8000-000000000010'::uuid,
  o.semantic_fingerprint,
  '{"test":"layer82-invalid-proof"}'::jsonb,
  e.action_result,
  jsonb_build_object(
    'foundationCaseAuditSafeResponseVerificationProof',
      'shine-foundation/case-audit-safe-response-verification-proof-v1',
    'schemaVersion','1.0.0',
    'executionEventId',e.event_id,
    'environment',e.environment
  ),
  repeat('f',64),
  now()
from foundation.case_audit_safe_response_exec_events e
join foundation.foundation_promoted_release_case_audit_observations o
  on o.observation_id='82000000-0000-4000-8000-000000000010'::uuid
where e.event_id='82000000-0000-4000-8000-000000000104'::uuid;


-- Target 105: structurally valid proof claims VERIFIED, but current durable
-- evaluation is MISMATCH because the Layer-76 action result carries a wrong
-- semantic fingerprint. Layer 82 must detect that semantic drift.
do $l82_seed_evidence_drift$
declare
  e foundation.case_audit_safe_response_exec_events%rowtype;
  o foundation.foundation_promoted_release_case_audit_observations%rowtype;
  verification_id uuid := '82000000-0000-4000-8000-000000000905'::uuid;
  verified_at timestamptz := now();
  durable_snapshot jsonb := '{"test":"layer82-evidence-drift"}'::jsonb;
  proof jsonb;
  proof_hash text;
begin
  select * into e
  from foundation.case_audit_safe_response_exec_events
  where event_id='82000000-0000-4000-8000-000000000105'::uuid;

  select * into o
  from foundation.foundation_promoted_release_case_audit_observations
  where observation_id='82000000-0000-4000-8000-000000000010'::uuid;

  proof:=jsonb_build_object(
    'foundationCaseAuditSafeResponseVerificationProof',
      'shine-foundation/case-audit-safe-response-verification-proof-v1',
    'schemaVersion','1.0.0',
    'executionEventId',e.event_id,
    'environment',e.environment,
    'incidentEventId',e.incident_event_id,
    'actionKey',e.action_key,
    'executionPolicyFingerprint',e.policy_fingerprint,
    'executionRequestedAt',e.requested_at,
    'verificationState','verified',
    'reasonCode','case-audit-safe-response-observation-durable',
    'durableEvidenceId',o.observation_id,
    'durableEvidenceFingerprint',o.semantic_fingerprint,
    'durableEvidence',durable_snapshot,
    'executionActionResult',e.action_result,
    'independentDurableEvidenceRead',true,
    'targetReexecuted',false,
    'historyRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'mutationPerformed',false,
    'verifiedAt',verified_at
  );

  proof_hash:=encode(
    extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.case_audit_safe_response_verifications(
    verification_id,execution_event_id,environment,incident_event_id,
    action_key,execution_policy_fingerprint,verification_state,reason_code,
    durable_evidence_id,durable_evidence_fingerprint,durable_evidence_snapshot,
    execution_action_result,verification_proof,verification_proof_sha256,
    verified_at
  )
  values(
    verification_id,e.event_id,e.environment,e.incident_event_id,e.action_key,
    e.policy_fingerprint,'verified',
    'case-audit-safe-response-observation-durable',
    o.observation_id,o.semantic_fingerprint,durable_snapshot,e.action_result,
    proof,proof_hash,verified_at
  );
end;
$l82_seed_evidence_drift$;


do $l82_seed_layer81$
declare
  decision jsonb;
  incident_snapshot jsonb;
  before_coverage jsonb;
  after_coverage jsonb;
  target foundation.case_audit_safe_response_exec_events%rowtype;
  verification foundation.case_audit_safe_response_verifications%rowtype;
  target_snapshot jsonb;
  action_result jsonb;
  policy_fp text;
  i integer;
  executor_event_id uuid;
begin
  decision:=jsonb_build_object(
    'foundationCaseAuditVerificationIncidentResponseDecision',
      'shine-foundation/case-audit-verification-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'incidentState','critical',
    'causeClass','verification-omission',
    'actionKey','run-independent-verification',
    'actionClass','evidence',
    'decision','admit',
    'requiredControl','layer-77-bounded-verifier',
    'reasonCode','case-audit-verification-response-run-bounded-verification',
    'authorityExpansion',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'mutatesVerificationProof',false,
    'rerunsSafeResponse',false,
    'executesAction',false
  );

  incident_snapshot:=jsonb_build_object(
    'state','critical',
    'currentEvent',jsonb_build_object(
      'eventId','82000000-0000-4000-8000-000000000201',
      'eventType','opened',
      'sourceState','gap',
      'evidenceFingerprint',repeat('9',64)
    )
  );

  before_coverage:=
    foundation.get_case_audit_safe_response_verification_coverage_v1(
      'production',now(),300,100
    );
  after_coverage:=before_coverage;

  for i in 1..5 loop
    select * into target
    from foundation.case_audit_safe_response_exec_events
    where event_id=(
      '82000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;

    select * into verification
    from foundation.case_audit_safe_response_verifications
    where execution_event_id=target.event_id;

    target_snapshot:=jsonb_build_object(
      'executionEventId',target.event_id,
      'incidentEventId',target.incident_event_id,
      'actionKey',target.action_key,
      'executionPolicyFingerprint',target.policy_fingerprint,
      'executionEventType',target.event_type,
      'executionRequestedAt',target.requested_at,
      'executionAgeSeconds',720,
      'verificationGraceSeconds',300,
      'verificationId',null,
      'verificationState',null,
      'verificationAbsent',true
    );

    if i=2 then
      action_result:=jsonb_build_object(
        'foundationCaseAuditSafeResponseVerification',
          'shine-foundation/case-audit-safe-response-verification-response-v1',
        'schemaVersion','1.0.0',
        'status','recorded',
        'verificationId','82000000-0000-4000-8000-000000000902',
        'executionEventId',target.event_id,
        'verificationState','verified',
        'reasonCode','case-audit-safe-response-observation-durable',
        'durableEvidenceId','82000000-0000-4000-8000-000000000010',
        'durableEvidenceFingerprint',repeat('2',64),
        'verificationProofSha256',repeat('2',64),
        'targetReexecuted',false,
        'mutationPerformed',false
      );

    elsif i=4 then
      action_result:=jsonb_build_object(
        'foundationCaseAuditSafeResponseVerification',
          'shine-foundation/case-audit-safe-response-verification-response-v1',
        'schemaVersion','1.0.0',
        'status','recorded',
        'verificationId',verification.verification_id,
        'executionEventId',target.event_id,
        'verificationState',verification.verification_state,
        'reasonCode',verification.reason_code,
        'durableEvidenceId',verification.durable_evidence_id,
        'durableEvidenceFingerprint',
          verification.durable_evidence_fingerprint,
        'verificationProofSha256',verification.verification_proof_sha256,
        'targetReexecuted',false,
        'mutationPerformed',false
      );

    elsif i=5 then
      action_result:=jsonb_build_object(
        'foundationCaseAuditSafeResponseVerification',
          'shine-foundation/case-audit-safe-response-verification-response-v1',
        'schemaVersion','1.0.0',
        'status','recorded',
        'verificationId',verification.verification_id,
        'executionEventId',target.event_id,
        'verificationState',verification.verification_state,
        'reasonCode',verification.reason_code,
        'durableEvidenceId',verification.durable_evidence_id,
        'durableEvidenceFingerprint',
          verification.durable_evidence_fingerprint,
        'verificationProofSha256',verification.verification_proof_sha256,
        'targetReexecuted',false,
        'mutationPerformed',false
      );

    else
      action_result:=case
        when i=1 then (
          select jsonb_build_object(
            'foundationCaseAuditSafeResponseVerification',
              'shine-foundation/case-audit-safe-response-verification-response-v1',
            'schemaVersion','1.0.0',
            'status','recorded',
            'verificationId',v.verification_id,
            'executionEventId',v.execution_event_id,
            'verificationState',v.verification_state,
            'reasonCode',v.reason_code,
            'durableEvidenceId',v.durable_evidence_id,
            'durableEvidenceFingerprint',v.durable_evidence_fingerprint,
            'verificationProofSha256',v.verification_proof_sha256,
            'targetReexecuted',false,
            'mutationPerformed',false
          )
          from foundation.case_audit_safe_response_verifications v
          where v.execution_event_id=target.event_id
        )
        else (
          select jsonb_build_object(
            'foundationCaseAuditSafeResponseVerification',
              'shine-foundation/case-audit-safe-response-verification-response-v1',
            'schemaVersion','1.0.0',
            'status','recorded',
            'verificationId',v.verification_id,
            'executionEventId',v.execution_event_id,
            'verificationState',v.verification_state,
            'reasonCode',v.reason_code,
            'durableEvidenceId',v.durable_evidence_id,
            'durableEvidenceFingerprint',v.durable_evidence_fingerprint,
            'verificationProofSha256',repeat('0',64),
            'targetReexecuted',false,
            'mutationPerformed',false
          )
          from foundation.case_audit_safe_response_verifications v
          where v.execution_event_id=target.event_id
        )
      end;
    end if;

    policy_fp:=foundation.case_audit_verify_exec_policy_fp_v1(
      decision,incident_snapshot,target_snapshot
    );

    executor_event_id:=(
      '82000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')
    )::uuid;

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    )
    values(
      executor_event_id,'production',target.event_id,
      '82000000-0000-4000-8000-000000000201'::uuid,
      'run-independent-verification','verification-omission',
      policy_fp,'executed','case-audit-overdue-verification-layer77-ran',
      decision,incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,now()
    );
  end loop;

  -- Non-executed Layer-81 receipt must not be reconciled.
  select * into target
  from foundation.case_audit_safe_response_exec_events
  where event_id='82000000-0000-4000-8000-000000000102'::uuid;

  target_snapshot:=jsonb_build_object(
    'executionEventId',target.event_id,
    'incidentEventId',target.incident_event_id,
    'actionKey',target.action_key,
    'executionPolicyFingerprint',target.policy_fingerprint,
    'executionEventType',target.event_type,
    'executionRequestedAt',target.requested_at,
    'executionAgeSeconds',720,
    'verificationGraceSeconds',300,
    'verificationId',null,
    'verificationState',null,
    'verificationAbsent',true
  );

  policy_fp:=foundation.case_audit_verify_exec_policy_fp_v1(
    decision,incident_snapshot,target_snapshot
  );

  insert into foundation.case_audit_verify_exec_events(
    event_id,environment,target_execution_event_id,
    verification_incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,target_snapshot,before_coverage,requested_at
  )
  values(
    '82000000-0000-4000-8000-000000000399'::uuid,
    'production',target.event_id,
    '82000000-0000-4000-8000-000000000201'::uuid,
    'run-independent-verification','verification-omission',
    policy_fp,'denied','case-audit-overdue-verification-policy-not-admitted',
    decision,incident_snapshot,target_snapshot,before_coverage,now()
  );
end;
$l82_seed_layer81$;


set local role service_role;

do $l82_reconcile$
declare
  r jsonb;
  replay jsonb;
  e jsonb;
  s jsonb;
  verification_count_before bigint;
  verification_count_after bigint;
  executor_count_before bigint;
  executor_count_after bigint;
begin
  select count(*) into verification_count_before
  from foundation.case_audit_safe_response_verifications;

  select count(*) into executor_count_before
  from foundation.case_audit_verify_exec_events;

  r:=foundation.run_case_audit_verify_exec_reconciliation_v1(
    '82000000-0000-4000-8000-000000000301'::uuid,now(),300
  );

  if r->>'status'<>'recorded'
     or r->>'reconciliationState'<>'reconciled'
     or r->>'verificationState'<>'verified'
     or r->>'verificationRerunPerformed'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 82 reconciled outcome invalid: %',r;
  end if;

  e:=foundation.evaluate_case_audit_verify_exec_outcome_v1(
    '82000000-0000-4000-8000-000000000301'::uuid,now(),300
  );

  if e->>'reconciliationState'<>'reconciled'
     or e->>'proofIntegrityValid'<>'true'
     or e->>'receiptMatchesProof'<>'true'
     or e->>'currentEvaluationMatches'<>'true'
     or e->>'coverageTargetVisible'<>'true'
     or e->>'coverageTargetMatches'<>'true' then
    raise exception 'Layer 82 independent reconciled evaluator invalid: %',e;
  end if;

  replay:=foundation.run_case_audit_verify_exec_reconciliation_v1(
    '82000000-0000-4000-8000-000000000301'::uuid,now(),300
  );

  if replay->>'status'<>'existing'
     or replay->>'reconciliationId'<>r->>'reconciliationId'
     or replay->>'reconciliationState'<>'reconciled' then
    raise exception 'Layer 82 reconciliation replay invalid: %',replay;
  end if;

  r:=foundation.run_case_audit_verify_exec_reconciliation_v1(
    '82000000-0000-4000-8000-000000000302'::uuid,now(),300
  );
  if r->>'reconciliationState'<>'missing-proof'
     or r->>'reasonCode'<>'case-audit-verify-exec-reconcile-proof-missing' then
    raise exception 'Layer 82 missing proof state invalid: %',r;
  end if;

  r:=foundation.run_case_audit_verify_exec_reconciliation_v1(
    '82000000-0000-4000-8000-000000000303'::uuid,now(),300
  );
  if r->>'reconciliationState'<>'receipt-mismatch'
     or r->>'reasonCode'<>'case-audit-verify-exec-reconcile-receipt-mismatch' then
    raise exception 'Layer 82 receipt mismatch state invalid: %',r;
  end if;

  r:=foundation.run_case_audit_verify_exec_reconciliation_v1(
    '82000000-0000-4000-8000-000000000304'::uuid,now(),300
  );
  if r->>'reconciliationState'<>'invalid-proof'
     or r->>'reasonCode'<>'case-audit-verify-exec-reconcile-proof-invalid' then
    raise exception 'Layer 82 invalid proof state invalid: %',r;
  end if;

  r:=foundation.run_case_audit_verify_exec_reconciliation_v1(
    '82000000-0000-4000-8000-000000000305'::uuid,now(),300
  );
  if r->>'reconciliationState'<>'evidence-drift'
     or r->>'reasonCode'<>'case-audit-verify-exec-reconcile-evidence-drift' then
    raise exception 'Layer 82 evidence drift state invalid: %',r;
  end if;

  r:=foundation.run_case_audit_verify_exec_reconciliation_v1(
    '82000000-0000-4000-8000-000000000399'::uuid,now(),300
  );
  if r->>'status'<>'not-applicable'
     or r->>'reasonCode'<>'case-audit-verify-exec-reconcile-source-not-executed' then
    raise exception 'Layer 82 non-executed source handling invalid: %',r;
  end if;

  select count(*) into verification_count_after
  from foundation.case_audit_safe_response_verifications;
  select count(*) into executor_count_after
  from foundation.case_audit_verify_exec_events;

  if verification_count_after<>verification_count_before
     or executor_count_after<>executor_count_before then
    raise exception 'Layer 82 unexpectedly reran verification or Layer 81';
  end if;

  s:=foundation.get_case_audit_verify_reconcile_summary_v1(
    'production',25
  );

  if s->>'totalCount'<>'5'
     or s->>'reconciledCount'<>'1'
     or s->>'missingProofCount'<>'1'
     or s->>'receiptMismatchCount'<>'1'
     or s->>'invalidProofCount'<>'1'
     or s->>'evidenceDriftCount'<>'1'
     or s->>'coverageDriftCount'<>'0'
     or s->>'problemCount'<>'4'
     or s->>'verificationRerunPerformed'<>'false'
     or s->>'mutationPerformed'<>'false' then
    raise exception 'Layer 82 reconciliation summary invalid: %',s;
  end if;
end;
$l82_reconcile$;

reset role;


do $l82_privileges$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_verify_exec_reconciliation_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_verify_exec_reconciliation_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_verify_exec_reconciliation_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_verify_exec_reconciliation_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_verify_exec_reconciliation_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_verify_exec_reconciliations',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.evaluate_case_audit_verify_exec_outcome_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_reconcile_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_reconcile_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not pg_has_role(
       'foundation_gateway','foundation_runtime','MEMBER'
     )
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(
         coalesce(p.proacl,acldefault('f',p.proowner))
       ) a
       join pg_roles r on r.oid=a.grantee
       where n.nspname='foundation'
         and p.proname in (
           'evaluate_case_audit_verify_exec_outcome_v1',
           'get_case_audit_verify_reconcile_summary_v1'
         )
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_reconcile_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.evaluate_case_audit_verify_exec_outcome_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_verify_reconcile_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.evaluate_case_audit_verify_exec_outcome_v1(uuid,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 82 privilege boundary invalid';
  end if;
end;
$l82_privileges$;


do $l82_append_only$
declare
  id uuid;
begin
  select reconciliation_id into id
  from foundation.case_audit_verify_exec_reconciliations
  limit 1;

  begin
    update foundation.case_audit_verify_exec_reconciliations
    set reason_code='mutation'
    where reconciliation_id=id;
    raise exception 'Layer 82 reconciliation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l82_append_only$;

do $layer82_verification_fk_index$
begin
  if not exists (
    select 1
    from pg_indexes
    where schemaname='foundation'
      and tablename='case_audit_verify_exec_reconciliations'
      and indexname='case_audit_verify_reconcile_verification_idx'
      and indexdef ilike '%(verification_id)%'
  ) then
    raise exception 'Layer 82 verification foreign key lacks covering index';
  end if;
end;
$layer82_verification_fk_index$;


rollback;
