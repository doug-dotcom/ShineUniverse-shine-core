begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '92000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer92"}'::jsonb,
  now()-interval '20 minutes','test:layer92:case-audit-incident'
);

do $l92_seed_layer76$
declare i integer;
begin
  for i in 1..5 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      ('92000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','92000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      repeat(i::text,64),'executed','test-layer92-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer92','chain',i),
      '{}'::jsonb,now()-interval '25 minutes'
    );
  end loop;
end;
$l92_seed_layer76$;

-- Five successful Layer-81 targets provide the FK spine for five Layer-86 claims.
do $l92_seed_layer81$
declare i integer;
begin
  for i in 1..5 loop
    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,verification_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    )
    values(
      ('92000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('92000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      null,
      'run-independent-verification','verification-omission',
      repeat((i+1)::text,64),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer92','chain',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );
  end loop;
end;
$l92_seed_layer81$;


-- Five Layer-86 executions. Layer 87 will reconcile 1,3,5; chain 4 gets an
-- intentionally malformed Layer-87 receipt; chain 2 has no Layer-87 truth.
do $l92_seed_layer86$
declare i integer;
begin
  for i in 1..5 loop
    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    )
    values(
      ('92000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('92000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,
      'run-independent-reconciliation','reconciliation-omission',
      repeat((i+5)::text,64),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer92','chain',i),
      '{}'::jsonb,now()-interval '10 minutes'
    );
  end loop;
end;
$l92_seed_layer86$;


insert into foundation.case_audit_reconcile_exec_coverage_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
)
values(
  '92000000-0000-4000-8000-000000000901'::uuid,
  'production:case_audit_reconciliation_execution_reconciliation_coverage',
  'production','case_audit_reconciliation_execution_reconciliation_coverage',
  'opened','gap','critical','case-audit-reconcile-exec-layer87-overdue',
  repeat('9',64),now()-interval '10 minutes',300,600,
  '{"test":"layer92"}'::jsonb,now()-interval '2 minutes',
  'test:layer92:coverage-incident'
);


do $l92_seed_real_layer87$
declare r jsonb; i integer;
begin
  foreach i in array array[1,3,5] loop
    r:=foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
      ('92000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      now()
    );
    if r->>'status'<>'recorded'
       or r->>'reconciliationState'<>'missing-layer82-receipt' then
      raise exception 'Layer 92 real Layer-87 seed invalid: %',r;
    end if;
  end loop;
end;
$l92_seed_real_layer87$;


-- Deliberately malformed Layer-87 receipt for integrity precedence.
insert into foundation.case_audit_verify_reconcile_exec_reconciliations(
  reconciliation_id,layer86_event_id,environment,target_executor_event_id,
  layer82_reconciliation_id,reconciliation_state,reason_code,
  policy_integrity_valid,incident_binding_valid,layer82_proof_integrity_valid,
  execution_receipt_matches,before_coverage_valid,after_coverage_valid,
  layer86_snapshot,layer82_snapshot,reconciliation_proof,
  reconciliation_proof_sha256,reconciled_at
)
values(
  '92000000-0000-4000-8000-000000000804'::uuid,
  '92000000-0000-4000-8000-000000000704'::uuid,
  'production','92000000-0000-4000-8000-000000000304'::uuid,
  null,'missing-layer82-receipt','case-audit-reconcile-exec-layer82-receipt-missing',
  false,false,null,null,false,false,
  jsonb_build_object(
    'layer86EventId','92000000-0000-4000-8000-000000000704',
    'targetExecutorEventId','92000000-0000-4000-8000-000000000304',
    'reconciliationIncidentEventId',null,
    'actionKey','run-independent-reconciliation',
    'causeClass','reconciliation-omission',
    'policyFingerprint',repeat('9',64),
    'eventType','executed',
    'reasonCode','case-audit-overdue-reconciliation-layer82-ran',
    'requestedAt',(select requested_at from foundation.case_audit_verify_reconcile_exec_events
      where event_id='92000000-0000-4000-8000-000000000704'::uuid)
  ),
  null,
  '{"bogus":true}'::jsonb,
  repeat('f',64),now()
);


-- Build five Layer-91 execution claims around current Layer-90 semantics.
do $l92_seed_layer91$
declare
  i integer;
  target foundation.case_audit_verify_reconcile_exec_events%rowtype;
  l87 foundation.case_audit_verify_reconcile_exec_reconciliations%rowtype;
  decision jsonb;
  incident_snapshot jsonb;
  target_snapshot jsonb;
  before_coverage jsonb;
  after_coverage jsonb;
  action_result jsonb;
  fp text;
begin
  decision:=jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionCoverageIncidentResponseDecision',
      'shine-foundation/case-audit-reconciliation-execution-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'incidentState','critical',
    'causeClass','layer87-reconciliation-omission',
    'actionKey','run-independent-layer87-reconciliation',
    'actionClass','evidence',
    'decision','admit',
    'requiredControl','layer-87-bounded-reconciler',
    'reasonCode','case-audit-layer87-response-run-bounded-reconciliation',
    'authorityExpansion',false,
    'automaticLayer87ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'layer86ReceiptRewriteAllowed',false,
    'layer82ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'mutatesLayer87Receipt',false,
    'mutatesLayer86Receipt',false,
    'mutatesLayer82Receipt',false,
    'rerunsLayer86',false,
    'rerunsLayer82',false,
    'rerunsLayer81',false,
    'rerunsVerification',false,
    'executesAction',false
  );

  incident_snapshot:=jsonb_build_object(
    'state','critical',
    'currentEvent',jsonb_build_object(
      'eventId','92000000-0000-4000-8000-000000000901',
      'eventType','opened','sourceState','gap',
      'evidenceFingerprint',repeat('9',64)
    )
  );

  before_coverage:=jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionReconciliationCoverage',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production',
    'state','gap','reasonCode','case-audit-reconcile-exec-layer87-overdue',
    'overdueCount',1,
    'layer87ReconciliationPerformed',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  after_coverage:=jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionReconciliationCoverage',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production',
    'state','normal','reasonCode','case-audit-reconcile-exec-layer87-covered',
    'overdueCount',0,
    'layer87ReconciliationPerformed',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  for i in 1..5 loop
    select * into target
    from foundation.case_audit_verify_reconcile_exec_events
    where event_id=(
      '92000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')
    )::uuid;

    select * into l87
    from foundation.case_audit_verify_reconcile_exec_reconciliations
    where layer86_event_id=target.event_id;

    target_snapshot:=jsonb_build_object(
      'layer86EventId',target.event_id,
      'targetExecutorEventId',target.target_executor_event_id,
      'reconciliationIncidentEventId',target.reconciliation_incident_event_id,
      'actionKey',target.action_key,
      'causeClass',target.cause_class,
      'policyFingerprint',target.policy_fingerprint,
      'eventType',target.event_type,
      'reasonCode',target.reason_code,
      'requestedAt',target.requested_at,
      'ageSeconds',600,
      'reconciliationGraceSeconds',300,
      'layer87ReconciliationId',null,
      'layer87ReconciliationState',null,
      'layer87ReconciliationAbsent',true
    );

    if i=2 then
      action_result:=jsonb_build_object(
        'foundationCaseAuditReconciliationExecutionReconciliation',
          'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId','92000000-0000-4000-8000-000000000899',
        'layer86EventId',target.event_id,
        'targetExecutorEventId',target.target_executor_event_id,
        'layer82ReconciliationId',null,
        'reconciliationState','missing-layer82-receipt',
        'reasonCode','case-audit-reconcile-exec-layer82-receipt-missing',
        'reconciliationProofSha256',repeat('8',64),
        'layer82RerunPerformed',false,'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,'mutationPerformed',false
      );
    else
      action_result:=jsonb_build_object(
        'foundationCaseAuditReconciliationExecutionReconciliation',
          'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId',l87.reconciliation_id,
        'layer86EventId',l87.layer86_event_id,
        'targetExecutorEventId',l87.target_executor_event_id,
        'layer82ReconciliationId',l87.layer82_reconciliation_id,
        'reconciliationState',l87.reconciliation_state,
        'reasonCode',l87.reason_code,
        'reconciliationProofSha256',
          case when i=3 then repeat('0',64)
               else l87.reconciliation_proof_sha256 end,
        'layer82RerunPerformed',false,'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,'mutationPerformed',false
      );
    end if;

    fp:=foundation.case_audit_reconcile_exec_reconcile_exec_policy_fp_v1(
      decision,incident_snapshot,target_snapshot
    );

    insert into foundation.case_audit_reconcile_exec_reconcile_exec_events(
      event_id,environment,target_layer86_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    )
    values(
      ('92000000-0000-4000-8000-'||lpad((910+i)::text,12,'0'))::uuid,
      'production',target.event_id,
      '92000000-0000-4000-8000-000000000901'::uuid,
      'run-independent-layer87-reconciliation',
      'layer87-reconciliation-omission',
      case when i=5 then repeat('a',64) else fp end,
      'executed','case-audit-overdue-layer87-reconciliation-ran',
      decision,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,now()-interval '30 seconds'
    );
  end loop;
