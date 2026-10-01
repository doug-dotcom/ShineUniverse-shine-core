begin;

insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '93000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('1',64),null,
  now()-interval '30 minutes',300,1200,'{"test":"layer93"}'::jsonb,
  now()-interval '20 minutes','test:layer93:case-audit-incident'
);

do $l93_seed_layer76$
declare i integer;
begin
  for i in 1..6 loop
    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    ) values(
      ('93000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      'production','93000000-0000-4000-8000-000000000001'::uuid,
      'record-fresh-promotion-case-audit-observation','observer-freshness',
      lpad(to_hex(i),64,'0'),'executed','test-layer93-layer76',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer93','chain',i),
      '{}'::jsonb,now()-interval '25 minutes'
    );
  end loop;
end;
$l93_seed_layer76$;

do $l93_seed_layer81$
declare i integer;
begin
  for i in 1..6 loop
    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,verification_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('93000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      'production',
      ('93000000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
      null,'run-independent-verification','verification-omission',
      lpad(to_hex(i+6),64,'0'),'executed',
      'case-audit-overdue-verification-layer77-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer93','chain',i),
      '{}'::jsonb,now()-interval '20 minutes'
    );
  end loop;
end;
$l93_seed_layer81$;

do $l93_seed_layer86$
declare i integer;
begin
  for i in 1..6 loop
    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,reconciliation_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('93000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,'run-independent-reconciliation','reconciliation-omission',
      lpad(to_hex(i+12),64,'0'),'executed',
      'case-audit-overdue-reconciliation-layer82-ran',
      '{}'::jsonb,'{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
      jsonb_build_object('status','recorded','test','layer93','chain',i),
      '{}'::jsonb,now()-interval '15 minutes'
    );
  end loop;
end;
$l93_seed_layer86$;

-- Real Layer-87 rows for chains 1, 5 and 6. These are linked truth records for
-- Layer-92 snapshots; Layer 93 does not rerun or reinterpret Layer 87.
do $l93_seed_layer87$
declare
  i integer;
  rid uuid;
begin
  foreach i in array array[1,5,6] loop
    rid:=('93000000-0000-4000-8000-'||lpad((800+i)::text,12,'0'))::uuid;
    insert into foundation.case_audit_verify_reconcile_exec_reconciliations(
      reconciliation_id,layer86_event_id,environment,target_executor_event_id,
      layer82_reconciliation_id,reconciliation_state,reason_code,
      policy_integrity_valid,incident_binding_valid,
      layer82_proof_integrity_valid,execution_receipt_matches,
      before_coverage_valid,after_coverage_valid,layer86_snapshot,
      layer82_snapshot,reconciliation_proof,reconciliation_proof_sha256,
      reconciled_at
    ) values(
      rid,
      ('93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      'production',
      ('93000000-0000-4000-8000-'||lpad((300+i)::text,12,'0'))::uuid,
      null,'missing-layer82-receipt',
      'case-audit-reconcile-exec-layer82-receipt-missing',
      true,true,null,null,true,true,
      jsonb_build_object(
        'layer86EventId',
          ('93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')),
        'targetExecutorEventId',
          ('93000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')),
        'reconciliationIncidentEventId',null,
        'actionKey','run-independent-reconciliation',
        'causeClass','reconciliation-omission',
        'policyFingerprint',lpad(to_hex(i+12),64,'0'),
        'eventType','executed',
        'reasonCode','case-audit-overdue-reconciliation-layer82-ran',
        'requestedAt',(
          select src.requested_at
          from foundation.case_audit_verify_reconcile_exec_events src
          where src.event_id=(
            '93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')
          )::uuid
        )
      ),
      null,
      jsonb_build_object('test','layer93','layer87',i),
      lpad(to_hex(i+20),64,'0'),
      now()-interval '4 minutes'
    );
  end loop;
end;
$l93_seed_layer87$;

