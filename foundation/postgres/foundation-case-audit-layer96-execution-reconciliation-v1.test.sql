begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '97000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer97"}'::jsonb,
  now()-interval '20 minutes','test:layer97:case-audit-incident'
);

do $l97_seed_layer76$
declare i integer;
begin
  for i in 1..5 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      ('97000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','97000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      lpad(to_hex(i),64,'0'),'executed','test-layer97-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer97','chain',i),
      '{}'::jsonb,now()-interval '25 minutes'
    );
  end loop;
end;
$l97_seed_layer76$;

do $l97_seed_layer81$
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
      ('97000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('97000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      null,'run-independent-verification','verification-omission',
      lpad(to_hex(i+5),64,'0'),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer97','chain',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );
  end loop;
end;
$l97_seed_layer81$;

do $l97_seed_layer86$
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
      ('97000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('97000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,'run-independent-reconciliation','reconciliation-omission',
      lpad(to_hex(i+10),64,'0'),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer97','chain',i),
      '{}'::jsonb,now()-interval '15 minutes'
    );
  end loop;
end;
$l97_seed_layer86$;

do $l97_seed_layer91$
declare i integer;
begin
  for i in 1..5 loop
    insert into foundation.case_audit_reconcile_exec_reconcile_exec_events(
      event_id,environment,target_layer86_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    )
    values(
      ('97000000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      'production',
      ('97000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      null,'run-independent-layer87-reconciliation',
      'layer87-reconciliation-omission',
      lpad(to_hex(i+15),64,'0'),'executed',
      'case-audit-overdue-layer87-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,
      jsonb_build_object(
        'layer86EventId',
          ('97000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')),
        'targetExecutorEventId',
          ('97000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')),
        'reconciliationIncidentEventId',null,
        'actionKey','run-independent-reconciliation',
        'causeClass','reconciliation-omission',
        'policyFingerprint',lpad(to_hex(i+10),64,'0'),
        'eventType','executed',
        'reasonCode','case-audit-overdue-reconciliation-layer82-ran',
        'requestedAt',(
          select src.requested_at
          from foundation.case_audit_verify_reconcile_exec_events src
          where src.event_id=(
            '97000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')
          )::uuid
        ),
        'layer87ReconciliationAbsent',true
      ),
      '{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer97','chain',i),
      '{}'::jsonb,now()-interval '10 minutes'
    );
  end loop;
end;
$l97_seed_layer91$;

-- Valid Layer-92 receipts for chains 1,3,5; chain 4 has a deliberately bad
-- proof hash; chain 2 intentionally has no Layer-92 receipt.
do $l97_seed_layer92$
declare
  i integer;
  e foundation.case_audit_reconcile_exec_reconcile_exec_events%rowtype;
  rid uuid;
  proof jsonb;
  proof_hash text;
  reconciled_at timestamptz;
