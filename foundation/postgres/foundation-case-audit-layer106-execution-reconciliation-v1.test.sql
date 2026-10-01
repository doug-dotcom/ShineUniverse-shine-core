begin;

-- Five minimal upstream chains ending in Layer-101 source executions.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
) values (
  '10700000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer107"}'::jsonb,
  now()-interval '20 minutes','test:layer107:case-audit-incident'
);

do $l107_seed_upstream$
declare i integer;
begin
  for i in 1..5 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    ) values(
      ('10700000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','10700000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      lpad(to_hex(i),64,'0'),'executed','test-layer107-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer107','chain',i),
      '{}'::jsonb,now()-interval '30 minutes'
    );

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,verification_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10700000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('10700000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      null,'run-independent-verification','verification-omission',
      lpad(to_hex(i+5),64,'0'),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer107','chain',i),
      '{}'::jsonb,now()-interval '25 minutes'
    );

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10700000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('10700000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,'run-independent-reconciliation','reconciliation-omission',
      lpad(to_hex(i+10),64,'0'),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer107','chain',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );

    insert into foundation.case_audit_reconcile_exec_reconcile_exec_events(
      event_id,environment,target_layer86_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10700000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      'production',
      ('10700000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      null,'run-independent-layer87-reconciliation',
      'layer87-reconciliation-omission',
      lpad(to_hex(i+15),64,'0'),'executed',
      'case-audit-overdue-layer87-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer107','chain',i),
      '{}'::jsonb,now()-interval '15 minutes'
    );

    insert into foundation.case_audit_layer92_reconcile_exec_events(
      event_id,environment,target_layer91_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10700000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      'production',
      ('10700000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      null,'run-independent-layer92-reconciliation',
      'layer92-reconciliation-omission',
      lpad(to_hex(i+20),64,'0'),'executed',
      'case-audit-overdue-layer92-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer107','chain',i),
      '{}'::jsonb,now()-interval '10 minutes'
    );

    insert into foundation.case_audit_layer97_reconcile_exec_events(
      event_id,environment,target_layer96_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10700000-0000-4000-8000-'||lpad((1010+i)::text,12,'0'))::uuid,
      'production',
      ('10700000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      null,'run-independent-layer97-reconciliation',
      'layer97-reconciliation-omission',
      lpad(to_hex(i+25),64,'0'),'executed',
      'case-audit-overdue-layer97-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,
      jsonb_build_object(
        'layer96EventId',('10700000-0000-4000-8000-'||lpad((960+i)::text,12,'0')),
        'targetLayer91EventId',('10700000-0000-4000-8000-'||lpad((900+i)::text,12,'0')),
        'eventType','executed','reasonCode','case-audit-overdue-layer97-reconciliation-ran'
      ),
      '{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer107','chain',i),
      '{}'::jsonb,
      now()-interval '8 minutes'
    );
  end loop;
end;
$l107_seed_upstream$;

-- Durable Layer-102 truth for chains 1,3,4,5.
do $l107_seed_layer102$
declare
  i integer;
  e foundation.case_audit_layer97_reconcile_exec_events%rowtype;
  rid uuid;
  proof jsonb;
  proof_hash text;
  reconciled_at timestamptz;
begin
  foreach i in array array[1,3,4,5] loop
    select * into e
    from foundation.case_audit_layer97_reconcile_exec_events
    where event_id=(
      '10700000-0000-4000-8000-'||lpad((1010+i)::text,12,'0')
    )::uuid;

    rid:=('10700000-0000-4000-8000-'||lpad((1020+i)::text,12,'0'))::uuid;
    reconciled_at:=now()-interval '4 minutes';

    proof:=jsonb_build_object(
      'foundationCaseAuditLayer101ExecutionReconciliationProof',
        'shine-foundation/case-audit-layer101-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0',
      'reconciliationId',rid,
      'layer101EventId',e.event_id,
      'environment',e.environment,
      'targetLayer96EventId',e.target_layer96_event_id,
      'layer97ReconciliationId',null,
      'reconciliationState','missing-layer97-receipt',
      'reasonCode','case-audit-layer101-layer97-receipt-missing',
      'policyIntegrityValid',true,
      'incidentBindingValid',true,
      'layer97ProofIntegrityValid',null,
      'executionReceiptMatches',null,
      'beforeCoverageValid',true,
      'afterCoverageValid',true,
      'layer101ActionResult',e.action_result,
      'layer97Receipt',null,
      'layer97RerunPerformed',false,'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
      'layer97ReceiptRewritePerformed',false,'layer96ReceiptRewritePerformed',false,
      'layer92ReceiptRewritePerformed',false,'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false,
      'approvalGranted',false,'executionAuthorityGranted',false,
      'mutationPerformed',false,'reconciledAt',reconciled_at
    );

    proof_hash:=encode(
      extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),'hex'
    );

    insert into foundation.case_audit_layer101_exec_reconciliations(
      reconciliation_id,layer101_event_id,environment,target_layer96_event_id,
      layer97_reconciliation_id,reconciliation_state,reason_code,
      policy_integrity_valid,incident_binding_valid,
      layer97_proof_integrity_valid,execution_receipt_matches,
      before_coverage_valid,after_coverage_valid,layer101_snapshot,
      layer97_snapshot,reconciliation_proof,reconciliation_proof_sha256,reconciled_at
    ) values(
      rid,e.event_id,e.environment,e.target_layer96_event_id,
      null,'missing-layer97-receipt',
      'case-audit-layer101-layer97-receipt-missing',
      true,true,null,null,true,true,
      jsonb_build_object(
        'layer101EventId',e.event_id,
        'targetLayer96EventId',e.target_layer96_event_id,
        'coverageIncidentEventId',e.coverage_incident_event_id,
        'actionKey',e.action_key,'causeClass',e.cause_class,
        'policyFingerprint',e.policy_fingerprint,'eventType',e.event_type,
        'reasonCode',e.reason_code,'requestedAt',e.requested_at
      ),
      null,proof,
      case when i=4 then repeat('f',64) else proof_hash end,
      reconciled_at
    );
  end loop;
end;
$l107_seed_layer102$;

insert into foundation.case_audit_layer102_coverage_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
) values(
  '10700000-0000-4000-8000-000000001041'::uuid,
  'production:case_audit_layer102_reconciliation_coverage',
  'production','case_audit_layer102_reconciliation_coverage',
  'opened','gap','critical','case-audit-layer102-overdue',repeat('9',64),
  now()-interval '10 minutes',300,600,'{"test":"layer107"}'::jsonb,
  now()-interval '1 minute','test:layer107:coverage-incident'
);

