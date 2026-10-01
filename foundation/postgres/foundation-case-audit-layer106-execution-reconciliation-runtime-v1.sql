-- Foundation Layer 107: append one immutable reconciliation receipt for one Layer-101 execution.

create or replace function foundation.run_case_audit_layer106_execution_reconciliation_v1(
  p_layer106_event_id uuid,
  p_reconciled_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer107_reconcile$
declare
  v_exec foundation.case_audit_layer102_reconcile_exec_events%rowtype;
  v_existing foundation.case_audit_layer106_exec_reconciliations%rowtype;
  v_eval jsonb;
  v_proof jsonb;
  v_proof_hash text;
  v_reconciliation_id uuid;
  v_layer97_id uuid;
begin
  if p_layer106_event_id is null then
    raise exception 'case-audit-layer106-reconciliation-event-id-required';
  end if;

  if p_reconciled_at is null
     or p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes' then
    raise exception 'case-audit-layer106-reconciliation-time-invalid';
  end if;

  select * into v_exec
  from foundation.case_audit_layer102_reconcile_exec_events
  where event_id=p_layer106_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditLayer106ExecutionReconciliation',
        'shine-foundation/case-audit-layer106-execution-reconciliation-v1',
      'schemaVersion','1.0.0','status','not-applicable',
      'layer106EventId',p_layer106_event_id,
      'reasonCode','case-audit-layer101-event-not-found',
      'layer97RerunPerformed',false,'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditLayer106ExecutionReconciliation',
        'shine-foundation/case-audit-layer106-execution-reconciliation-v1',
      'schemaVersion','1.0.0','status','not-applicable',
      'layer106EventId',v_exec.event_id,
      'sourceEventType',v_exec.event_type,
      'reasonCode','case-audit-layer101-source-not-executed',
      'layer97RerunPerformed',false,'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'mutationPerformed',false
    );
  end if;

  select * into v_existing
  from foundation.case_audit_layer106_exec_reconciliations
  where layer106_event_id=v_exec.event_id;

  if v_existing.reconciliation_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditLayer106ExecutionReconciliation',
        'shine-foundation/case-audit-layer106-execution-reconciliation-v1',
      'schemaVersion','1.0.0','status','existing',
      'reconciliationId',v_existing.reconciliation_id,
      'layer106EventId',v_existing.layer106_event_id,
      'targetLayer101EventId',v_existing.target_layer101_event_id,
      'layer102ReconciliationId',v_existing.layer102_reconciliation_id,
      'reconciliationState',v_existing.reconciliation_state,
      'reasonCode',v_existing.reason_code,
      'reconciliationProofSha256',v_existing.reconciliation_proof_sha256,
      'layer97RerunPerformed',false,'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'mutationPerformed',false
    );
  end if;

  v_eval := foundation.evaluate_case_audit_layer106_execution_outcome_v1(
    v_exec.event_id,p_reconciled_at
  );

  if v_eval->>'status'<>'evaluated'
     or v_eval->>'reconciliationState' not in (
       'reconciled','missing-layer102-receipt','invalid-layer102-receipt',
       'execution-receipt-mismatch','policy-drift','incident-drift','coverage-drift'
     ) then
    raise exception 'case-audit-layer106-reconciliation-evaluation-invalid';
  end if;

  begin
    v_layer97_id := nullif(v_eval->>'layer102ReconciliationId','')::uuid;
  exception when invalid_text_representation then
    v_layer97_id := null;
  end;

  v_reconciliation_id := gen_random_uuid();

  v_proof := jsonb_build_object(
    'foundationCaseAuditLayer106ExecutionReconciliationProof',
      'shine-foundation/case-audit-layer106-execution-reconciliation-proof-v1',
    'schemaVersion','1.0.0',
    'reconciliationId',v_reconciliation_id,
    'layer106EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer101EventId',v_exec.target_layer101_event_id,
    'layer102ReconciliationId',v_layer97_id,
    'reconciliationState',v_eval->>'reconciliationState',
    'reasonCode',v_eval->>'reasonCode',
    'policyIntegrityValid',v_eval->'policyIntegrityValid',
    'incidentBindingValid',v_eval->'incidentBindingValid',
    'layer102ProofIntegrityValid',v_eval->'layer102ProofIntegrityValid',
    'executionReceiptMatches',v_eval->'executionReceiptMatches',
    'beforeCoverageValid',v_eval->'beforeCoverageValid',
    'afterCoverageValid',v_eval->'afterCoverageValid',
    'layer106ActionResult',v_eval->'layer106ActionResult',
    'layer102Receipt',v_eval->'layer102Receipt',
    'layer102RerunPerformed',false,'layer101RerunPerformed',false,
    'layer97RerunPerformed',false,'layer96RerunPerformed',false,
    'layer92RerunPerformed',false,'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
    'layer102ReceiptRewritePerformed',false,'layer96ReceiptRewritePerformed',false,
    'layer92ReceiptRewritePerformed',false,'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'approvalGranted',false,'executionAuthorityGranted',false,
    'mutationPerformed',false,'reconciledAt',p_reconciled_at
  );

  v_proof_hash := encode(
    extensions.digest(convert_to(v_proof::text,'UTF8'),'sha256'),'hex'
  );

  insert into foundation.case_audit_layer106_exec_reconciliations(
    reconciliation_id,layer106_event_id,environment,target_layer101_event_id,
    layer102_reconciliation_id,reconciliation_state,reason_code,
    policy_integrity_valid,incident_binding_valid,
    layer102_proof_integrity_valid,execution_receipt_matches,
    before_coverage_valid,after_coverage_valid,layer106_snapshot,
    layer102_snapshot,reconciliation_proof,reconciliation_proof_sha256,reconciled_at
  )
  values(
    v_reconciliation_id,v_exec.event_id,v_exec.environment,v_exec.target_layer101_event_id,
    v_layer97_id,v_eval->>'reconciliationState',v_eval->>'reasonCode',
    coalesce((v_eval->>'policyIntegrityValid')::boolean,false),
    coalesce((v_eval->>'incidentBindingValid')::boolean,false),
    case when v_eval->'layer102ProofIntegrityValid' is null then null
         else (v_eval->>'layer102ProofIntegrityValid')::boolean end,
    case when v_eval->'executionReceiptMatches' is null then null
         else (v_eval->>'executionReceiptMatches')::boolean end,
    coalesce((v_eval->>'beforeCoverageValid')::boolean,false),
    coalesce((v_eval->>'afterCoverageValid')::boolean,false),
    jsonb_build_object(
      'layer106EventId',v_exec.event_id,
      'targetLayer101EventId',v_exec.target_layer101_event_id,
      'coverageIncidentEventId',v_exec.coverage_incident_event_id,
      'actionKey',v_exec.action_key,
      'causeClass',v_exec.cause_class,
      'policyFingerprint',v_exec.policy_fingerprint,
      'eventType',v_exec.event_type,
      'reasonCode',v_exec.reason_code,
      'requestedAt',v_exec.requested_at
    ),
    nullif(v_eval->'layer102Receipt','null'::jsonb),
    v_proof,v_proof_hash,p_reconciled_at
  );

  return jsonb_build_object(
    'foundationCaseAuditLayer106ExecutionReconciliation',
      'shine-foundation/case-audit-layer106-execution-reconciliation-v1',
    'schemaVersion','1.0.0','status','recorded',
    'reconciliationId',v_reconciliation_id,
    'layer106EventId',v_exec.event_id,
    'targetLayer101EventId',v_exec.target_layer101_event_id,
    'layer102ReconciliationId',v_layer97_id,
    'reconciliationState',v_eval->>'reconciliationState',
    'reasonCode',v_eval->>'reasonCode',
    'reconciliationProofSha256',v_proof_hash,
    'layer102RerunPerformed',false,'layer101RerunPerformed',false,
    'layer97RerunPerformed',false,'layer96RerunPerformed',false,
    'layer92RerunPerformed',false,'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'mutationPerformed',false
  );
