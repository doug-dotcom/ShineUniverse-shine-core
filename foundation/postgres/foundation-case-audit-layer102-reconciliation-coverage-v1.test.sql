begin;

-- Minimal upstream chain needed for six successful Layer-101 source events.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
) values (
  '10300000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer103"}'::jsonb,
  now()-interval '20 minutes','test:layer103:case-audit-incident'
);

do $l103_seed_chain$
declare i integer;
begin
  for i in 1..6 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    ) values(
      ('10300000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','10300000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      lpad(to_hex(i),64,'0'),'executed','test-layer103-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer103','chain',i),
      '{}'::jsonb,now()-interval '30 minutes'
    );

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,verification_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10300000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('10300000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      null,'run-independent-verification','verification-omission',
      lpad(to_hex(i+6),64,'0'),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer103','chain',i),
      '{}'::jsonb,now()-interval '25 minutes'
    );

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10300000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('10300000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,'run-independent-reconciliation','reconciliation-omission',
      lpad(to_hex(i+12),64,'0'),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer103','chain',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );

    insert into foundation.case_audit_reconcile_exec_reconcile_exec_events(
      event_id,environment,target_layer86_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10300000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      'production',
      ('10300000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      null,'run-independent-layer87-reconciliation',
      'layer87-reconciliation-omission',
      lpad(to_hex(i+18),64,'0'),'executed',
      'case-audit-overdue-layer87-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer103','chain',i),
      '{}'::jsonb,now()-interval '15 minutes'
    );

    insert into foundation.case_audit_layer92_reconcile_exec_events(
      event_id,environment,target_layer91_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10300000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      'production',
      ('10300000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      null,'run-independent-layer92-reconciliation',
      'layer92-reconciliation-omission',
      lpad(to_hex(i+24),64,'0'),'executed',
      'case-audit-overdue-layer92-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer103','chain',i),
      '{}'::jsonb,now()-interval '10 minutes'
    );
  end loop;
end;
$l103_seed_chain$;

-- Linked Layer-97 truth for chains 1, 5 and 6. A valid negative Layer-97
-- receipt is sufficient linked truth for Layer-103 structural validation.
do $l103_seed_layer97$
declare
  i integer;
  rid uuid;
  reconciled_at timestamptz;
begin
  foreach i in array array[1,5,6] loop
    rid:=('10300000-0000-4000-8000-'||lpad((970+i)::text,12,'0'))::uuid;
    reconciled_at:=now()-interval '4 minutes';

    insert into foundation.case_audit_layer96_exec_reconciliations(
      reconciliation_id,layer96_event_id,environment,target_layer91_event_id,
      layer92_reconciliation_id,reconciliation_state,reason_code,
      policy_integrity_valid,incident_binding_valid,
      layer92_proof_integrity_valid,execution_receipt_matches,
      before_coverage_valid,after_coverage_valid,layer96_snapshot,
      layer92_snapshot,reconciliation_proof,reconciliation_proof_sha256,
      reconciled_at
    ) values(
      rid,
      ('10300000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      'production',
      ('10300000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      null,'missing-layer92-receipt',
      'case-audit-layer96-layer92-receipt-missing',
      true,true,null,null,true,true,
      jsonb_build_object(
        'layer96EventId',
          ('10300000-0000-4000-8000-'||lpad((960+i)::text,12,'0')),
        'targetLayer91EventId',
          ('10300000-0000-4000-8000-'||lpad((900+i)::text,12,'0')),
        'coverageIncidentEventId',null,
        'actionKey','run-independent-layer92-reconciliation',
        'causeClass','layer92-reconciliation-omission',
        'policyFingerprint',lpad(to_hex(i+24),64,'0'),
        'eventType','executed',
        'reasonCode','case-audit-overdue-layer92-reconciliation-ran',
        'requestedAt',(
          select src.requested_at
          from foundation.case_audit_layer92_reconcile_exec_events src
          where src.event_id=(
            '10300000-0000-4000-8000-'||lpad((960+i)::text,12,'0')
          )::uuid
        )
      ),
      null,
      jsonb_build_object('test','layer103','layer97',i),
      lpad(to_hex(i+30),64,'0'),
      reconciled_at
    );
  end loop;
end;
$l103_seed_layer97$;

-- Six successful Layer-101 executions. Chain 2 is within grace; chain 3 is
-- overdue. The others receive Layer-102 receipts below.
do $l103_seed_layer101$
declare
  i integer;
  requested timestamptz;
begin
  for i in 1..6 loop
    requested:=case when i=2 then now()-interval '1 minute'
                    else now()-interval '10 minutes' end;

    insert into foundation.case_audit_layer97_reconcile_exec_events(
      event_id,environment,target_layer96_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('10300000-0000-4000-8000-'||lpad((1010+i)::text,12,'0'))::uuid,
      'production',
      ('10300000-0000-4000-8000-'||lpad((960+i)::text,12,'0'))::uuid,
      null,'run-independent-layer97-reconciliation',
      'layer97-reconciliation-omission',
      lpad(to_hex(i+36),64,'0'),'executed',
      'case-audit-overdue-layer97-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,
      jsonb_build_object(
        'layer96EventId',
          ('10300000-0000-4000-8000-'||lpad((960+i)::text,12,'0')),
        'targetLayer91EventId',
          ('10300000-0000-4000-8000-'||lpad((900+i)::text,12,'0')),
        'coverageIncidentEventId',null,
        'actionKey','run-independent-layer92-reconciliation',
        'causeClass','layer92-reconciliation-omission',
        'policyFingerprint',lpad(to_hex(i+24),64,'0'),
        'eventType','executed',
        'reasonCode','case-audit-overdue-layer92-reconciliation-ran',
        'requestedAt',(
          select src.requested_at
          from foundation.case_audit_layer92_reconcile_exec_events src
          where src.event_id=(
            '10300000-0000-4000-8000-'||lpad((960+i)::text,12,'0')
          )::uuid
        ),
        'layer97ReconciliationAbsent',true
      ),
      jsonb_build_object(
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
      ),
      jsonb_build_object('status','recorded','test','layer103','chain',i),
      jsonb_build_object(
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
      ),
      requested
    );
  end loop;
end;
$l103_seed_layer101$;

-- Layer-102 receipts:
-- 1 reconciled; 4 valid missing-layer97; 5 valid execution mismatch;
-- 6 structurally invalid; 2 pending/no receipt; 3 overdue/no receipt.
do $l103_seed_layer102$
declare
  i integer;
  e foundation.case_audit_layer97_reconcile_exec_events%rowtype;
  l97 foundation.case_audit_layer96_exec_reconciliations%rowtype;
  rid uuid;
  state text;
  reason text;
  policy_ok boolean;
  incident_ok boolean;
  l97_ok boolean;
  exec_match boolean;
  before_ok boolean;
  after_ok boolean;
  l101_snapshot jsonb;
  l97_snapshot jsonb;
  proof jsonb;
  proof_hash text;
  reconciled_at timestamptz;
begin
  foreach i in array array[1,4,5,6] loop
    select * into e
    from foundation.case_audit_layer97_reconcile_exec_events
    where event_id=(
      '10300000-0000-4000-8000-'||lpad((1010+i)::text,12,'0')
    )::uuid;

    select * into l97
    from foundation.case_audit_layer96_exec_reconciliations
    where layer96_event_id=e.target_layer96_event_id;

    rid:=('10300000-0000-4000-8000-'||lpad((1020+i)::text,12,'0'))::uuid;
    reconciled_at:=now()-interval '30 seconds';

    state:=case
      when i in (1,6) then 'reconciled'
      when i=4 then 'missing-layer97-receipt'
      else 'execution-receipt-mismatch'
    end;

    reason:=case state
      when 'reconciled' then 'case-audit-layer101-complete'
      when 'missing-layer97-receipt' then 'case-audit-layer101-layer97-receipt-missing'
      else 'case-audit-layer101-receipt-mismatch'
    end;

    policy_ok:=true;
    incident_ok:=true;
    l97_ok:=case when i=4 then null else true end;
    exec_match:=case when i=4 then null when i=5 then false else true end;
    before_ok:=true;
    after_ok:=true;

    l101_snapshot:=jsonb_build_object(
      'layer101EventId',e.event_id,
      'targetLayer96EventId',e.target_layer96_event_id,
      'coverageIncidentEventId',e.coverage_incident_event_id,
      'actionKey',e.action_key,
      'causeClass',e.cause_class,
      'policyFingerprint',e.policy_fingerprint,
      'eventType',e.event_type,
      'reasonCode',e.reason_code,
      'requestedAt',e.requested_at
    );

    l97_snapshot:=case when l97.reconciliation_id is null then null else
      jsonb_build_object(
        'reconciliationId',l97.reconciliation_id,
        'layer96EventId',l97.layer96_event_id,
        'targetLayer91EventId',l97.target_layer91_event_id,
        'layer92ReconciliationId',l97.layer92_reconciliation_id,
        'reconciliationState',l97.reconciliation_state,
        'reasonCode',l97.reason_code,
        'policyIntegrityValid',l97.policy_integrity_valid,
        'incidentBindingValid',l97.incident_binding_valid,
        'layer92ProofIntegrityValid',l97.layer92_proof_integrity_valid,
        'executionReceiptMatches',l97.execution_receipt_matches,
        'beforeCoverageValid',l97.before_coverage_valid,
        'afterCoverageValid',l97.after_coverage_valid,
        'reconciliationProofSha256',l97.reconciliation_proof_sha256,
        'reconciledAt',l97.reconciled_at
      ) end;

    proof:=jsonb_build_object(
      'foundationCaseAuditLayer101ExecutionReconciliationProof',
        'shine-foundation/case-audit-layer101-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0',
      'reconciliationId',rid,
      'layer101EventId',e.event_id,
      'environment',e.environment,
      'targetLayer96EventId',e.target_layer96_event_id,
      'layer97ReconciliationId',l97.reconciliation_id,
      'reconciliationState',state,
      'reasonCode',reason,
      'policyIntegrityValid',policy_ok,
      'incidentBindingValid',incident_ok,
      'layer97ProofIntegrityValid',l97_ok,
      'executionReceiptMatches',exec_match,
      'beforeCoverageValid',before_ok,
      'afterCoverageValid',after_ok,
      'layer101ActionResult',e.action_result,
      'layer97Receipt',l97_snapshot,
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
      l97.reconciliation_id,state,reason,policy_ok,incident_ok,l97_ok,
      exec_match,before_ok,after_ok,l101_snapshot,l97_snapshot,proof,
      case when i=6 then repeat('f',64) else proof_hash end,
      reconciled_at
    );
  end loop;
end;
$l103_seed_layer102$;

do $l103_coverage$
declare
  r jsonb;
  l101_before bigint; l101_after bigint;
  l102_before bigint; l102_after bigint;
  l97_before bigint; l97_after bigint;
begin
  select count(*) into l101_before
  from foundation.case_audit_layer97_reconcile_exec_events;
  select count(*) into l102_before
  from foundation.case_audit_layer101_exec_reconciliations;
  select count(*) into l97_before
  from foundation.case_audit_layer96_exec_reconciliations;

  r:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',now(),300,50
  );

  if r->>'state'<>'invalid'
     or r->>'reasonCode'<>'case-audit-layer102-receipt-invalid'
     or r->>'successfulLayer101ExecutionCount'<>'6'
     or r->>'layer102ReconciliationRequiredCount'<>'6'
     or r->>'layer102ReconciliationReceiptCount'<>'4'
     or r->>'reconciledCount'<>'1'
     or r->>'pendingCount'<>'1'
     or r->>'overdueCount'<>'1'
     or r->>'invalidLayer102ReconciliationCount'<>'1'
     or r->>'missingLayer97ReceiptCount'<>'1'
     or r->>'invalidLayer97ReceiptCount'<>'0'
     or r->>'executionReceiptMismatchCount'<>'1'
     or r->>'policyDriftCount'<>'0'
     or r->>'incidentDriftCount'<>'0'
     or r->>'coverageDriftCount'<>'0'
     or r->>'problemCount'<>'4'
     or r->>'layer102ReconciliationCoveragePercent'<>'66.67'
     or r->>'healthyLayer102ReconciliationPercent'<>'16.67'
     or r->>'layer102ProofIntegrityRecomputed'<>'true'
     or r->>'linkedLayer97SnapshotRevalidated'<>'true'
     or r->>'layer102ReconciliationPerformed'<>'false'
     or r->>'layer101RerunPerformed'<>'false'
     or r->>'layer97RerunPerformed'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 103 coverage summary invalid: %',r;
  end if;

  if not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer101EventId'='10300000-0000-4000-8000-000000001012'
      and item->>'coverageState'='pending'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer101EventId'='10300000-0000-4000-8000-000000001013'
      and item->>'coverageState'='overdue'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer101EventId'='10300000-0000-4000-8000-000000001014'
      and item->>'coverageState'='missing-layer97-receipt'
      and item->>'layer102ProofIntegrityValid'='true'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer101EventId'='10300000-0000-4000-8000-000000001016'
      and item->>'coverageState'='invalid-reconciliation'
      and item->>'layer102ProofIntegrityValid'='false'
  ) then
    raise exception 'Layer 103 per-execution classification invalid: %',r;
  end if;

  select count(*) into l101_after
  from foundation.case_audit_layer97_reconcile_exec_events;
  select count(*) into l102_after
  from foundation.case_audit_layer101_exec_reconciliations;
  select count(*) into l97_after
  from foundation.case_audit_layer96_exec_reconciliations;

  if l101_after<>l101_before or l102_after<>l102_before or l97_after<>l97_before then
    raise exception 'Layer 103 coverage reader mutated or reran upstream controls';
  end if;
end;
$l103_coverage$;

do $l103_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer102_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.get_case_audit_layer102_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer102_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
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
         and p.proname='get_case_audit_layer102_reconciliation_coverage_v1'
         and rr.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_layer102_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_layer102_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_layer102_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_layer102_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 103 privilege boundary invalid';
  end if;
end;
$l103_privileges$;

rollback;
