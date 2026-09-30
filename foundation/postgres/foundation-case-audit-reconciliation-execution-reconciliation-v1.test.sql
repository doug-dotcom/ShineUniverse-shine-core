begin;

-- Minimal shared Layer-74 source incident.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '87000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer87"}'::jsonb,
  now()-interval '20 minutes','test:layer87:case-audit-incident'
);

-- Minimal Layer-79 incident referenced by synthetic Layer-81 rows.
insert into foundation.case_audit_verify_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '87000000-0000-4000-8000-000000000201'::uuid,
  'production:case_audit_verification_coverage','production',
  'case_audit_verification_coverage','opened','gap','critical',
  'case-audit-safe-response-verification-overdue',repeat('9',64),
  now()-interval '15 minutes',300,600,'{"test":"layer87"}'::jsonb,
  now()-interval '8 minutes','test:layer87:verification-incident'
);

-- One active Layer-84 incident used by all synthetic Layer-86 receipts.
insert into foundation.case_audit_verify_reconcile_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '87000000-0000-4000-8000-000000000401'::uuid,
  'production:case_audit_verification_reconciliation_coverage','production',
  'case_audit_verification_reconciliation_coverage','opened','gap','critical',
  'case-audit-verify-reconcile-overdue',repeat('8',64),
  now()-interval '10 minutes',300,600,'{"test":"layer87"}'::jsonb,
  now()-interval '2 minutes','test:layer87:reconciliation-incident'
);


-- Four Layer-76 / Layer-81 chains.
do $l87_seed_layer81$
declare
  i integer;
  target_id uuid;
  executor_id uuid;
  layer81_result jsonb;
begin
  for i in 1..4 loop
    target_id:=(
      '87000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;
    executor_id:=(
      '87000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')
    )::uuid;

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      target_id,'production',
      '87000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      repeat(i::text,64),'executed','test-layer87-target-executed',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('test','layer87','target',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );

    layer81_result:=jsonb_build_object(
      'foundationCaseAuditSafeResponseVerification',
        'shine-foundation/case-audit-safe-response-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','recorded',
      'verificationId',null,
      'executionEventId',target_id,
      'verificationState','missing',
      'reasonCode','case-audit-safe-response-durable-evidence-missing',
      'durableEvidenceId',null,
      'durableEvidenceFingerprint',null,
      'verificationProofSha256',repeat('a',64),
      'targetReexecuted',false,
      'mutationPerformed',false
    );

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    )
    values(
      executor_id,'production',target_id,
      '87000000-0000-4000-8000-000000000201'::uuid,
      'run-independent-verification','verification-omission',
      repeat((i+4)::text,64),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      '{}'::jsonb,layer81_result,'{}'::jsonb,
      now()-interval '10 minutes'
    );
  end loop;
end;
$l87_seed_layer81$;


-- Layer-82 receipts for chains 1, 3 and 4. Chain 2 intentionally has none.
do $l87_seed_layer82$
declare
  i integer;
  executor_id uuid;
  target_id uuid;
  rec_id uuid;
  reconciled_at timestamptz;
  current_coverage jsonb;
  layer81_result jsonb;
  proof jsonb;
  proof_hash text;