end;
$l92_seed_layer91$;


do $l92_evaluate$
declare r jsonb;
begin
  r:=foundation.evaluate_case_audit_layer91_execution_outcome_v1(
    '92000000-0000-4000-8000-000000000911'::uuid,now()
  );
  if r->>'reconciliationState'<>'reconciled'
     or r->>'policyIntegrityValid'<>'true'
     or r->>'incidentBindingValid'<>'true'
     or r->>'layer87ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'true'
     or r->>'beforeCoverageValid'<>'true'
     or r->>'afterCoverageValid'<>'true' then
    raise exception 'Layer 92 truthful Layer-91 reconciliation invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer91_execution_outcome_v1(
    '92000000-0000-4000-8000-000000000912'::uuid,now()
  );
  if r->>'reconciliationState'<>'missing-layer87-receipt' then
    raise exception 'Layer 92 missing Layer-87 truth invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer91_execution_outcome_v1(
    '92000000-0000-4000-8000-000000000913'::uuid,now()
  );
  if r->>'reconciliationState'<>'execution-receipt-mismatch'
     or r->>'layer87ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'false' then
    raise exception 'Layer 92 execution mismatch invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer91_execution_outcome_v1(
    '92000000-0000-4000-8000-000000000914'::uuid,now()
  );
  if r->>'reconciliationState'<>'invalid-layer87-receipt'
     or r->>'layer87ProofIntegrityValid'<>'false' then
    raise exception 'Layer 92 invalid Layer-87 integrity precedence failed: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer91_execution_outcome_v1(
    '92000000-0000-4000-8000-000000000915'::uuid,now()
  );
  if r->>'reconciliationState'<>'policy-drift'
     or r->>'layer87ProofIntegrityValid'<>'true'
     or r->>'policyIntegrityValid'<>'false' then
    raise exception 'Layer 92 policy drift invalid: %',r;
  end if;