begin
  foreach i in array array[1,3,4,5] loop
    select * into e
    from foundation.case_audit_reconcile_exec_reconcile_exec_events
    where event_id=(
      '97000000-0000-4000-8000-'||lpad((900+i)::text,12,'0')
    )::uuid;

    rid:=('97000000-0000-4000-8000-'||lpad((800+i)::text,12,'0'))::uuid;
    reconciled_at:=now()-interval '4 minutes';

    proof:=jsonb_build_object(
      'foundationCaseAuditLayer91ExecutionReconciliationProof',
        'shine-foundation/case-audit-layer91-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0',
      'reconciliationId',rid,
      'layer91EventId',e.event_id,
      'environment',e.environment,
      'targetLayer86EventId',e.target_layer86_event_id,
      'layer87ReconciliationId',null,
      'reconciliationState','missing-layer87-receipt',
      'reasonCode','case-audit-layer91-layer87-receipt-missing',
      'policyIntegrityValid',true,
      'incidentBindingValid',true,
      'layer87ProofIntegrityValid',null,
      'executionReceiptMatches',null,
      'beforeCoverageValid',true,
      'afterCoverageValid',true,
      'layer91ActionResult',e.action_result,
      'layer87Receipt',null,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'layer87ReceiptRewritePerformed',false,
      'layer86ReceiptRewritePerformed',false,
      'layer82ReceiptRewritePerformed',false,
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

    insert into foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations(
      reconciliation_id,layer91_event_id,environment,target_layer86_event_id,
      layer87_reconciliation_id,reconciliation_state,reason_code,
      policy_integrity_valid,incident_binding_valid,
      layer87_proof_integrity_valid,execution_receipt_matches,
      before_coverage_valid,after_coverage_valid,layer91_snapshot,
      layer87_snapshot,reconciliation_proof,reconciliation_proof_sha256,
      reconciled_at
    )
    values(
      rid,e.event_id,e.environment,e.target_layer86_event_id,
      null,'missing-layer87-receipt',
      'case-audit-layer91-layer87-receipt-missing',
      true,true,null,null,true,true,
      jsonb_build_object(
        'layer91EventId',e.event_id,
        'targetLayer86EventId',e.target_layer86_event_id,
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
$l97_seed_layer92$;

insert into foundation.case_audit_layer92_coverage_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,detection_started_at,
  persistence_threshold_seconds,persistence_seconds,snapshot,occurred_at,evidence_ref
)
values(
  '97000000-0000-4000-8000-000000000951'::uuid,
  'production:case_audit_layer92_reconciliation_coverage',
  'production','case_audit_layer92_reconciliation_coverage',
  'opened','gap','critical','case-audit-layer92-overdue',repeat('9',64),
  now()-interval '10 minutes',300,600,'{"test":"layer97"}'::jsonb,
  now()-interval '1 minute','test:layer97:coverage-incident'
);

do $l97_seed_layer96$
declare
  i integer;
  target foundation.case_audit_reconcile_exec_reconcile_exec_events%rowtype;
  l92 foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations%rowtype;
  decision jsonb;
  incident_snapshot jsonb;
  target_snapshot jsonb;
  before_coverage jsonb;
  after_coverage jsonb;
  action_result jsonb;
  fp text;
begin
  decision:=jsonb_build_object(
    'foundationCaseAuditLayer92CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'incidentState','critical',
    'causeClass','layer92-reconciliation-omission',
    'actionKey','run-independent-layer92-reconciliation',
    'actionClass','evidence',
    'decision','admit',
    'requiredControl','layer-92-bounded-reconciler',
    'reasonCode','case-audit-layer92-response-run-bounded-reconciliation',
    'authorityExpansion',false,
    'automaticLayer92ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'layer91ReceiptRewriteAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'mutatesLayer92Receipt',false,
    'mutatesLayer91Receipt',false,
    'mutatesLayer87Receipt',false,
    'rerunsLayer91',false,
    'rerunsLayer87',false,
    'rerunsLayer86',false,
    'rerunsLayer82',false,
    'rerunsLayer81',false,
    'rerunsVerification',false,
    'executesAction',false
  );

  incident_snapshot:=jsonb_build_object(
    'state','critical',
    'currentEvent',jsonb_build_object(
      'eventId','97000000-0000-4000-8000-000000000951',
      'eventType','opened',
      'sourceState','gap',
      'evidenceFingerprint',repeat('9',64)
    )
  );

  before_coverage:=jsonb_build_object(
    'foundationCaseAuditLayer92ReconciliationCoverage',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production',
    'state','gap','reasonCode','case-audit-layer92-overdue',
    'overdueCount',1,
    'layer92ReconciliationPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  after_coverage:=jsonb_build_object(
    'foundationCaseAuditLayer92ReconciliationCoverage',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-v1',
    'schemaVersion','1.0.0','environment','production',
    'state','normal','reasonCode','case-audit-layer92-covered',
    'overdueCount',0,
    'layer92ReconciliationPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'mutationPerformed',false
  );

  for i in 1..5 loop
    select * into target
    from foundation.case_audit_reconcile_exec_reconcile_exec_events
    where event_id=(
      '97000000-0000-4000-8000-'||lpad((900+i)::text,12,'0')
    )::uuid;

    select * into l92
    from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations
    where layer91_event_id=target.event_id;

    target_snapshot:=jsonb_build_object(
      'layer91EventId',target.event_id,
      'targetLayer86EventId',target.target_layer86_event_id,
      'coverageIncidentEventId',target.coverage_incident_event_id,
      'actionKey',target.action_key,
      'causeClass',target.cause_class,
      'policyFingerprint',target.policy_fingerprint,
      'eventType',target.event_type,
      'reasonCode',target.reason_code,
      'requestedAt',target.requested_at,
      'ageSeconds',600,
      'reconciliationGraceSeconds',300,
      'layer92ReconciliationId',null,
      'layer92ReconciliationState',null,
      'layer92ReconciliationAbsent',true
    );

    if l92.reconciliation_id is null then
      action_result:=jsonb_build_object(
        'foundationCaseAuditLayer91ExecutionReconciliation',
          'shine-foundation/case-audit-layer91-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId','97000000-0000-4000-8000-000000000899',
        'layer91EventId',target.event_id,
        'targetLayer86EventId',target.target_layer86_event_id,
        'layer87ReconciliationId',null,
        'reconciliationState','missing-layer87-receipt',
        'reasonCode','case-audit-layer91-layer87-receipt-missing',
        'reconciliationProofSha256',repeat('8',64),
        'layer87RerunPerformed',false,
        'layer86RerunPerformed',false,
        'layer82RerunPerformed',false,
        'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,
        'mutationPerformed',false
      );
    else
      action_result:=jsonb_build_object(
        'foundationCaseAuditLayer91ExecutionReconciliation',
          'shine-foundation/case-audit-layer91-execution-reconciliation-v1',
        'schemaVersion','1.0.0','status','recorded',
        'reconciliationId',l92.reconciliation_id,
        'layer91EventId',l92.layer91_event_id,
        'targetLayer86EventId',l92.target_layer86_event_id,
        'layer87ReconciliationId',l92.layer87_reconciliation_id,
        'reconciliationState',l92.reconciliation_state,
        'reasonCode',l92.reason_code,
        'reconciliationProofSha256',
          case when i=3 then repeat('0',64)
               else l92.reconciliation_proof_sha256 end,
        'layer87RerunPerformed',false,
        'layer86RerunPerformed',false,
        'layer82RerunPerformed',false,
        'layer81RerunPerformed',false,
        'verificationRerunPerformed',false,
        'mutationPerformed',false
      );
    end if;

    fp:=foundation.case_audit_layer92_reconcile_exec_policy_fp_v1(
      decision,incident_snapshot,target_snapshot
    );

    insert into foundation.case_audit_layer92_reconcile_exec_events(
      event_id,environment,target_layer91_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    )
    values(
      ('97000000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      'production',target.event_id,
      '97000000-0000-4000-8000-000000000951'::uuid,
      'run-independent-layer92-reconciliation',
      'layer92-reconciliation-omission',
      case when i=5 then repeat('a',64) else fp end,
      'executed','case-audit-overdue-layer92-reconciliation-ran',
      decision,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,now()-interval '30 seconds'
    );
  end loop;
end;
$l97_seed_layer96$;


do $l97_evaluate$
declare r jsonb;
begin
  r:=foundation.evaluate_case_audit_layer96_execution_outcome_v1(
    '97000000-0000-4000-8000-000000000961'::uuid,now()
  );
  if r->>'reconciliationState'<>'reconciled'
     or r->>'policyIntegrityValid'<>'true'
     or r->>'incidentBindingValid'<>'true'
     or r->>'layer92ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'true'
     or r->>'beforeCoverageValid'<>'true'
     or r->>'afterCoverageValid'<>'true' then
    raise exception 'Layer 97 truthful Layer-96 reconciliation invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer96_execution_outcome_v1(
    '97000000-0000-4000-8000-000000000962'::uuid,now()
  );
  if r->>'reconciliationState'<>'missing-layer92-receipt' then
    raise exception 'Layer 97 missing Layer-92 truth invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer96_execution_outcome_v1(
    '97000000-0000-4000-8000-000000000963'::uuid,now()
  );
  if r->>'reconciliationState'<>'execution-receipt-mismatch'
     or r->>'layer92ProofIntegrityValid'<>'true'
     or r->>'executionReceiptMatches'<>'false' then
    raise exception 'Layer 97 execution mismatch invalid: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer96_execution_outcome_v1(
    '97000000-0000-4000-8000-000000000964'::uuid,now()
  );
  if r->>'reconciliationState'<>'invalid-layer92-receipt'
     or r->>'layer92ProofIntegrityValid'<>'false' then
    raise exception 'Layer 97 invalid Layer-92 integrity precedence failed: %',r;
  end if;

  r:=foundation.evaluate_case_audit_layer96_execution_outcome_v1(
    '97000000-0000-4000-8000-000000000965'::uuid,now()
  );
  if r->>'reconciliationState'<>'policy-drift'
     or r->>'layer92ProofIntegrityValid'<>'true'
     or r->>'policyIntegrityValid'<>'false' then
    raise exception 'Layer 97 policy drift invalid: %',r;
  end if;