do $l93_seed_layer91$
declare i integer; requested_at timestamptz; l87_id uuid;
begin
  for i in 1..6 loop
    requested_at:=case when i=2 then now()-interval '1 minute'
                       else now()-interval '10 minutes' end;
    select reconciliation_id into l87_id
    from foundation.case_audit_verify_reconcile_exec_reconciliations
    where layer86_event_id=(
      '93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')
    )::uuid;

    insert into foundation.case_audit_reconcile_exec_reconcile_exec_events(
      event_id,environment,target_layer86_event_id,coverage_incident_event_id,
      action_key,cause_class,policy_fingerprint,event_type,reason_code,
      decision_snapshot,incident_snapshot,target_snapshot,before_coverage,
      action_result,after_coverage,requested_at
    ) values(
      ('93000000-0000-4000-8000-'||lpad((900+i)::text,12,'0'))::uuid,
      'production',
      ('93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0'))::uuid,
      null,
      'run-independent-layer87-reconciliation','layer87-reconciliation-omission',
      lpad(to_hex(i+26),64,'0'),'executed',
      'case-audit-overdue-layer87-reconciliation-ran',
      '{}'::jsonb,'{}'::jsonb,
      jsonb_build_object(
        'layer86EventId',
          ('93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')),
        'targetExecutorEventId',
          ('93000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')),
        'reconciliationIncidentEventId',null,
        'actionKey','run-independent-reconciliation',
        'causeClass','reconciliation-omission',
        'policyFingerprint',lpad(to_hex(i+12),64,'0'),
        'eventType','executed',
        'reasonCode','case-audit-overdue-reconciliation-layer82-ran',
        'requestedAt',(
          select src.requested_at
          from foundation.case_audit_verify_reconcile_exec_events src
          where src.event_id=(
            '93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')
          )::uuid
        ),
        'ageSeconds',600,
        'reconciliationGraceSeconds',300,
        'layer87ReconciliationId',null,
        'layer87ReconciliationState',null,
        'layer87ReconciliationAbsent',true
      ),
      jsonb_build_object(
        'foundationCaseAuditReconciliationExecutionReconciliationCoverage',
          'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1',
        'schemaVersion','1.0.0','environment','production','state','gap',
        'overdueCount',1,'layer87ReconciliationPerformed',false,
        'layer86RerunPerformed',false,'layer82RerunPerformed',false,
        'layer81RerunPerformed',false,'verificationRerunPerformed',false,
        'mutationPerformed',false
      ),
      case when l87_id is null then
        jsonb_build_object(
          'foundationCaseAuditReconciliationExecutionReconciliation',
            'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
          'schemaVersion','1.0.0','status','recorded',
          'reconciliationId','93000000-0000-4000-8000-000000000899',
          'layer86EventId',
            ('93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')),
          'targetExecutorEventId',
            ('93000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')),
          'layer82ReconciliationId',null,
          'reconciliationState','missing-layer82-receipt',
          'reasonCode','case-audit-reconcile-exec-layer82-receipt-missing',
          'reconciliationProofSha256',repeat('8',64),
          'layer82RerunPerformed',false,'layer81RerunPerformed',false,
          'verificationRerunPerformed',false,'mutationPerformed',false
        )
      else
        jsonb_build_object(
          'foundationCaseAuditReconciliationExecutionReconciliation',
            'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
          'schemaVersion','1.0.0','status','recorded',
          'reconciliationId',l87_id,
          'layer86EventId',
            ('93000000-0000-4000-8000-'||lpad((700+i)::text,12,'0')),
          'targetExecutorEventId',
            ('93000000-0000-4000-8000-'||lpad((300+i)::text,12,'0')),
          'layer82ReconciliationId',null,
          'reconciliationState','missing-layer82-receipt',
          'reasonCode','case-audit-reconcile-exec-layer82-receipt-missing',
          'reconciliationProofSha256',lpad(to_hex(i+20),64,'0'),
          'layer82RerunPerformed',false,'layer81RerunPerformed',false,
          'verificationRerunPerformed',false,'mutationPerformed',false
        )
      end,
      jsonb_build_object(
        'foundationCaseAuditReconciliationExecutionReconciliationCoverage',
          'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1',
        'schemaVersion','1.0.0','environment','production','state','normal',
        'overdueCount',0,'layer87ReconciliationPerformed',false,
        'layer86RerunPerformed',false,'layer82RerunPerformed',false,
        'layer81RerunPerformed',false,'verificationRerunPerformed',false,
        'mutationPerformed',false
      ),
      requested_at
    );
  end loop;
end;
$l93_seed_layer91$;

