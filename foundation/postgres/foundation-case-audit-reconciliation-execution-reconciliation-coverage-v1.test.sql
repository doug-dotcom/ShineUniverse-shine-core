begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '88000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer88"}'::jsonb,
  now()-interval '20 minutes','test:layer88:case-audit-incident'
);

insert into foundation.case_audit_verify_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '88000000-0000-4000-8000-000000000201'::uuid,
  'production:case_audit_verification_coverage','production',
  'case_audit_verification_coverage','opened','gap','critical',
  'case-audit-safe-response-verification-overdue',repeat('9',64),
  now()-interval '20 minutes',300,900,'{"test":"layer88"}'::jsonb,
  now()-interval '10 minutes','test:layer88:verification-incident'
);

insert into foundation.case_audit_verify_reconcile_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,
  evidence_ref
)
values(
  '88000000-0000-4000-8000-000000000401'::uuid,
  'production:case_audit_verification_reconciliation_coverage','production',
  'case_audit_verification_reconciliation_coverage','opened','gap','critical',
  'case-audit-verify-reconcile-overdue',repeat('8',64),
  now()-interval '15 minutes',300,600,'{"test":"layer88"}'::jsonb,
  now()-interval '5 minutes','test:layer88:reconciliation-incident'
);

do $l88_seed_layer81$
declare i integer; target_id uuid; executor_id uuid; layer81_result jsonb;
begin
  for i in 1..6 loop
    target_id:=('88000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid;
    executor_id:=('88000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid;

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    ) values(
      target_id,'production','88000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      repeat(i::text,64),'executed','test-layer88-target-executed',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('test','layer88','target',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );

    layer81_result:=jsonb_build_object(
      'foundationCaseAuditSafeResponseVerification',
        'shine-foundation/case-audit-safe-response-verification-response-v1',
      'schemaVersion','1.0.0','status','recorded',
      'verificationId',null,'executionEventId',target_id,
      'verificationState','missing',
      'reasonCode','case-audit-safe-response-durable-evidence-missing',
      'durableEvidenceId',null,'durableEvidenceFingerprint',null,
      'verificationProofSha256',repeat('a',64),
      'targetReexecuted',false,'mutationPerformed',false
    );

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    ) values(
      executor_id,'production',target_id,
      '88000000-0000-4000-8000-000000000201'::uuid,
      'run-independent-verification','verification-omission',
      repeat(to_hex(i+6),64),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      layer81_result,'{}'::jsonb,now()-interval '15 minutes'
    );
  end loop;
end;
$l88_seed_layer81$;

do $l88_seed_layer82$
declare i integer; executor_id uuid; target_id uuid; rec_id uuid; layer81_result jsonb;
begin
  foreach i in array array[1,5,6] loop
    executor_id:=('88000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid;
    target_id:=('88000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid;
    rec_id:=('88000000-0000-4000-8000-'||lpad((500+i)::text,12,'0'))::uuid;

    select action_result into layer81_result
    from foundation.case_audit_verify_exec_events
    where event_id=executor_id;

    insert into foundation.case_audit_verify_exec_reconciliations(
      reconciliation_id,executor_event_id,environment,target_execution_event_id,
      verification_id,reconciliation_state,reason_code,verification_state,
      proof_integrity_valid,receipt_matches_proof,current_evaluation_matches,
      coverage_target_visible,coverage_target_matches,verification_snapshot,
      current_evaluation,current_coverage,layer81_action_result,
      reconciliation_proof,reconciliation_proof_sha256,reconciled_at
    ) values(
      rec_id,executor_id,'production',target_id,null,'missing-proof',
      'case-audit-verify-exec-reconcile-proof-missing',null,
      null,null,null,false,null,null,null,
      '{"test":"layer88","coverage":"layer82"}'::jsonb,
      layer81_result,'{"test":"layer88","proof":"layer82"}'::jsonb,
      repeat('b',64),now()-interval '4 minutes'
    );
  end loop;
end;
$l88_seed_layer82$;

do $l88_seed_layer86$
declare i integer; layer86_id uuid; executor_id uuid; requested_at timestamptz;
begin
  for i in 1..6 loop
    layer86_id:=('88000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid;
    executor_id:=('88000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid;
    requested_at:=case when i=2 then now()-interval '1 minute'
                       else now()-interval '10 minutes' end;

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,
      reconciliation_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    ) values(
      layer86_id,'production',executor_id,
      '88000000-0000-4000-8000-000000000401'::uuid,
      'run-independent-reconciliation','reconciliation-omission',
      repeat((i+1)::text,64),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('test','layer88','layer86',i),
      '{}'::jsonb,requested_at
    );
  end loop;
end;
$l88_seed_layer86$;

-- Layer-87 receipts:
-- 1 reconciled; 4 valid missing-layer82 (covered but unhealthy);
-- 5 valid execution-receipt-mismatch (covered but unhealthy);
-- 6 invalid Layer-87 proof; 2 pending/no receipt; 3 overdue/no receipt.
do $l88_seed_layer87$
declare
  i integer;
  layer86 foundation.case_audit_verify_reconcile_exec_events%rowtype;
  l82 foundation.case_audit_verify_exec_reconciliations%rowtype;
  rec_id uuid; state text; reason text;
  policy_ok boolean; incident_ok boolean; layer82_ok boolean;
  exec_match boolean; before_ok boolean; after_ok boolean;
  layer86_snapshot jsonb; layer82_snapshot jsonb; proof jsonb; proof_hash text;
  reconciled_at timestamptz;
begin
  foreach i in array array[1,4,5,6] loop
    select * into layer86
    from foundation.case_audit_verify_reconcile_exec_events
    where event_id=('88000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid;

    select * into l82
    from foundation.case_audit_verify_exec_reconciliations
    where executor_event_id=layer86.target_executor_event_id;

    rec_id:=('88000000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid;
    reconciled_at:=now()-interval '30 seconds';
    state:=case when i in (1,6) then 'reconciled'
                when i=4 then 'missing-layer82-receipt'
                else 'execution-receipt-mismatch' end;
    reason:=case state
      when 'reconciled' then 'case-audit-reconcile-exec-complete'
      when 'missing-layer82-receipt' then 'case-audit-reconcile-exec-layer82-receipt-missing'
      else 'case-audit-reconcile-exec-receipt-mismatch' end;
    policy_ok:=true; incident_ok:=true;
    layer82_ok:=case when i=4 then null else true end;
    exec_match:=case when i=4 then null when i=5 then false else true end;
    before_ok:=true; after_ok:=true;

    layer86_snapshot:=jsonb_build_object(
      'layer86EventId',layer86.event_id,
      'targetExecutorEventId',layer86.target_executor_event_id,
      'reconciliationIncidentEventId',layer86.reconciliation_incident_event_id,
      'actionKey',layer86.action_key,'causeClass',layer86.cause_class,
      'policyFingerprint',layer86.policy_fingerprint,
      'eventType',layer86.event_type,'reasonCode',layer86.reason_code,
      'requestedAt',layer86.requested_at
    );

    layer82_snapshot:=case when l82.reconciliation_id is null then null else
      jsonb_build_object(
        'reconciliationId',l82.reconciliation_id,
        'executorEventId',l82.executor_event_id,
        'targetExecutionEventId',l82.target_execution_event_id,
        'verificationId',l82.verification_id,
        'verificationState',l82.verification_state,
        'reconciliationState',l82.reconciliation_state,
        'reasonCode',l82.reason_code,
        'proofIntegrityValid',l82.proof_integrity_valid,
        'receiptMatchesProof',l82.receipt_matches_proof,
        'currentEvaluationMatches',l82.current_evaluation_matches,
        'coverageTargetVisible',l82.coverage_target_visible,
        'coverageTargetMatches',l82.coverage_target_matches,
        'reconciliationProofSha256',l82.reconciliation_proof_sha256,
        'reconciledAt',l82.reconciled_at
      ) end;

    proof:=jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionReconciliationProof',
        'shine-foundation/case-audit-reconciliation-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0','reconciliationId',rec_id,
      'layer86EventId',layer86.event_id,'environment',layer86.environment,
      'targetExecutorEventId',layer86.target_executor_event_id,
      'layer82ReconciliationId',l82.reconciliation_id,
      'reconciliationState',state,'reasonCode',reason,
      'policyIntegrityValid',policy_ok,'incidentBindingValid',incident_ok,
      'layer82ProofIntegrityValid',layer82_ok,
      'executionReceiptMatches',exec_match,
      'beforeCoverageValid',before_ok,'afterCoverageValid',after_ok,
      'layer86ActionResult',layer86.action_result,
      'layer82Receipt',layer82_snapshot,
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false,
      'approvalGranted',false,'executionAuthorityGranted',false,
      'mutationPerformed',false,'reconciledAt',reconciled_at
    );

    proof_hash:=encode(extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),'hex');

    insert into foundation.case_audit_verify_reconcile_exec_reconciliations(
      reconciliation_id,layer86_event_id,environment,target_executor_event_id,
      layer82_reconciliation_id,reconciliation_state,reason_code,
      policy_integrity_valid,incident_binding_valid,
      layer82_proof_integrity_valid,execution_receipt_matches,
      before_coverage_valid,after_coverage_valid,layer86_snapshot,
      layer82_snapshot,reconciliation_proof,reconciliation_proof_sha256,
      reconciled_at
    ) values(
      rec_id,layer86.event_id,layer86.environment,layer86.target_executor_event_id,
      l82.reconciliation_id,state,reason,policy_ok,incident_ok,layer82_ok,
      exec_match,before_ok,after_ok,layer86_snapshot,layer82_snapshot,proof,
      case when i=6 then repeat('f',64) else proof_hash end,reconciled_at
    );
  end loop;
end;
$l88_seed_layer87$;

do $l88_coverage$
declare
  r jsonb;
  layer86_before bigint; layer86_after bigint;
  layer87_before bigint; layer87_after bigint;
  layer82_before bigint; layer82_after bigint;
begin
  select count(*) into layer86_before from foundation.case_audit_verify_reconcile_exec_events;
  select count(*) into layer87_before from foundation.case_audit_verify_reconcile_exec_reconciliations;
  select count(*) into layer82_before from foundation.case_audit_verify_exec_reconciliations;

  r:=foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(
    'production',now(),300,50
  );

  if r->>'state'<>'invalid'
     or r->>'reasonCode'<>'case-audit-reconcile-exec-layer87-receipt-invalid'
     or r->>'successfulLayer86ExecutionCount'<>'6'
     or r->>'layer87ReconciliationRequiredCount'<>'6'
     or r->>'layer87ReconciliationReceiptCount'<>'4'
     or r->>'reconciledCount'<>'1'
     or r->>'pendingCount'<>'1'
     or r->>'overdueCount'<>'1'
     or r->>'invalidLayer87ReconciliationCount'<>'1'
     or r->>'missingLayer82ReceiptCount'<>'1'
     or r->>'invalidLayer82ReceiptCount'<>'0'
     or r->>'executionReceiptMismatchCount'<>'1'
     or r->>'policyDriftCount'<>'0'
     or r->>'incidentDriftCount'<>'0'
     or r->>'coverageDriftCount'<>'0'
     or r->>'problemCount'<>'4'
     or r->>'layer87ReconciliationCoveragePercent'<>'66.67'
     or r->>'healthyLayer87ReconciliationPercent'<>'16.67'
     or r->>'layer87ProofIntegrityRecomputed'<>'true'
     or r->>'linkedLayer82SnapshotRevalidated'<>'true'
     or r->>'layer87ReconciliationPerformed'<>'false'
     or r->>'layer86RerunPerformed'<>'false'
     or r->>'layer82RerunPerformed'<>'false'
     or r->>'layer81RerunPerformed'<>'false'
     or r->>'verificationRerunPerformed'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 88 coverage summary invalid: %',r;
  end if;

  if not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer86EventId'='88000000-0000-4000-8000-000000000702'
      and item->>'coverageState'='pending'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer86EventId'='88000000-0000-4000-8000-000000000703'
      and item->>'coverageState'='overdue'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer86EventId'='88000000-0000-4000-8000-000000000704'
      and item->>'coverageState'='missing-layer82-receipt'
      and item->>'layer87ProofIntegrityValid'='true'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer86EventId'='88000000-0000-4000-8000-000000000706'
      and item->>'coverageState'='invalid-reconciliation'
      and item->>'layer87ProofIntegrityValid'='false'
  ) then
    raise exception 'Layer 88 per-execution classification invalid: %',r;
  end if;

  select count(*) into layer86_after from foundation.case_audit_verify_reconcile_exec_events;
  select count(*) into layer87_after from foundation.case_audit_verify_reconcile_exec_reconciliations;
  select count(*) into layer82_after from foundation.case_audit_verify_exec_reconciliations;

  if layer86_after<>layer86_before
     or layer87_after<>layer87_before
     or layer82_after<>layer82_before then
    raise exception 'Layer 88 coverage reader mutated or reran upstream controls';
  end if;
end;
$l88_coverage$;

do $l88_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER')
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       join pg_roles r on r.oid=a.grantee
       where n.nspname='foundation'
         and p.proname='get_case_audit_reconcile_exec_reconciliation_coverage_v1'
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 88 privilege boundary invalid';
  end if;
end;
$l88_privileges$;

rollback;