begin
  foreach i in array array[1,3,4] loop
    executor_id:=(
      '87000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')
    )::uuid;
    target_id:=(
      '87000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;
    rec_id:=(
      '87000000-0000-4000-8000-'||lpad((500+i)::text,12,'0')
    )::uuid;
    reconciled_at:=now()-interval '1 minute';

    select action_result into layer81_result
    from foundation.case_audit_verify_exec_events
    where event_id=executor_id;

    current_coverage:=jsonb_build_object(
      'foundationCaseAuditSafeResponseVerificationCoverage',
        'shine-foundation/case-audit-safe-response-verification-coverage-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'test','layer87'
    );

    proof:=jsonb_build_object(
      'foundationCaseAuditVerificationExecutionReconciliationProof',
        'shine-foundation/case-audit-verification-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0',
      'reconciliationId',rec_id,
      'executorEventId',executor_id,
      'environment','production',
      'targetExecutionEventId',target_id,
      'verificationIncidentEventId',
        '87000000-0000-4000-8000-000000000201',
      'verificationId',null,
      'verificationState',null,
      'reconciliationState','missing-proof',
      'reasonCode','case-audit-verify-exec-reconcile-proof-missing',
      'proofIntegrityValid',null,
      'receiptMatchesProof',null,
      'currentEvaluationMatches',null,
      'coverageTargetVisible',false,
      'coverageTargetMatches',null,
      'verification',null,
      'currentEvaluation',null,
      'currentCoverage',current_coverage,
      'layer81ActionResult',layer81_result,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'mutationPerformed',false,
      'reconciledAt',reconciled_at
    );

    proof_hash:=encode(
      extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),
      'hex'
    );

    insert into foundation.case_audit_verify_exec_reconciliations(
      reconciliation_id,executor_event_id,environment,target_execution_event_id,
      verification_id,reconciliation_state,reason_code,verification_state,
      proof_integrity_valid,receipt_matches_proof,current_evaluation_matches,
      coverage_target_visible,coverage_target_matches,verification_snapshot,
      current_evaluation,current_coverage,layer81_action_result,
      reconciliation_proof,reconciliation_proof_sha256,reconciled_at
    )
    values(
      rec_id,executor_id,'production',target_id,null,'missing-proof',
      'case-audit-verify-exec-reconcile-proof-missing',null,
      null,null,null,false,null,null,null,current_coverage,layer81_result,
      proof,
      case when i=4 then repeat('f',64) else proof_hash end,
      reconciled_at
    );
  end loop;
end;
$l87_seed_layer82$;


-- Four Layer-86 claims:
-- 1 truthful; 2 claims execution with no Layer-82 receipt;
-- 3 action-result mismatch; 4 policy fingerprint drift + invalid Layer-82 hash.
do $l87_seed_layer86$
declare
  i integer;
  layer86_id uuid;
  executor_id uuid;
  layer82 foundation.case_audit_verify_exec_reconciliations%rowtype;
  target foundation.case_audit_verify_exec_events%rowtype;
  decision jsonb;
  incident_snapshot jsonb;
  target_snapshot jsonb;
  before_coverage jsonb;
  after_coverage jsonb;
  action_result jsonb;
  policy_fp text;