-- Layer-92 receipts:
-- 1 reconciled; 4 valid missing-layer87 (covered but unhealthy);
-- 5 valid execution-receipt-mismatch (covered but unhealthy);
-- 6 invalid Layer-92 proof; 2 pending/no receipt; 3 overdue/no receipt.
do $l93_seed_layer92$
declare
  i integer;
  e foundation.case_audit_reconcile_exec_reconcile_exec_events%rowtype;
  l87 foundation.case_audit_verify_reconcile_exec_reconciliations%rowtype;
  rid uuid;
  state text;
  reason text;
  policy_ok boolean;
  incident_ok boolean;
  l87_ok boolean;
  exec_match boolean;
  before_ok boolean;
  after_ok boolean;
  l91_snapshot jsonb;
  l87_snapshot jsonb;
  proof jsonb;
  proof_hash text;
  reconciled_at timestamptz;
begin
  foreach i in array array[1,4,5,6] loop
    select * into e
    from foundation.case_audit_reconcile_exec_reconcile_exec_events
    where event_id=(
      '93000000-0000-4000-8000-'||lpad((900+i)::text,12,'0')
    )::uuid;

    select * into l87
    from foundation.case_audit_verify_reconcile_exec_reconciliations
    where layer86_event_id=e.target_layer86_event_id;

    rid:=('93000000-0000-4000-8000-'||lpad((950+i)::text,12,'0'))::uuid;
    reconciled_at:=now()-interval '30 seconds';
    state:=case
      when i in (1,6) then 'reconciled'
      when i=4 then 'missing-layer87-receipt'
      else 'execution-receipt-mismatch'
    end;
    reason:=case state
      when 'reconciled' then 'case-audit-layer91-complete'
      when 'missing-layer87-receipt' then 'case-audit-layer91-layer87-receipt-missing'
      else 'case-audit-layer91-receipt-mismatch'
    end;
    policy_ok:=true;
    incident_ok:=true;
    l87_ok:=case when i=4 then null else true end;
    exec_match:=case when i=4 then null when i=5 then false else true end;
    before_ok:=true;
    after_ok:=true;

    l91_snapshot:=jsonb_build_object(
      'layer91EventId',e.event_id,
      'targetLayer86EventId',e.target_layer86_event_id,
      'coverageIncidentEventId',e.coverage_incident_event_id,
      'actionKey',e.action_key,
      'causeClass',e.cause_class,
      'policyFingerprint',e.policy_fingerprint,
      'eventType',e.event_type,
      'reasonCode',e.reason_code,
      'requestedAt',e.requested_at
    );

    l87_snapshot:=case when l87.reconciliation_id is null then null else
      jsonb_build_object(
        'reconciliationId',l87.reconciliation_id,
        'layer86EventId',l87.layer86_event_id,
        'targetExecutorEventId',l87.target_executor_event_id,
        'layer82ReconciliationId',l87.layer82_reconciliation_id,
        'reconciliationState',l87.reconciliation_state,
        'reasonCode',l87.reason_code,
        'policyIntegrityValid',l87.policy_integrity_valid,
        'incidentBindingValid',l87.incident_binding_valid,
        'layer82ProofIntegrityValid',l87.layer82_proof_integrity_valid,
        'executionReceiptMatches',l87.execution_receipt_matches,
        'beforeCoverageValid',l87.before_coverage_valid,
        'afterCoverageValid',l87.after_coverage_valid,
        'reconciliationProofSha256',l87.reconciliation_proof_sha256,
        'reconciledAt',l87.reconciled_at
      ) end;

    proof:=jsonb_build_object(
      'foundationCaseAuditLayer91ExecutionReconciliationProof',
        'shine-foundation/case-audit-layer91-execution-reconciliation-proof-v1',
      'schemaVersion','1.0.0',
      'reconciliationId',rid,
      'layer91EventId',e.event_id,
      'environment',e.environment,
      'targetLayer86EventId',e.target_layer86_event_id,
      'layer87ReconciliationId',l87.reconciliation_id,
      'reconciliationState',state,
      'reasonCode',reason,
      'policyIntegrityValid',policy_ok,
      'incidentBindingValid',incident_ok,
      'layer87ProofIntegrityValid',l87_ok,
      'executionReceiptMatches',exec_match,
      'beforeCoverageValid',before_ok,
      'afterCoverageValid',after_ok,
      'layer91ActionResult',e.action_result,
      'layer87Receipt',l87_snapshot,
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
    ) values(
      rid,e.event_id,e.environment,e.target_layer86_event_id,
      l87.reconciliation_id,state,reason,policy_ok,incident_ok,l87_ok,
      exec_match,before_ok,after_ok,l91_snapshot,l87_snapshot,proof,
      case when i=6 then repeat('f',64) else proof_hash end,reconciled_at
    );
  end loop;
