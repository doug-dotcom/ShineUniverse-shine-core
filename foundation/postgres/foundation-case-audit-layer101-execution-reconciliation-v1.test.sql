begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
) values (
  '10200000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer102"}'::jsonb,
  now()-interval '20 minutes','test:layer102:case-audit-incident'
);

do $l102_seed_upstream$
declare i integer;
begin
  for i in 1..5 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    ) values(
      ('10200000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','10200000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      lpad(to_hex(i),64,'0'),'executed','test-layer102-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer102','chain',i),
      '{}'::jsonb,now()-interval '30 minutes'
    );

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,verification_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10200000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('10200000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      null,'run-independent-verification','verification-omission',
      lpad(to_hex(i+5),64,'0'),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer102','chain',i),
      '{}'::jsonb,now()-interval '25 minutes'
    );

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10200000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('10200000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,'run-independent-reconciliation','reconciliation-omission',
      lpad(to_hex(i+10),64,'0'),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer102','chain',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );

    insert into foundation.case_audit_reconcile_exec_reconcile_exec_events(
      event_id,environment,target_layer86_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10200000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      'production',
      ('10200000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      null,'run-independent-layer87-reconciliation',
      'layer87-reconciliation-omission',
      lpad(to_hex(i+15),64,'0'),'executed',
      'case-audit-overdue-layer87-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer102','chain',i),
      '{}'::jsonb,now()-interval '15 minutes'
    );

    insert into foundation.case_audit_layer92_reconcile_exec_events(
      event_id,environment,target_layer91_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10200000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      'production',
      ('10200000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      null,'run-independent-layer92-reconciliation',
      'layer92-reconciliation-omission',
      lpad(to_hex(i+20),64,'0'),'executed',
      'case-audit-overdue-layer92-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer102','chain',i),
      '{}'::jsonb,now()-interval '10 minutes'
    );
  end loop;
end;
$l102_seed_upstream$;

-- Durable Layer-97 truth for chains 1,3,4,5. Each is a valid negative receipt
-- except chain 4, whose proof hash is deliberately corrupted.
do $l102_seed_layer97$
declare
  i integer;
  e foundation.case_audit_layer92_reconcile_exec_events%rowtype;
  rid uuid;
  proof jsonb;
  proof_hash text;
  reconciled_at timestamptz;
begin
  foreach i in array array[1,3,4,5] loop
    select * into e
    from foundation.case_audit_layer92_reconcile_exec_events
    where event_id=(
      '10200000-0000-4000-8000-'||lpad((960+i)::text,12,'0')
    )::uuid;

    rid:=('10200000-0000-4000-8000-'||lpad((970+i)::text,12,'0'))::uuid;
    reconciled_at:=now()-interval '4 minutes';

    proof:=jsonb_build_object(
      'foundationCaseAuditLayer96ExecutionReconciliationProof',
        'shine-foundation/case-audit-layer96-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0',
      'reconciliationId',rid,
      'layer96EventId',e.event_id,
      'environment',e.environment,
      'targetLayer91EventId',e.target_layer91_event_id,
      'layer92ReconciliationId',null,
      'reconciliationState','missing-layer92-receipt',
      'reasonCode','case-audit-layer96-layer92-receipt-missing',
      'policyIntegrityValid',true,
      'incidentBindingValid',true,
      'layer92ProofIntegrityValid',null,
      'executionReceiptMatches',null,
      'beforeCoverageValid',true,
      'afterCoverageValid',true,
      'layer96ActionResult',e.action_result,
      'layer92Receipt',null,
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'layer92ReceiptRewritePerformed',false,
      'layer91ReceiptRewritePerformed',false,
      'layer87ReceiptRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false,
      'approvalGranted',false,
      'executionAuthorityGranted',false,
      'mutationPerformed',false,
      'reconciledAt',reconciled_at
    );

    proof_hash:=encode(
      extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),'hex'
    );

    insert into foundation.case_audit_layer96_exec_reconciliations(
      reconciliation_id,layer96_event_id,environment,target_layer91_event_id,
      layer92_reconciliation_id,reconciliation_state,reason_code,
      policy_integrity_valid,incident_binding_valid,
      layer92_proof_integrity_valid,execution_receipt_matches,
      before_coverage_valid,after_coverage_valid,layer96_snapshot,
      layer92_snapshot,reconciliation_proof,reconciliation_proof_sha256,
      reconciled_at
    ) values(
      rid,e.event_id,e.environment,e.target_layer91_event_id,
      null,'missing-layer92-receipt',
      'case-audit-layer96-layer92-receipt-missing',
      true,true,null,null,true,true,
      jsonb_build_object(
        'layer96EventId',e.event_id,
        'targetLayer91EventId',e.target_layer91_event_id,
        'coverageIncidentEventId',e.coverage_incident_event_id,
        'actionKey',e.action_key,
        'causeClass',e.cause_class,
        'policyFingerprint',e.policy_fingerprint,
        'eventType',e.event_type,
        'reasonCode',e.reason_code,
        'requestedAt',e.requested_at
      ),
      null,proof,
      case when i=4 then repeat('f',64) else proof_hash end,
      reconciled_at
    );
  end loop;
end;
$l102_seed_layer97$;

insert into foundation.case_audit_layer97_coverage_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
) values(
  '10200000-0000-4000-8000-000000000991'::uuid,
  'production:case_audit_layer97_reconciliation_coverage',
  'production','case_audit_layer97_reconciliation_coverage',
  'opened','gap','critical','case-audit-layer97-overdue',repeat('9',64),
  now()-interval '10 minutes',300,600,'{"test":"layer102"}'::jsonb,
  now()-interval '1 minute','test:layer102:coverage-incident'
);