begin
  for i in 1..4 loop
    layer86_id:=(
      '87000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')
    )::uuid;
    executor_id:=(
      '87000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')
    )::uuid;

    select * into target
    from foundation.case_audit_verify_exec_events
    where event_id=executor_id;

    select * into layer82
    from foundation.case_audit_verify_exec_reconciliations
    where executor_event_id=executor_id;

    decision:=jsonb_build_object(
      'foundationCaseAuditVerificationReconciliationIncidentResponseDecision',
        'shine-foundation/case-audit-verification-reconciliation-incident-response-decision-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'incidentState','critical',
      'causeClass','reconciliation-omission',
      'actionKey','run-independent-reconciliation',
      'actionClass','evidence',
      'decision','admit',
      'requiredControl','layer-82-bounded-reconciler',
      'reasonCode','case-audit-reconciliation-response-run-bounded-reconciliation',
      'authorityExpansion',false,
      'automaticReconciliationAllowed',false,
      'automaticVerificationAllowed',false,
      'automaticRepairAllowed',false,
      'reconciliationReceiptRewriteAllowed',false,
      'verificationProofRewriteAllowed',false,
      'historyRewriteAllowed',false,
      'layer81RerunAllowed',false,
      'verificationRerunAllowed',false,
      'mutatesAuthoritativeTruth',false,
      'mutatesIncidentHistory',false,
      'mutatesReconciliationReceipt',false,
      'mutatesVerificationProof',false,
      'rerunsLayer81',false,
      'rerunsVerification',false,
      'executesAction',false
    );

    incident_snapshot:=jsonb_build_object(
      'state','critical',
      'currentEvent',jsonb_build_object(
        'eventId','87000000-0000-4000-8000-000000000401',
        'eventType','opened',
        'sourceState','gap',
        'evidenceFingerprint',repeat('8',64)
      )
    );

    target_snapshot:=jsonb_build_object(
      'executorEventId',target.event_id,
      'targetExecutionEventId',target.target_execution_event_id,
      'verificationIncidentEventId',target.verification_incident_event_id,
      'actionKey',target.action_key,
      'causeClass',target.cause_class,
      'policyFingerprint',target.policy_fingerprint,
      'eventType',target.event_type,
      'reasonCode',target.reason_code,
      'requestedAt',target.requested_at,
      'ageSeconds',600,
      'reconciliationGraceSeconds',300,
      'verificationGraceSeconds',300,
      'reconciliationId',null,
      'reconciliationState',null,
      'reconciliationAbsent',true
    );

    before_coverage:=jsonb_build_object(
      'foundationCaseAuditVerificationReconciliationCoverage',
        'shine-foundation/case-audit-verification-reconciliation-coverage-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'state','gap',
      'reasonCode','case-audit-verify-reconcile-overdue',
      'overdueCount',1,
      'verificationRerunPerformed',false,
      'layer81RerunPerformed',false,
      'mutationPerformed',false
    );

    after_coverage:=jsonb_build_object(
      'foundationCaseAuditVerificationReconciliationCoverage',
        'shine-foundation/case-audit-verification-reconciliation-coverage-v1',
      'schemaVersion','1.0.0',
      'environment','production',
      'state','gap',
      'reasonCode','case-audit-verify-exec-reconcile-proof-missing',
      'overdueCount',0,
      'missingProofCount',1,
      'verificationRerunPerformed',false,
      'layer81RerunPerformed',false,
      'mutationPerformed',false
    );

    action_result:=case
      when layer82.reconciliation_id is null then
        jsonb_build_object(
          'foundationCaseAuditVerificationExecutionReconciliation',
            'shine-foundation/case-audit-verification-execution-reconciliation-v1',
          'schemaVersion','1.0.0',
          'status','recorded',
          'reconciliationId','87000000-0000-4000-8000-000000000599',
          'executorEventId',executor_id,
          'targetExecutionEventId',target.target_execution_event_id,
          'verificationId',null,
          'reconciliationState','missing-proof',
          'reasonCode','case-audit-verify-exec-reconcile-proof-missing',
          'verificationState',null,
          'reconciliationProofSha256',repeat('9',64),
          'verificationRerunPerformed',false,
          'mutationPerformed',false
        )
      else
        jsonb_build_object(
          'foundationCaseAuditVerificationExecutionReconciliation',
            'shine-foundation/case-audit-verification-execution-reconciliation-v1',
          'schemaVersion','1.0.0',
          'status','recorded',
          'reconciliationId',layer82.reconciliation_id,
          'executorEventId',layer82.executor_event_id,
          'targetExecutionEventId',layer82.target_execution_event_id,
          'verificationId',layer82.verification_id,
          'reconciliationState',layer82.reconciliation_state,
          'reasonCode',layer82.reason_code,
          'verificationState',layer82.verification_state,
          'reconciliationProofSha256',
            case when i=3 then repeat('0',64)
                 else layer82.reconciliation_proof_sha256 end,
          'verificationRerunPerformed',false,
          'evidenceMutationPerformed',false,
          'verificationProofRewritePerformed',false,
          'releaseTruthMutationPerformed',false,
          'incidentHistoryMutationPerformed',false,
          'mutationPerformed',false
        )
    end;

    policy_fp:=foundation.case_audit_verify_reconcile_exec_policy_fp_v1(
      decision,incident_snapshot,target_snapshot
    );

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,
      reconciliation_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    )
    values(
      layer86_id,'production',executor_id,
      '87000000-0000-4000-8000-000000000401'::uuid,
      'run-independent-reconciliation','reconciliation-omission',
      case when i=4 then repeat('f',64) else policy_fp end,
      'executed','case-audit-overdue-reconciliation-layer82-ran',
      decision,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,now()-interval '30 seconds'
    );
  end loop;
end;
$l87_seed_layer86$;


do $l87_evaluate$
declare
  r jsonb;
begin
  r:=foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
    '87000000-0000-4000-8000-000000000701'::uuid,now()
  );
  if r->>'reconciliationState'<>'reconciled'
     or r->>'policyIntegrityValid'<>'true'
     or r->>'incidentBindingValid'<>'true'
     or r->>'layer82ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'true'
     or r->>'beforeCoverageValid'<>'true'
     or r->>'afterCoverageValid'<>'true' then
    raise exception 'Layer 87 truthful execution reconciliation invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
    '87000000-0000-4000-8000-000000000702'::uuid,now()
  );
  if r->>'reconciliationState'<>'missing-layer82-receipt' then
    raise exception 'Layer 87 missing Layer-82 receipt invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
    '87000000-0000-4000-8000-000000000703'::uuid,now()
  );
  if r->>'reconciliationState'<>'execution-receipt-mismatch'
     or r->>'layer82ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'false' then
    raise exception 'Layer 87 execution receipt mismatch invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
    '87000000-0000-4000-8000-000000000704'::uuid,now()
  );
  if r->>'reconciliationState'<>'invalid-layer82-receipt'
     or r->>'layer82ProofIntegrityValid'<>'false' then
    raise exception 'Layer 87 invalid Layer-82 receipt did not dominate: %',r;
  end if;
