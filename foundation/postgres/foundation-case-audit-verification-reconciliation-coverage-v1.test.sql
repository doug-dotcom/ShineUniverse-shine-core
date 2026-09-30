begin;

-- Minimal Layer-74 incident required by synthetic Layer-76 receipts.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '83000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer83"}'::jsonb,
  now()-interval '20 minutes','test:layer83:case-audit-incident'
);

-- Minimal Layer-79 incident required by synthetic Layer-81 receipts.
insert into foundation.case_audit_verify_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '83000000-0000-4000-8000-000000000201'::uuid,
  'production:case_audit_verification_coverage','production',
  'case_audit_verification_coverage','opened','gap','critical',
  'case-audit-safe-response-verification-overdue',repeat('b',64),
  now()-interval '20 minutes',300,900,'{"test":"layer83"}'::jsonb,
  now()-interval '10 minutes','test:layer83:verification-incident'
);

-- Six successful Layer-76 receipts back the six Layer-81 successful executions.
do $l83_seed_targets$
declare
  i integer;
  target_id uuid;
begin
  for i in 1..6 loop
    target_id:=(
      '83000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      target_id,'production',
      '83000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation',
      'observer-freshness',
      repeat(i::text,64),
      'executed','test-layer83-target-executed',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('test','layer83','target',i),
      '{}'::jsonb,
      now()-interval '20 minutes'
    );
  end loop;
end;
$l83_seed_targets$;

-- Verification rows only for reconciliation states that require a proof identity.
do $l83_seed_verifications$
declare
  i integer;
  target_id uuid;
  verification_id uuid;
begin
  foreach i in array array[1,5,6] loop
    target_id:=(
      '83000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;
    verification_id:=(
      '83000000-0000-4000-8000-'||lpad((900+i)::text,12,'0')
    )::uuid;

    insert into foundation.case_audit_safe_response_verifications(
      verification_id,execution_event_id,environment,incident_event_id,
      action_key,execution_policy_fingerprint,verification_state,reason_code,
      durable_evidence_id,durable_evidence_fingerprint,
      durable_evidence_snapshot,execution_action_result,verification_proof,
      verification_proof_sha256,verified_at
    )
    values(
      verification_id,target_id,'production',
      '83000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation',
      repeat(i::text,64),
      'verified','case-audit-safe-response-observation-durable',
      null,null,null,
      jsonb_build_object('test','layer83','target',i),
      jsonb_build_object('test','layer83','verification',i),
      repeat('c',64),
      now()-interval '5 minutes'
    );
  end loop;
end;
$l83_seed_verifications$;

-- Six successful Layer-81 executions:
-- 1 reconciled
-- 2 pending reconciliation
-- 3 overdue reconciliation
-- 4 missing-proof reconciliation
-- 5 evidence-drift reconciliation
-- 6 structurally invalid reconciliation receipt
do $l83_seed_executor$
declare
  i integer;
  executor_id uuid;
  target_id uuid;
  requested_at timestamptz;
begin
  for i in 1..6 loop
    executor_id:=(
      '83000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')
    )::uuid;
    target_id:=(
      '83000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;
    requested_at:=case
      when i=2 then now()-interval '1 minute'
      else now()-interval '10 minutes'
    end;

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    )
    values(
      executor_id,'production',target_id,
      '83000000-0000-4000-8000-000000000201'::uuid,
      'run-independent-verification','verification-omission',
      repeat(i::text,64),
      'executed','case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      '{"test":"layer83-before"}'::jsonb,
      jsonb_build_object('test','layer83','executor',i),
      '{"test":"layer83-after"}'::jsonb,
      requested_at
    );
  end loop;

  -- Denied Layer-81 attempts never enter the Layer-83 denominator.
  insert into foundation.case_audit_verify_exec_events(
    event_id,environment,target_execution_event_id,
    verification_incident_event_id,action_key,cause_class,
    policy_fingerprint,event_type,reason_code,decision_snapshot,
    incident_snapshot,target_snapshot,before_coverage,requested_at
  )
  values(
    '83000000-0000-4000-8000-000000000399'::uuid,
    'production','83000000-0000-4000-8000-000000000101'::uuid,
    '83000000-0000-4000-8000-000000000201'::uuid,
    'run-independent-verification','verification-omission',
    repeat('9',64),
    'denied','case-audit-overdue-verification-policy-not-admitted',
    '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
    '{"test":"layer83-denied"}'::jsonb,
    now()-interval '20 minutes'
  );