do $l102_seed_layer101$
declare
  i integer;
  target foundation.case_audit_layer92_reconcile_exec_events%rowtype;
  l97 foundation.case_audit_layer96_exec_reconciliations%rowtype;
  decision jsonb;
  incident_snapshot jsonb;
  target_snapshot jsonb;
  before_coverage jsonb;
  after_coverage jsonb;
  action_result jsonb;
  fp text;
begin
  decision:=jsonb_build_object(
    'foundationCaseAuditLayer97CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer97-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0','environment','production',
    'incidentState','critical','causeClass','layer97-reconciliation-omission',
    'actionKey','run-independent-layer97-reconciliation',
    'actionClass','evidence','decision','admit',
    'requiredControl','layer-97-bounded-reconciler',
    'reasonCode','case-audit-layer97-response-run-bounded-reconciliation',
    'authorityExpansion',false,
    'automaticLayer97ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,'automaticRepairAllowed',false,
    'layer97ReceiptRewriteAllowed',false,'layer96ReceiptRewriteAllowed',false,
    'layer92ReceiptRewriteAllowed',false,'historyRewriteAllowed',false,
    'layer96RerunAllowed',false,'layer92RerunAllowed',false,
    'layer91RerunAllowed',false,'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false,
    'mutatesLayer97Receipt',false,'mutatesLayer96Receipt',false,
    'mutatesLayer92Receipt',false,'rerunsLayer96',false,'rerunsLayer92',false,
    'rerunsLayer91',false,'rerunsLayer87',false,'rerunsLayer86',false,
    'rerunsLayer82',false,'rerunsLayer81',false,'rerunsVerification',false,
    'executesAction',false
  );

  incident_snapshot:=jsonb_build_object(
    'state','critical',
    'currentEvent',jsonb_build_object(
      'eventId','10200000-0000-4000-8000-000000000991',
      'eventType','opened','sourceState','gap',
      'evidenceFingerprint',repeat('9',64)
    )
  );

  before_coverage:=jsonb_build_object(
    'foundationCaseAuditLayer97ReconciliationCoverage',
      'shine-foundation/case-audit-layer97-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production','state','gap',
    'overdueCount',1,'layer97ReconciliationPerformed',false,
    'layer96RerunPerformed',false,'layer92RerunPerformed',false,
    'layer91RerunPerformed',false,'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  after_coverage:=jsonb_build_object(
    'foundationCaseAuditLayer97ReconciliationCoverage',
      'shine-foundation/case-audit-layer97-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production','state','normal',
    'overdueCount',0,'layer97ReconciliationPerformed',false,
    'layer96RerunPerformed',false,'layer92RerunPerformed',false,
    'layer91RerunPerformed',false,'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  for i in 1..5 loop
    select * into target
    from foundation.case_audit_layer92_reconcile_exec_events
    where event_id=(
      '10200000-0000-4000-8000-'||lpad((960+i)::text,12,'0')
    )::uuid;

    select * into l97
    from foundation.case_audit_layer96_exec_reconciliations
    where layer96_event_id=target.event_id;

    target_snapshot:=jsonb_build_object(
      'layer96EventId',target.event_id,
      'targetLayer91EventId',target.target_layer91_event_id,
      'coverageIncidentEventId',target.coverage_incident_event_id,
      'actionKey',target.action_key,'causeClass',target.cause_class,
      'policyFingerprint',target.policy_fingerprint,'eventType',target.event_type,
      'reasonCode',target.reason_code,'requestedAt',target.requested_at,
      'ageSeconds',600,'reconciliationGraceSeconds',300,
      'layer97ReconciliationId',null,'layer97ReconciliationState',null,
      'layer97ReconciliationAbsent',true
    );

    if l97.reconciliation_id is null then
      action_result:=jsonb_build_object(
        'foundationCaseAuditLayer96ExecutionReconciliation',
          'shine-foundation/case-audit-layer96-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId','10200000-0000-4000-8000-000000000899',
        'layer96EventId',target.event_id,
        'targetLayer91EventId',target.target_layer91_event_id,
        'layer92ReconciliationId',null,
        'reconciliationState','missing-layer92-receipt',
        'reasonCode','case-audit-layer96-layer92-receipt-missing',
        'reconciliationProofSha256',repeat('8',64),
        'layer92RerunPerformed',false,'layer91RerunPerformed',false,
        'layer87RerunPerformed',false,'layer86RerunPerformed',false,
        'layer82RerunPerformed',false,'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,'mutationPerformed',false
      );
    else
      action_result:=jsonb_build_object(
        'foundationCaseAuditLayer96ExecutionReconciliation',
          'shine-foundation/case-audit-layer96-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId',l97.reconciliation_id,
        'layer96EventId',l97.layer96_event_id,
        'targetLayer91EventId',l97.target_layer91_event_id,
        'layer92ReconciliationId',l97.layer92_reconciliation_id,
        'reconciliationState',l97.reconciliation_state,
        'reasonCode',l97.reason_code,
        'reconciliationProofSha256',
          case when i=3 then repeat('0',64) else l97.reconciliation_proof_sha256 end,
        'layer92RerunPerformed',false,'layer91RerunPerformed',false,
        'layer87RerunPerformed',false,'layer86RerunPerformed',false,
        'layer82RerunPerformed',false,'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,'mutationPerformed',false
      );
    end if;

    fp:=foundation.case_audit_layer97_reconcile_exec_policy_fp_v1(
      decision,incident_snapshot,target_snapshot
    );

    insert into foundation.case_audit_layer97_reconcile_exec_events(
      event_id,environment,target_layer96_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10200000-0000-4000-8000-'||lpad((1010+i)::text,12,'0'))::uuid,
      'production',target.event_id,
      '10200000-0000-4000-8000-000000000991'::uuid,
      'run-independent-layer97-reconciliation','layer97-reconciliation-omission',
      case when i=5 then repeat('a',64) else fp end,
      'executed','case-audit-overdue-layer97-reconciliation-ran',
      decision,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,now()-interval '30 seconds'
    );
  end loop;
end;
$l102_seed_layer101$;

do $l102_evaluate$
declare r jsonb;
begin
  r:=foundation.evaluate_case_audit_layer101_execution_outcome_v1(
    '10200000-0000-4000-8000-000000001011'::uuid,now()
  );
  if r->>'reconciliationState'<>'reconciled'
     or r->>'layer97ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'true'
     or r->>'policyIntegrityValid'<>'true'
     or r->>'incidentBindingValid'<>'true' then
    raise exception 'Layer 102 truthful execution invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer101_execution_outcome_v1(
    '10200000-0000-4000-8000-000000001012'::uuid,now()
  );
  if r->>'reconciliationState'<>'missing-layer97-receipt' then
    raise exception 'Layer 102 missing Layer-97 truth invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer101_execution_outcome_v1(
    '10200000-0000-4000-8000-000000001013'::uuid,now()
  );
  if r->>'reconciliationState'<>'execution-receipt-mismatch'
     or r->>'layer97ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'false' then
    raise exception 'Layer 102 execution mismatch invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer101_execution_outcome_v1(
    '10200000-0000-4000-8000-000000001014'::uuid,now()
  );
  if r->>'reconciliationState'<>'invalid-layer97-receipt'
     or r->>'layer97ProofIntegrityValid'<>'false' then
    raise exception 'Layer 102 invalid Layer-97 integrity precedence failed: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer101_execution_outcome_v1(
    '10200000-0000-4000-8000-000000001015'::uuid,now()
  );
  if r->>'reconciliationState'<>'policy-drift'
     or r->>'layer97ProofIntegrityValid'<>'true'
     or r->>'policyIntegrityValid'<>'false' then
    raise exception 'Layer 102 policy drift invalid: %',r;
  end if;