end;
$l87_evaluate$;


set local role service_role;

do $l87_reconcile$
declare
  r jsonb;
  replay jsonb;
  s jsonb;
  layer82_before bigint;
  layer82_after bigint;
  layer86_before bigint;
  layer86_after bigint;
  verification_before bigint;
  verification_after bigint;
begin
  select count(*) into layer82_before
  from foundation.case_audit_verify_exec_reconciliations;
  select count(*) into layer86_before
  from foundation.case_audit_verify_reconcile_exec_events;
  select count(*) into verification_before
  from foundation.case_audit_safe_response_verifications;

  r:=foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
    '87000000-0000-4000-8000-000000000701'::uuid,now()
  );
  if r->>'status'<>'recorded'
     or r->>'reconciliationState'<>'reconciled'
     or r->>'layer82RerunPerformed'<>'false'
     or r->>'layer81RerunPerformed'<>'false'
     or r->>'verificationRerunPerformed'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 87 reconciliation receipt invalid: %',r;
  end if;

  replay:=foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
    '87000000-0000-4000-8000-000000000701'::uuid,now()
  );
  if replay->>'status'<>'existing'
     or replay->>'reconciliationId'<>r->>'reconciliationId' then
    raise exception 'Layer 87 replay invalid: %',replay;
  end if;

  perform foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
    '87000000-0000-4000-8000-000000000702'::uuid,now()
  );
  perform foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
    '87000000-0000-4000-8000-000000000703'::uuid,now()
  );
  perform foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
    '87000000-0000-4000-8000-000000000704'::uuid,now()
  );

  select count(*) into layer82_after
  from foundation.case_audit_verify_exec_reconciliations;
  select count(*) into layer86_after
  from foundation.case_audit_verify_reconcile_exec_events;
  select count(*) into verification_after
  from foundation.case_audit_safe_response_verifications;

  if layer82_after<>layer82_before
     or layer86_after<>layer86_before
     or verification_after<>verification_before then
    raise exception 'Layer 87 unexpectedly reran or mutated upstream controls';
  end if;

  s:=foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(
    'production',25
  );

  if s->>'totalCount'<>'4'
     or s->>'reconciledCount'<>'1'
     or s->>'missingLayer82ReceiptCount'<>'1'
     or s->>'invalidLayer82ReceiptCount'<>'1'
     or s->>'executionReceiptMismatchCount'<>'1'
     or s->>'policyDriftCount'<>'0'
     or s->>'incidentDriftCount'<>'0'
     or s->>'coverageDriftCount'<>'0'
     or s->>'problemCount'<>'3'
     or s->>'layer82RerunPerformed'<>'false'
     or s->>'layer81RerunPerformed'<>'false'
     or s->>'verificationRerunPerformed'<>'false'
     or s->>'mutationPerformed'<>'false' then
    raise exception 'Layer 87 summary invalid: %',s;
  end if;
end;
$l87_reconcile$;

reset role;


do $l87_privileges$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_verify_reconcile_exec_reconciliations',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(text,integer)',
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
           'evaluate_case_audit_verify_reconcile_exec_outcome_v1',
           'get_case_audit_verify_reconcile_exec_reconciliation_summary_v1'
         )
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 87 privilege boundary invalid';
  end if;
end;
$l87_privileges$;


do $l87_append_only$
declare
  id uuid;
begin
  select reconciliation_id into id
  from foundation.case_audit_verify_reconcile_exec_reconciliations
  limit 1;

  begin
    update foundation.case_audit_verify_reconcile_exec_reconciliations
    set reason_code='mutation'
    where reconciliation_id=id;
    raise exception 'Layer 87 reconciliation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l87_append_only$;

rollback;