do $l107_seed_layer106$
declare
  i integer;
  target foundation.case_audit_layer97_reconcile_exec_events%rowtype;
  l102 foundation.case_audit_layer101_exec_reconciliations%rowtype;
  decision jsonb;
  incident_snapshot jsonb;
  target_snapshot jsonb;
  before_coverage jsonb;
  after_coverage jsonb;
  action_result jsonb;
  fp text;
begin
  decision:=jsonb_build_object(
    'foundationCaseAuditLayer102CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer102-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0','environment','production',
    'incidentState','critical','causeClass','layer102-reconciliation-omission',
    'actionKey','run-independent-layer102-reconciliation',
    'actionClass','evidence','decision','admit',
    'requiredControl','layer-102-bounded-reconciler',
    'reasonCode','case-audit-layer102-response-run-bounded-reconciliation',
    'authorityExpansion',false,
    'automaticLayer102ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,'automaticRepairAllowed',false,
    'layer102ReceiptRewriteAllowed',false,'layer101ReceiptRewriteAllowed',false,
    'layer97ReceiptRewriteAllowed',false,'historyRewriteAllowed',false,
    'layer101RerunAllowed',false,'layer97RerunAllowed',false,
    'layer96RerunAllowed',false,'layer92RerunAllowed',false,
    'layer91RerunAllowed',false,'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false,
    'mutatesLayer102Receipt',false,'mutatesLayer101Receipt',false,
    'mutatesLayer97Receipt',false,
    'rerunsLayer101',false,'rerunsLayer97',false,
    'rerunsLayer96',false,'rerunsLayer92',false,'rerunsLayer91',false,
    'rerunsLayer87',false,'rerunsLayer86',false,'rerunsLayer82',false,
    'rerunsLayer81',false,'rerunsVerification',false,'executesAction',false
  );

  incident_snapshot:=jsonb_build_object(
    'state','critical',
    'currentEvent',jsonb_build_object(
      'eventId','10700000-0000-4000-8000-000000001041',
      'eventType','opened','sourceState','gap',
      'evidenceFingerprint',repeat('9',64)
    )
  );

  before_coverage:=jsonb_build_object(
    'foundationCaseAuditLayer102ReconciliationCoverage',
      'shine-foundation/case-audit-layer102-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production','state','gap',
    'overdueCount',1,'layer102ReconciliationPerformed',false,
    'layer101RerunPerformed',false,'layer97RerunPerformed',false,
    'layer96RerunPerformed',false,'layer92RerunPerformed',false,
    'layer91RerunPerformed',false,'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  after_coverage:=jsonb_build_object(
    'foundationCaseAuditLayer102ReconciliationCoverage',
      'shine-foundation/case-audit-layer102-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production','state','normal',
    'overdueCount',0,'layer102ReconciliationPerformed',false,
    'layer101RerunPerformed',false,'layer97RerunPerformed',false,
    'layer96RerunPerformed',false,'layer92RerunPerformed',false,
    'layer91RerunPerformed',false,'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  for i in 1..5 loop
    select * into target
    from foundation.case_audit_layer97_reconcile_exec_events
    where event_id=(
      '10700000-0000-4000-8000-'||lpad((1010+i)::text,12,'0')
    )::uuid;

    select * into l102
    from foundation.case_audit_layer101_exec_reconciliations
    where layer101_event_id=target.event_id;

    target_snapshot:=jsonb_build_object(
      'layer101EventId',target.event_id,
      'targetLayer96EventId',target.target_layer96_event_id,
      'coverageIncidentEventId',target.coverage_incident_event_id,
      'actionKey',target.action_key,'causeClass',target.cause_class,
      'policyFingerprint',target.policy_fingerprint,'eventType',target.event_type,
      'reasonCode',target.reason_code,'requestedAt',target.requested_at,
      'ageSeconds',600,'reconciliationGraceSeconds',300,
      'layer102ReconciliationId',null,'layer102ReconciliationState',null,
      'layer102ReconciliationAbsent',true
    );

    if l102.reconciliation_id is null then
      action_result:=jsonb_build_object(
        'foundationCaseAuditLayer101ExecutionReconciliation',
          'shine-foundation/case-audit-layer101-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId','10700000-0000-4000-8000-000000001099',
        'layer101EventId',target.event_id,
        'targetLayer96EventId',target.target_layer96_event_id,
        'layer97ReconciliationId',null,
        'reconciliationState','missing-layer97-receipt',
        'reasonCode','case-audit-layer101-layer97-receipt-missing',
        'reconciliationProofSha256',repeat('8',64),
        'layer97RerunPerformed',false,'layer96RerunPerformed',false,
        'layer92RerunPerformed',false,'layer91RerunPerformed',false,
        'layer87RerunPerformed',false,'layer86RerunPerformed',false,
        'layer82RerunPerformed',false,'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,'mutationPerformed',false
      );
    else
      action_result:=jsonb_build_object(
        'foundationCaseAuditLayer101ExecutionReconciliation',
          'shine-foundation/case-audit-layer101-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId',l102.reconciliation_id,
        'layer101EventId',l102.layer101_event_id,
        'targetLayer96EventId',l102.target_layer96_event_id,
        'layer97ReconciliationId',l102.layer97_reconciliation_id,
        'reconciliationState',l102.reconciliation_state,
        'reasonCode',l102.reason_code,
        'reconciliationProofSha256',
          case when i=3 then repeat('0',64) else l102.reconciliation_proof_sha256 end,
        'layer97RerunPerformed',false,'layer96RerunPerformed',false,
        'layer92RerunPerformed',false,'layer91RerunPerformed',false,
        'layer87RerunPerformed',false,'layer86RerunPerformed',false,
        'layer82RerunPerformed',false,'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,'mutationPerformed',false
      );
    end if;

    fp:=foundation.case_audit_layer102_reconcile_exec_policy_fp_v1(
      decision,incident_snapshot,target_snapshot
    );

    insert into foundation.case_audit_layer102_reconcile_exec_events(
      event_id,environment,target_layer101_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10700000-0000-4000-8000-'||lpad((1060+i)::text,12,'0'))::uuid,
      'production',target.event_id,
      '10700000-0000-4000-8000-000000001041'::uuid,
      'run-independent-layer102-reconciliation','layer102-reconciliation-omission',
      case when i=5 then repeat('a',64) else fp end,
      'executed','case-audit-overdue-layer102-reconciliation-ran',
      decision,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,now()-interval '30 seconds'
    );
  end loop;
end;
$l107_seed_layer106$;

do $l107_evaluate$
declare r jsonb;
begin
  r:=foundation.evaluate_case_audit_layer106_execution_outcome_v1(
    '10700000-0000-4000-8000-000000001061'::uuid,now()
  );
  if r->>'reconciliationState'<>'reconciled'
     or r->>'layer102ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'true'
     or r->>'policyIntegrityValid'<>'true'
     or r->>'incidentBindingValid'<>'true' then
    raise exception 'Layer 107 truthful execution invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer106_execution_outcome_v1(
    '10700000-0000-4000-8000-000000001062'::uuid,now()
  );
  if r->>'reconciliationState'<>'missing-layer102-receipt' then
    raise exception 'Layer 107 missing Layer-102 truth invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer106_execution_outcome_v1(
    '10700000-0000-4000-8000-000000001063'::uuid,now()
  );
  if r->>'reconciliationState'<>'execution-receipt-mismatch'
     or r->>'layer102ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'false' then
    raise exception 'Layer 107 execution mismatch invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer106_execution_outcome_v1(
    '10700000-0000-4000-8000-000000001064'::uuid,now()
  );
  if r->>'reconciliationState'<>'invalid-layer102-receipt'
     or r->>'layer102ProofIntegrityValid'<>'false' then
    raise exception 'Layer 107 invalid Layer-102 integrity precedence failed: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer106_execution_outcome_v1(
    '10700000-0000-4000-8000-000000001065'::uuid,now()
  );
  if r->>'reconciliationState'<>'policy-drift'
     or r->>'layer102ProofIntegrityValid'<>'true'
     or r->>'policyIntegrityValid'<>'false' then
    raise exception 'Layer 107 policy drift invalid: %',r;
  end if;