end;
$l97_evaluate$;


set local role service_role;

do $l97_reconcile$
declare
  i integer;
  r jsonb;
  replay jsonb;
  summary jsonb;
  l96_before bigint; l96_after bigint;
  l92_before bigint; l92_after bigint;
  l91_before bigint; l91_after bigint;
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 97 service-role reconciler unavailable';
  end if;

  if has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer91_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 97 found Layer-96 direct Layer-92 bypass reopened';
  end if;

  select count(*) into l96_before
  from foundation.case_audit_layer92_reconcile_exec_events;
  select count(*) into l92_before
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations;
  select count(*) into l91_before
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;

  for i in 1..5 loop
    r:=foundation.run_case_audit_layer96_execution_reconciliation_v1(
      ('97000000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      now()
    );
    if r->>'status'<>'recorded'
       or r->>'layer92RerunPerformed'<>'false'
       or r->>'layer91RerunPerformed'<>'false'
       or r->>'layer87RerunPerformed'<>'false'
       or r->>'mutationPerformed'<>'false' then
      raise exception 'Layer 97 receipt invalid: %',r;
    end if;
  end loop;

  replay:=foundation.run_case_audit_layer96_execution_reconciliation_v1(
    '97000000-0000-4000-8000-000000000961'::uuid,now()
  );
  if replay->>'status'<>'existing' then
    raise exception 'Layer 97 semantic replay invalid: %',replay;
  end if;

  select count(*) into l96_after
  from foundation.case_audit_layer92_reconcile_exec_events;
  select count(*) into l92_after
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations;
  select count(*) into l91_after
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;

  if l96_after<>l96_before or l92_after<>l92_before or l91_after<>l91_before then
    raise exception 'Layer 97 unexpectedly reran or mutated upstream controls';
  end if;

  summary:=foundation.get_case_audit_layer96_execution_reconciliation_summary_v1(
    'production',25
  );

  if summary->>'totalCount'<>'5'
     or summary->>'reconciledCount'<>'1'
     or summary->>'missingLayer92ReceiptCount'<>'1'
     or summary->>'invalidLayer92ReceiptCount'<>'1'
     or summary->>'executionReceiptMismatchCount'<>'1'
     or summary->>'policyDriftCount'<>'1'
     or summary->>'incidentDriftCount'<>'0'
     or summary->>'coverageDriftCount'<>'0'
     or summary->>'problemCount'<>'4'
     or summary->>'layer92RerunPerformed'<>'false'
     or summary->>'layer91RerunPerformed'<>'false'
     or summary->>'mutationPerformed'<>'false' then
    raise exception 'Layer 97 summary invalid: %',summary;
  end if;
end;
$l97_reconcile$;

reset role;


do $l97_privileges$
begin
  if has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.run_case_audit_layer96_execution_reconciliation_v1(uuid,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_layer96_exec_reconciliations',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer96_execution_reconciliation_summary_v1(text,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer96_execution_reconciliation_summary_v1(text,integer)',
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
         and p.proname='get_case_audit_layer96_execution_reconciliation_summary_v1'
         and rr.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     ) then
    raise exception 'Layer 97 privilege boundary invalid';
  end if;
end;
$l97_privileges$;


do $l97_append_only$
declare id uuid;
begin
  select reconciliation_id into id
  from foundation.case_audit_layer96_exec_reconciliations
  limit 1;

  begin
    update foundation.case_audit_layer96_exec_reconciliations
    set reason_code='mutation'
    where reconciliation_id=id;
    raise exception 'Layer 97 reconciliation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l97_append_only$;

rollback;