end;
$l102_evaluate$;

set local role service_role;

do $l102_reconcile$
declare
  i integer;
  r jsonb;
  replay jsonb;
  s jsonb;
  l101_before bigint; l101_after bigint;
  l97_before bigint; l97_after bigint;
  l96_before bigint; l96_after bigint;
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer101_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 102 service-role reconciler unavailable';
  end if;

  if has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 102 found direct Layer-97 bypass reopened';
  end if;

  select count(*) into l101_before
  from foundation.case_audit_layer97_reconcile_exec_events;
  select count(*) into l97_before
  from foundation.case_audit_layer96_exec_reconciliations;
  select count(*) into l96_before
  from foundation.case_audit_layer92_reconcile_exec_events;

  for i in 1..5 loop
    r:=foundation.run_case_audit_layer101_execution_reconciliation_v1(
      ('10200000-0000-4000-8000-'||lpad((1010+i)::text,12,'0'))::uuid,now()
    );
    if r->>'status'<>'recorded'
       or r->>'layer97RerunPerformed'<>'false'
       or r->>'layer96RerunPerformed'<>'false'
       or r->>'mutationPerformed'<>'false' then
      raise exception 'Layer 102 receipt invalid: %',r;
    end if;
  end loop;

  replay:=foundation.run_case_audit_layer101_execution_reconciliation_v1(
    '10200000-0000-4000-8000-000000001011'::uuid,now()
  );
  if replay->>'status'<>'existing' then
    raise exception 'Layer 102 semantic replay invalid: %',replay;
  end if;

  select count(*) into l101_after
  from foundation.case_audit_layer97_reconcile_exec_events;
  select count(*) into l97_after
  from foundation.case_audit_layer96_exec_reconciliations;
  select count(*) into l96_after
  from foundation.case_audit_layer92_reconcile_exec_events;

  if l101_after<>l101_before or l97_after<>l97_before or l96_after<>l96_before then
    raise exception 'Layer 102 unexpectedly reran or mutated upstream controls';
  end if;

  s:=foundation.get_case_audit_layer101_execution_reconciliation_summary_v1(
    'production',25
  );

  if s->>'totalCount'<>'5'
     or s->>'reconciledCount'<>'1'
     or s->>'missingLayer97ReceiptCount'<>'1'
     or s->>'invalidLayer97ReceiptCount'<>'1'
     or s->>'executionReceiptMismatchCount'<>'1'
     or s->>'policyDriftCount'<>'1'
     or s->>'incidentDriftCount'<>'0'
     or s->>'coverageDriftCount'<>'0'
     or s->>'problemCount'<>'4' then
    raise exception 'Layer 102 summary invalid: %',s;
  end if;
end;
$l102_reconcile$;

reset role;

do $l102_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_layer101_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_layer101_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_layer101_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_layer101_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role','foundation.case_audit_layer101_exec_reconciliations','INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer101_execution_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer101_execution_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER') then
    raise exception 'Layer 102 privilege boundary invalid';
  end if;
end;
$l102_privileges$;

do $l102_append_only$
declare id uuid;
begin
  select reconciliation_id into id
  from foundation.case_audit_layer101_exec_reconciliations
  limit 1;
  begin
    update foundation.case_audit_layer101_exec_reconciliations
    set reason_code='mutation' where reconciliation_id=id;
    raise exception 'Layer 102 reconciliation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l102_append_only$;

rollback;