end;
$l107_evaluate$;

set local role service_role;

do $l107_reconcile$
declare
  i integer;
  r jsonb;
  replay jsonb;
  s jsonb;
  l106_before bigint; l106_after bigint;
  l102_before bigint; l102_after bigint;
  l101_before bigint; l101_after bigint;
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer106_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 107 service-role reconciler unavailable';
  end if;

  if has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer101_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 107 found direct Layer-102 bypass reopened';
  end if;

  select count(*) into l106_before
  from foundation.case_audit_layer102_reconcile_exec_events;
  select count(*) into l102_before
  from foundation.case_audit_layer101_exec_reconciliations;
  select count(*) into l101_before
  from foundation.case_audit_layer97_reconcile_exec_events;

  for i in 1..5 loop
    r:=foundation.run_case_audit_layer106_execution_reconciliation_v1(
      ('10700000-0000-4000-8000-'||lpad((1060+i)::text,12,'0'))::uuid,now()
    );
    if r->>'status'<>'recorded'
       or r->>'layer102RerunPerformed'<>'false'
       or r->>'layer101RerunPerformed'<>'false'
       or r->>'mutationPerformed'<>'false' then
      raise exception 'Layer 107 receipt invalid: %',r;
    end if;
  end loop;

  replay:=foundation.run_case_audit_layer106_execution_reconciliation_v1(
    '10700000-0000-4000-8000-000000001061'::uuid,now()
  );
  if replay->>'status'<>'existing' then
    raise exception 'Layer 107 semantic replay invalid: %',replay;
  end if;

  select count(*) into l106_after
  from foundation.case_audit_layer102_reconcile_exec_events;
  select count(*) into l102_after
  from foundation.case_audit_layer101_exec_reconciliations;
  select count(*) into l101_after
  from foundation.case_audit_layer97_reconcile_exec_events;

  if l106_after<>l106_before or l102_after<>l102_before or l101_after<>l101_before then
    raise exception 'Layer 107 unexpectedly reran or mutated upstream controls';
  end if;

  s:=foundation.get_case_audit_layer106_execution_reconciliation_summary_v1(
    'production',25
  );

  if s->>'totalCount'<>'5'
     or s->>'reconciledCount'<>'1'
     or s->>'missingLayer102ReceiptCount'<>'1'
     or s->>'invalidLayer102ReceiptCount'<>'1'
     or s->>'executionReceiptMismatchCount'<>'1'
     or s->>'policyDriftCount'<>'1'
     or s->>'incidentDriftCount'<>'0'
     or s->>'coverageDriftCount'<>'0'
     or s->>'problemCount'<>'4' then
    raise exception 'Layer 107 summary invalid: %',s;
  end if;
end;
$l107_reconcile$;

reset role;

do $l107_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_layer106_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_layer106_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_layer106_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_layer106_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role','foundation.case_audit_layer106_exec_reconciliations','INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer106_execution_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer106_execution_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER') then
    raise exception 'Layer 107 privilege boundary invalid';
  end if;
end;
$l107_privileges$;

do $l107_append_only$
declare id uuid;
begin
  select reconciliation_id into id
  from foundation.case_audit_layer106_exec_reconciliations
  limit 1;
  begin
    update foundation.case_audit_layer106_exec_reconciliations
    set reason_code='mutation' where reconciliation_id=id;
    raise exception 'Layer 107 reconciliation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l107_append_only$;

rollback;