end;
$l83_seed_executor$;

-- Four Layer-82 reconciliation receipts (1,4,5,6).
-- Row 6 deliberately carries a bad proof hash.
do $l83_seed_reconciliations$
declare
  i integer;
  executor_id uuid;
  target_id uuid;
  reconciliation_id uuid;
  verification_id uuid;
  state text;
  reason text;
  verification_state text;
  proof_ok boolean;
  receipt_ok boolean;
  current_ok boolean;
  coverage_visible boolean;
  coverage_ok boolean;
  verification_snapshot jsonb;
  current_eval jsonb;
  current_coverage jsonb;
  layer81_result jsonb;
  reconciled_at timestamptz;
  proof jsonb;
  proof_hash text;
begin
  foreach i in array array[1,4,5,6] loop
    executor_id:=(
      '83000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')
    )::uuid;
    target_id:=(
      '83000000-0000-4000-8000-'||lpad((100+i)::text,12,'0')
    )::uuid;
    reconciliation_id:=(
      '83000000-0000-4000-8000-'||lpad((500+i)::text,12,'0')
    )::uuid;
    verification_id:=case
      when i=4 then null
      else (
        '83000000-0000-4000-8000-'||lpad((900+i)::text,12,'0')
      )::uuid
    end;

    state:=case
      when i in (1,6) then 'reconciled'
      when i=4 then 'missing-proof'
      when i=5 then 'evidence-drift'
    end;

    reason:=case
      when i in (1,6) then 'case-audit-verify-exec-reconcile-complete'
      when i=4 then 'case-audit-verify-exec-reconcile-proof-missing'
      when i=5 then 'case-audit-verify-exec-reconcile-evidence-drift'
    end;

    verification_state:=case when verification_id is null then null else 'verified' end;
    proof_ok:=case when i=4 then null else true end;
    receipt_ok:=case when i=4 then null else true end;
    current_ok:=case
      when i=4 then null
      when i=5 then false
      else true
    end;
    coverage_visible:=case when i=4 then false else true end;
    coverage_ok:=case when i=4 then null else true end;

    verification_snapshot:=case
      when verification_id is null then null
      else jsonb_build_object(
        'verificationId',verification_id,
        'verificationState','verified',
        'test','layer83'
      )
    end;

    current_eval:=case
      when i=4 then null
      else jsonb_build_object(
        'status','evaluated',
        'verificationState',case when i=5 then 'mismatch' else 'verified' end,
        'test','layer83'
      )
    end;

    current_coverage:=jsonb_build_object(
      'foundationCaseAuditSafeResponseVerificationCoverage',
        'shine-foundation/case-audit-safe-response-verification-coverage-v1',
      'schemaVersion','1.0.0',
      'test','layer83',
      'reconciliation',i
    );

    select action_result into layer81_result
    from foundation.case_audit_verify_exec_events
    where event_id=executor_id;

    reconciled_at:=now()-interval '30 seconds';

    proof:=jsonb_build_object(
      'foundationCaseAuditVerificationExecutionReconciliationProof',
        'shine-foundation/case-audit-verification-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0',
      'reconciliationId',reconciliation_id,
      'executorEventId',executor_id,
      'environment','production',
      'targetExecutionEventId',target_id,
      'verificationIncidentEventId',
        '83000000-0000-4000-8000-000000000201',
      'verificationId',verification_id,
      'verificationState',verification_state,
      'reconciliationState',state,
      'reasonCode',reason,
      'proofIntegrityValid',proof_ok,
      'receiptMatchesProof',receipt_ok,
      'currentEvaluationMatches',current_ok,
      'coverageTargetVisible',coverage_visible,
      'coverageTargetMatches',coverage_ok,
      'verification',verification_snapshot,
      'currentEvaluation',current_eval,
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
      reconciliation_id,executor_event_id,environment,
      target_execution_event_id,verification_id,reconciliation_state,
      reason_code,verification_state,proof_integrity_valid,
      receipt_matches_proof,current_evaluation_matches,
      coverage_target_visible,coverage_target_matches,
      verification_snapshot,current_evaluation,current_coverage,
      layer81_action_result,reconciliation_proof,
      reconciliation_proof_sha256,reconciled_at
    )
    values(
      reconciliation_id,executor_id,'production',target_id,verification_id,
      state,reason,verification_state,proof_ok,receipt_ok,current_ok,
      coverage_visible,coverage_ok,verification_snapshot,current_eval,
      current_coverage,layer81_result,proof,
      case when i=6 then repeat('f',64) else proof_hash end,
      reconciled_at
    );
  end loop;