end;
$layer107_reconcile$;

revoke all on function foundation.run_case_audit_layer106_execution_reconciliation_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_case_audit_layer106_execution_reconciliation_v1(
  uuid,timestamptz
) to service_role;

create or replace function foundation.get_case_audit_layer106_execution_reconciliation_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer107_summary$
declare
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_reconciled integer := 0;
  v_missing integer := 0;
  v_invalid integer := 0;
  v_mismatch integer := 0;
  v_policy integer := 0;
  v_incident integer := 0;
  v_coverage integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'case-audit-layer106-reconciliation-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter(where reconciliation_state='reconciled'),
    count(*) filter(where reconciliation_state='missing-layer102-receipt'),
    count(*) filter(where reconciliation_state='invalid-layer102-receipt'),
    count(*) filter(where reconciliation_state='execution-receipt-mismatch'),
    count(*) filter(where reconciliation_state='policy-drift'),
    count(*) filter(where reconciliation_state='incident-drift'),
    count(*) filter(where reconciliation_state='coverage-drift')
  into v_total,v_reconciled,v_missing,v_invalid,v_mismatch,v_policy,v_incident,v_coverage
  from foundation.case_audit_layer106_exec_reconciliations
  where environment=p_environment;

  select coalesce(jsonb_agg(jsonb_build_object(
    'reconciliationId',x.reconciliation_id,
    'layer106EventId',x.layer106_event_id,
    'targetLayer101EventId',x.target_layer101_event_id,
    'layer102ReconciliationId',x.layer102_reconciliation_id,
    'reconciliationState',x.reconciliation_state,
    'reasonCode',x.reason_code,
    'policyIntegrityValid',x.policy_integrity_valid,
    'incidentBindingValid',x.incident_binding_valid,
    'layer102ProofIntegrityValid',x.layer102_proof_integrity_valid,
    'executionReceiptMatches',x.execution_receipt_matches,
    'beforeCoverageValid',x.before_coverage_valid,
    'afterCoverageValid',x.after_coverage_valid,
    'reconciliationProofSha256',x.reconciliation_proof_sha256,
    'reconciledAt',x.reconciled_at
  ) order by x.reconciliation_sequence desc),'[]'::jsonb)
  into v_items
  from (
    select * from foundation.case_audit_layer106_exec_reconciliations
    where environment=p_environment
    order by reconciliation_sequence desc limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditLayer106ExecutionReconciliationSummary',
      'shine-foundation/case-audit-layer106-execution-reconciliation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,
    'totalCount',v_total,'reconciledCount',v_reconciled,
    'missingLayer102ReceiptCount',v_missing,'invalidLayer102ReceiptCount',v_invalid,
    'executionReceiptMismatchCount',v_mismatch,'policyDriftCount',v_policy,
    'incidentDriftCount',v_incident,'coverageDriftCount',v_coverage,
    'problemCount',v_missing+v_invalid+v_mismatch+v_policy+v_incident+v_coverage,
    'visibleCount',jsonb_array_length(v_items),'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'layer102RerunPerformed',false,'layer101RerunPerformed',false,
    'layer97RerunPerformed',false,'layer96RerunPerformed',false,
    'layer92RerunPerformed',false,'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
    'layer102ReceiptRewritePerformed',false,'layer96ReceiptRewritePerformed',false,
    'layer92ReceiptRewritePerformed',false,'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,'mutationPerformed',false
  );
end;
$layer107_summary$;

revoke all on function foundation.get_case_audit_layer106_execution_reconciliation_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer106_execution_reconciliation_summary_v1(
  text,integer
) to foundation_runtime,service_role;