end;
$l93_seed_layer92$;

do $l93_coverage$
declare
  r jsonb;
  l91_before bigint; l91_after bigint;
  l92_before bigint; l92_after bigint;
  l87_before bigint; l87_after bigint;
begin
  select count(*) into l91_before
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;
  select count(*) into l92_before
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations;
  select count(*) into l87_before
  from foundation.case_audit_verify_reconcile_exec_reconciliations;

  r:=foundation.get_case_audit_layer92_reconciliation_coverage_v1(
    'production',now(),300,50
  );

  if r->>'state'<>'invalid'
     or r->>'reasonCode'<>'case-audit-layer92-receipt-invalid'
     or r->>'successfulLayer91ExecutionCount'<>'6'
     or r->>'layer92ReconciliationRequiredCount'<>'6'
     or r->>'layer92ReconciliationReceiptCount'<>'4'
     or r->>'reconciledCount'<>'1'
     or r->>'pendingCount'<>'1'
     or r->>'overdueCount'<>'1'
     or r->>'invalidLayer92ReconciliationCount'<>'1'
     or r->>'missingLayer87ReceiptCount'<>'1'
     or r->>'invalidLayer87ReceiptCount'<>'0'
     or r->>'executionReceiptMismatchCount'<>'1'
     or r->>'policyDriftCount'<>'0'
     or r->>'incidentDriftCount'<>'0'
     or r->>'coverageDriftCount'<>'0'
     or r->>'problemCount'<>'4'
     or r->>'layer92ReconciliationCoveragePercent'<>'66.67'
     or r->>'healthyLayer92ReconciliationPercent'<>'16.67'
     or r->>'layer92ProofIntegrityRecomputed'<>'true'
     or r->>'linkedLayer87SnapshotRevalidated'<>'true'
     or r->>'layer92ReconciliationPerformed'<>'false'
     or r->>'layer91RerunPerformed'<>'false'
     or r->>'layer87RerunPerformed'<>'false'
     or r->>'layer86RerunPerformed'<>'false'
     or r->>'layer82RerunPerformed'<>'false'
     or r->>'layer81RerunPerformed'<>'false'
     or r->>'verificationRerunPerformed'<>'false'
     or r->>'mutationPerformed'<>'false' then
    raise exception 'Layer 93 coverage summary invalid: %',r;
  end if;

  if not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer91EventId'='93000000-0000-4000-8000-000000000902'
      and item->>'coverageState'='pending'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer91EventId'='93000000-0000-4000-8000-000000000903'
      and item->>'coverageState'='overdue'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer91EventId'='93000000-0000-4000-8000-000000000904'
      and item->>'coverageState'='missing-layer87-receipt'
      and item->>'layer92ProofIntegrityValid'='true'
  )
  or not exists(
    select 1 from jsonb_array_elements(r->'items') item
    where item->>'layer91EventId'='93000000-0000-4000-8000-000000000906'
      and item->>'coverageState'='invalid-reconciliation'
      and item->>'layer92ProofIntegrityValid'='false'
  ) then
    raise exception 'Layer 93 per-execution classification invalid: %',r;
  end if;

  select count(*) into l91_after
  from foundation.case_audit_reconcile_exec_reconcile_exec_events;
  select count(*) into l92_after
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations;
  select count(*) into l87_after
  from foundation.case_audit_verify_reconcile_exec_reconciliations;

  if l91_after<>l91_before or l92_after<>l92_before or l87_after<>l87_before then
    raise exception 'Layer 93 coverage reader mutated or reran upstream controls';
  end if;
end;
$l93_coverage$;

do $l93_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer92_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.get_case_audit_layer92_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer92_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
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
         and p.proname='get_case_audit_layer92_reconciliation_coverage_v1'
         and rr.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_layer92_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_layer92_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_layer92_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_layer92_reconciliation_coverage_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 93 privilege boundary invalid';
  end if;
end;
$l93_privileges$;

rollback;