end;
$l83_seed_reconciliations$;


do $l83_coverage$
declare
  r jsonb;
  idle jsonb;
begin
  r:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',now(),300,50
  );

  if r->>'state'<>'invalid'
     or r->>'reasonCode'<>'case-audit-verify-reconcile-receipt-invalid'
     or r->>'successfulExecutorCount'<>'6'
     or r->>'reconciliationRequiredCount'<>'6'
     or r->>'reconciliationReceiptCount'<>'4'
     or r->>'reconciledCount'<>'1'
     or r->>'pendingCount'<>'1'
     or r->>'overdueCount'<>'1'
     or r->>'invalidReconciliationCount'<>'1'
     or r->>'missingProofCount'<>'1'
     or r->>'receiptMismatchCount'<>'0'
     or r->>'invalidProofCount'<>'0'
     or r->>'evidenceDriftCount'<>'1'
     or r->>'coverageDriftCount'<>'0'
     or r->>'problemCount'<>'4'
     or r->>'reconciliationCoveragePercent'<>'66.67'
     or r->>'healthyReconciliationPercent'<>'16.67'
     or r->>'onlySuccessfulLayer81ExecutionsRequireReconciliation'<>'true'
     or r->>'reconciliationProofIntegrityRecomputed'<>'true'
     or r->>'verificationRerunPerformed'<>'false'
     or r->>'layer81RerunPerformed'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 83 coverage summary invalid: %',r;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='pending'
      and item->>'reasonCode'='case-audit-verify-reconcile-within-grace'
  )
  or not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='overdue'
      and item->>'reasonCode'='case-audit-verify-reconcile-overdue'
  )
  or not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='invalid-reconciliation'
      and item->>'reconciliationProofIntegrityValid'='false'
  )
  or not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='missing-proof'
  )
  or not exists(
    select 1
    from jsonb_array_elements(r->'items') item
    where item->>'coverageState'='evidence-drift'
  ) then
    raise exception 'Layer 83 item classification invalid: %',r;
  end if;

  idle:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'staging',now(),300,50
  );

  if idle->>'state'<>'idle'
     or idle->>'successfulExecutorCount'<>'0'
     or idle->>'reconciliationCoveragePercent'<>'100.00'
     or idle->>'healthyReconciliationPercent'<>'100.00'
     or idle->>'problemCount'<>'0' then
    raise exception 'Layer 83 idle coverage invalid: %',idle;
  end if;
end;
$l83_coverage$;


do $l83_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_reconcile_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.get_case_audit_verify_reconcile_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_reconcile_coverage_v1(text,timestamptz,integer,integer)',
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
         and p.proname='get_case_audit_verify_reconcile_coverage_v1'
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_reconcile_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_verify_reconcile_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_verify_reconcile_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_verify_reconcile_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 83 privilege boundary invalid';
  end if;
end;
$l83_privileges$;

rollback;