end;
$l92_evaluate$;


set local role service_role;

do $l92_reconcile$
declare
  i integer;
  r jsonb;
  replay jsonb;
  summary jsonb;
  layer91_before bigint;
  layer91_after bigint;
  layer87_before bigint;
  layer87_after bigint;
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 92 service-role reconciler unavailable';
  end if;

  select count(*) into layer91_before
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;
  select count(*) into layer87_before
  from foundation.case_audit_verify_reconcile_exec_reconciliations;

  for i in 1..5 loop
    r:=foundation.run_case_audit_layer91_execution_reconciliation_v1(
      ('92000000-0000-4000-8000-'||lpad((910+i)::text,12,'0'))::uuid,
      now()
    );
    if r->>'status'<>'recorded'
       or r->>'layer87RerunPerformed'<>'false'
       or r->>'layer86RerunPerformed'<>'false'
       or r->>'layer82RerunPerformed'<>'false'
       or r->>'layer81RerunPerformed'<>'false'
       or r->>'verificationRerunPerformed'<>'false'
       or r->>'mutationPerformed'<>'false' then
      raise exception 'Layer 92 receipt invalid: %',r;
    end if;
  end loop;

  replay:=foundation.run_case_audit_layer91_execution_reconciliation_v1(
    '92000000-0000-4000-8000-000000000911'::uuid,now()
  );
  if replay->>'status'<>'existing' then
    raise exception 'Layer 92 semantic replay invalid: %',replay;
  end if;

  select count(*) into layer91_after
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;
  select count(*) into layer87_after
  from foundation.case_audit_verify_reconcile_exec_reconciliations;

  if layer91_after<>layer91_before or layer87_after<>layer87_before then
    raise exception 'Layer 92 unexpectedly reran or mutated upstream controls';
  end if;

  summary:=foundation.get_case_audit_layer91_execution_reconciliation_summary_v1(
    'production',25
  );

  if summary->>'totalCount'<>'5'
     or summary->>'reconciledCount'<>'1'
     or summary->>'missingLayer87ReceiptCount'<>'1'
     or summary->>'invalidLayer87ReceiptCount'<>'1'
     or summary->>'executionReceiptMismatchCount'<>'1'
     or summary->>'policyDriftCount'<>'1'
     or summary->>'incidentDriftCount'<>'0'
     or summary->>'coverageDriftCount'<>'0'
     or summary->>'problemCount'<>'4'
     or summary->>'layer87RerunPerformed'<>'false'
     or summary->>'layer86RerunPerformed'<>'false'
     or summary->>'mutationPerformed'<>'false' then
    raise exception 'Layer 92 summary invalid: %',summary;
  end if;
end;
$l92_reconcile$;

reset role;


do $l92_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer91_execution_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer91_execution_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER')
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       join pg_roles rr on rr.oid=a.grantee
       where n.nspname='foundation'
         and p.proname='get_case_audit_layer91_execution_reconciliation_summary_v1'
         and rr.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     ) then
    raise exception 'Layer 92 privilege boundary invalid';
  end if;
end;
$l92_privileges$;


do $l92_append_only$
declare id uuid;
begin
  select reconciliation_id into id
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations
  limit 1;

  begin
    update foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations
    set reason_code='mutation'
    where reconciliation_id=id;
    raise exception 'Layer 92 reconciliation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l92_append_only$;

rollback;
