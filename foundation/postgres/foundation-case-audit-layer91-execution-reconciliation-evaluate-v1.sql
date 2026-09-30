-- Foundation Layer 92: independently evaluate one Layer-91 execution against durable Layer-87 truth.

create or replace function foundation.evaluate_case_audit_layer91_execution_outcome_v1(
  p_layer91_event_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer92_evaluate$
declare
  v_exec foundation.case_audit_reconcile_exec_reconcile_exec_events%rowtype;
  v_target foundation.case_audit_verify_reconcile_exec_events%rowtype;
  v_layer87 foundation.case_audit_verify_reconcile_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_reconcile_exec_coverage_incident_events%rowtype;
  v_policy_integrity boolean := false;
  v_incident_binding boolean := false;
  v_layer87_integrity boolean;
  v_execution_match boolean;
  v_before_valid boolean := false;
  v_after_valid boolean := false;
  v_recomputed_layer87_hash text;
  v_state text;
  v_reason text;
  v_layer87_snapshot jsonb;
begin
  if p_layer91_event_id is null then
    raise exception 'case-audit-layer91-outcome-event-id-required';
  end if;

  if p_as_of is null then
    raise exception 'case-audit-layer91-outcome-time-required';
  end if;

  select * into v_exec
  from foundation.case_audit_reconcile_exec_reconcile_exec_events
  where event_id=p_layer91_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditLayer91ExecutionOutcome',
        'shine-foundation/case-audit-layer91-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-found',
      'layer91EventId',p_layer91_event_id,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-layer91-event-not-found',
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditLayer91ExecutionOutcome',
        'shine-foundation/case-audit-layer91-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'layer91EventId',v_exec.event_id,
      'targetLayer86EventId',v_exec.target_layer86_event_id,
      'environment',v_exec.environment,
      'sourceEventType',v_exec.event_type,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-layer91-source-not-executed',
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  select * into v_target
  from foundation.case_audit_verify_reconcile_exec_events
  where event_id=v_exec.target_layer86_event_id
    and environment=v_exec.environment;

  select * into v_layer87
  from foundation.case_audit_verify_reconcile_exec_reconciliations
  where layer86_event_id=v_exec.target_layer86_event_id;

  select * into v_incident
  from foundation.case_audit_reconcile_exec_coverage_incident_events
  where event_id=v_exec.coverage_incident_event_id
    and environment=v_exec.environment;

  v_policy_integrity :=
    v_target.event_id is not null
    and foundation.case_audit_reconcile_exec_reconcile_exec_policy_fp_v1(
          v_exec.decision_snapshot,
          v_exec.incident_snapshot,
          v_exec.target_snapshot
        ) is not distinct from v_exec.policy_fingerprint
    and v_exec.action_key='run-independent-layer87-reconciliation'
    and v_exec.cause_class='layer87-reconciliation-omission'
    and v_exec.reason_code='case-audit-overdue-layer87-reconciliation-ran'
    and v_exec.decision_snapshot->>
          'foundationCaseAuditReconciliationExecutionCoverageIncidentResponseDecision'
        is not distinct from
          'shine-foundation/case-audit-reconciliation-execution-coverage-incident-response-decision-v1'
    and v_exec.decision_snapshot->>'schemaVersion'
        is not distinct from '1.0.0'
    and v_exec.decision_snapshot->>'decision'='admit'
    and v_exec.decision_snapshot->>'requiredControl'='layer-87-bounded-reconciler'
    and v_exec.decision_snapshot->>'causeClass'='layer87-reconciliation-omission'
    and v_exec.decision_snapshot->>'actionKey'='run-independent-layer87-reconciliation'
    and v_exec.decision_snapshot->'authorityExpansion'='false'::jsonb
    and v_exec.decision_snapshot->'automaticLayer87ReconciliationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticReconciliationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticRepairAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer87ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer86ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer82ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'historyRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer86RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer82RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer81RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'verificationRerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'executesAction'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer87Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer86Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer82Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer86'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer82'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer81'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsVerification'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesAuthoritativeTruth'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesIncidentHistory'='false'::jsonb
    and v_exec.target_snapshot->>'layer86EventId'
        is not distinct from v_target.event_id::text
    and v_exec.target_snapshot->>'targetExecutorEventId'
        is not distinct from v_target.target_executor_event_id::text
    and v_exec.target_snapshot->>'reconciliationIncidentEventId'
        is not distinct from v_target.reconciliation_incident_event_id::text
    and v_exec.target_snapshot->>'actionKey'
        is not distinct from v_target.action_key
    and v_exec.target_snapshot->>'causeClass'
        is not distinct from v_target.cause_class
    and v_exec.target_snapshot->>'policyFingerprint'
        is not distinct from v_target.policy_fingerprint
    and v_exec.target_snapshot->>'eventType'
        is not distinct from v_target.event_type
    and v_exec.target_snapshot->>'reasonCode'
        is not distinct from v_target.reason_code
    and v_exec.target_snapshot->'requestedAt'
        is not distinct from to_jsonb(v_target.requested_at)
    and v_exec.target_snapshot->'layer87ReconciliationAbsent'='true'::jsonb
    and nullif(v_exec.target_snapshot->>'layer87ReconciliationId','') is null;

  v_incident_binding :=
    v_incident.event_id is not null
    and v_incident.event_type in ('detected','opened','changed')
    and v_incident.source_state in ('gap','invalid')
    and v_exec.incident_snapshot#>>'{currentEvent,eventId}'
        is not distinct from v_incident.event_id::text
    and v_exec.incident_snapshot#>>'{currentEvent,eventType}'
        is not distinct from v_incident.event_type
    and v_exec.incident_snapshot#>>'{currentEvent,sourceState}'
        is not distinct from v_incident.source_state
    and v_exec.incident_snapshot#>>'{currentEvent,evidenceFingerprint}'
        is not distinct from v_incident.evidence_fingerprint
    and (
      (v_incident.event_type='detected' and v_exec.incident_snapshot->>'state'='watching')
      or
      (v_incident.event_type in ('opened','changed')
       and v_exec.incident_snapshot->>'state'='critical')
    );

  v_before_valid :=
    v_exec.before_coverage->>
          'foundationCaseAuditReconciliationExecutionReconciliationCoverage'
      is not distinct from
          'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1'
    and v_exec.before_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.before_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.before_coverage->>'state'='gap'
    and coalesce((v_exec.before_coverage->>'overdueCount')::integer,0)>0
    and v_exec.before_coverage->'layer87ReconciliationPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer86RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer82RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'mutationPerformed'='false'::jsonb;

  v_after_valid :=
    v_exec.after_coverage is not null
    and v_exec.after_coverage->>
          'foundationCaseAuditReconciliationExecutionReconciliationCoverage'
      is not distinct from
          'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1'
    and v_exec.after_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.after_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.after_coverage->'layer87ReconciliationPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer86RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer82RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'mutationPerformed'='false'::jsonb;

  if v_layer87.reconciliation_id is not null then
    v_recomputed_layer87_hash := encode(
      extensions.digest(
        convert_to(v_layer87.reconciliation_proof::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    v_layer87_integrity :=
      v_recomputed_layer87_hash
        is not distinct from v_layer87.reconciliation_proof_sha256
      and v_layer87.reconciliation_proof->>
            'foundationCaseAuditReconciliationExecutionReconciliationProof'
          is not distinct from
            'shine-foundation/case-audit-reconciliation-execution-reconciliation-proof-v1'
      and v_layer87.reconciliation_proof->>'schemaVersion'
          is not distinct from '1.0.0'
      and v_layer87.reconciliation_proof->>'reconciliationId'
          is not distinct from v_layer87.reconciliation_id::text
      and v_layer87.reconciliation_proof->>'layer86EventId'
          is not distinct from v_layer87.layer86_event_id::text
      and v_layer87.reconciliation_proof->>'environment'
          is not distinct from v_layer87.environment
      and v_layer87.reconciliation_proof->>'targetExecutorEventId'
          is not distinct from v_layer87.target_executor_event_id::text
      and v_layer87.reconciliation_proof->>'layer82ReconciliationId'
          is not distinct from v_layer87.layer82_reconciliation_id::text
      and v_layer87.reconciliation_proof->>'reconciliationState'
          is not distinct from v_layer87.reconciliation_state
      and v_layer87.reconciliation_proof->>'reasonCode'
          is not distinct from v_layer87.reason_code
      and v_layer87.reconciliation_proof->'policyIntegrityValid'
          is not distinct from to_jsonb(v_layer87.policy_integrity_valid)
      and v_layer87.reconciliation_proof->'incidentBindingValid'
          is not distinct from to_jsonb(v_layer87.incident_binding_valid)
      and nullif(
            v_layer87.reconciliation_proof->'layer82ProofIntegrityValid',
            'null'::jsonb
          ) is not distinct from to_jsonb(v_layer87.layer82_proof_integrity_valid)
      and nullif(
            v_layer87.reconciliation_proof->'executionReceiptMatches',
            'null'::jsonb
          ) is not distinct from to_jsonb(v_layer87.execution_receipt_matches)
      and v_layer87.reconciliation_proof->'beforeCoverageValid'
          is not distinct from to_jsonb(v_layer87.before_coverage_valid)
      and v_layer87.reconciliation_proof->'afterCoverageValid'
          is not distinct from to_jsonb(v_layer87.after_coverage_valid)
      and v_layer87.reconciliation_proof->'layer86ActionResult'
          is not distinct from v_target.action_result
      and nullif(v_layer87.reconciliation_proof->'layer82Receipt','null'::jsonb)
          is not distinct from v_layer87.layer82_snapshot
      and v_layer87.reconciliation_proof->'reconciledAt'
          is not distinct from to_jsonb(v_layer87.reconciled_at)
      and v_layer87.reconciliation_proof->'layer82RerunPerformed'='false'::jsonb
      and v_layer87.reconciliation_proof->'layer81RerunPerformed'='false'::jsonb
      and v_layer87.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
      and v_layer87.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
      and v_layer87.reconciliation_proof->'reconciliationReceiptRewritePerformed'
          ='false'::jsonb
      and v_layer87.reconciliation_proof->'verificationProofRewritePerformed'
          ='false'::jsonb
      and v_layer87.reconciliation_proof->'releaseTruthMutationPerformed'
          ='false'::jsonb
      and v_layer87.reconciliation_proof->'incidentHistoryMutationPerformed'
          ='false'::jsonb
      and v_layer87.reconciliation_proof->'approvalGranted'='false'::jsonb
      and v_layer87.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
      and v_layer87.reconciliation_proof->'mutationPerformed'='false'::jsonb
      and v_layer87.layer86_snapshot->>'layer86EventId'
          is not distinct from v_target.event_id::text
      and v_layer87.layer86_snapshot->>'targetExecutorEventId'
          is not distinct from v_target.target_executor_event_id::text
      and v_layer87.layer86_snapshot->>'reconciliationIncidentEventId'
          is not distinct from v_target.reconciliation_incident_event_id::text
      and v_layer87.layer86_snapshot->>'actionKey'
          is not distinct from v_target.action_key
      and v_layer87.layer86_snapshot->>'causeClass'
          is not distinct from v_target.cause_class
      and v_layer87.layer86_snapshot->>'policyFingerprint'
          is not distinct from v_target.policy_fingerprint
      and v_layer87.layer86_snapshot->>'eventType'
          is not distinct from v_target.event_type
      and v_layer87.layer86_snapshot->>'reasonCode'
          is not distinct from v_target.reason_code
      and v_layer87.layer86_snapshot->'requestedAt'
          is not distinct from to_jsonb(v_target.requested_at);

    v_execution_match :=
      v_exec.action_result->>
          'foundationCaseAuditReconciliationExecutionReconciliation'
        is not distinct from
          'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1'
      and v_exec.action_result->>'schemaVersion' is not distinct from '1.0.0'
      and v_exec.action_result->>'status' in ('recorded','existing')
      and v_exec.action_result->>'reconciliationId'
          is not distinct from v_layer87.reconciliation_id::text
      and v_exec.action_result->>'layer86EventId'
          is not distinct from v_layer87.layer86_event_id::text
      and v_exec.action_result->>'targetExecutorEventId'
          is not distinct from v_layer87.target_executor_event_id::text
      and v_exec.action_result->>'layer82ReconciliationId'
          is not distinct from v_layer87.layer82_reconciliation_id::text
      and v_exec.action_result->>'reconciliationState'
          is not distinct from v_layer87.reconciliation_state
      and v_exec.action_result->>'reasonCode'
          is not distinct from v_layer87.reason_code
      and v_exec.action_result->>'reconciliationProofSha256'
          is not distinct from v_layer87.reconciliation_proof_sha256
      and v_exec.action_result->'layer82RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer81RerunPerformed'='false'::jsonb
      and v_exec.action_result->'verificationRerunPerformed'='false'::jsonb
      and v_exec.action_result->'mutationPerformed'='false'::jsonb;

    v_layer87_snapshot := jsonb_build_object(
      'reconciliationId',v_layer87.reconciliation_id,
      'layer86EventId',v_layer87.layer86_event_id,
      'targetExecutorEventId',v_layer87.target_executor_event_id,
      'layer82ReconciliationId',v_layer87.layer82_reconciliation_id,
      'reconciliationState',v_layer87.reconciliation_state,
      'reasonCode',v_layer87.reason_code,
      'policyIntegrityValid',v_layer87.policy_integrity_valid,
      'incidentBindingValid',v_layer87.incident_binding_valid,
      'layer82ProofIntegrityValid',v_layer87.layer82_proof_integrity_valid,
      'executionReceiptMatches',v_layer87.execution_receipt_matches,
      'beforeCoverageValid',v_layer87.before_coverage_valid,
      'afterCoverageValid',v_layer87.after_coverage_valid,
      'reconciliationProofSha256',v_layer87.reconciliation_proof_sha256,
      'reconciledAt',v_layer87.reconciled_at
    );
  end if;

  if v_layer87.reconciliation_id is null then
    v_state := 'missing-layer87-receipt';
    v_reason := 'case-audit-layer91-layer87-receipt-missing';
  elsif coalesce(v_layer87_integrity,false)=false then
    v_state := 'invalid-layer87-receipt';
    v_reason := 'case-audit-layer91-layer87-receipt-invalid';
  elsif not v_policy_integrity then
    v_state := 'policy-drift';
    v_reason := 'case-audit-layer91-policy-drift';
  elsif not v_incident_binding then
    v_state := 'incident-drift';
    v_reason := 'case-audit-layer91-incident-drift';
  elsif coalesce(v_execution_match,false)=false then
    v_state := 'execution-receipt-mismatch';
    v_reason := 'case-audit-layer91-receipt-mismatch';
  elsif not v_before_valid or not v_after_valid then
    v_state := 'coverage-drift';
    v_reason := 'case-audit-layer91-coverage-drift';
  else
    v_state := 'reconciled';
    v_reason := 'case-audit-layer91-complete';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer91ExecutionOutcome',
      'shine-foundation/case-audit-layer91-execution-outcome-v1',
    'schemaVersion','1.0.0',
    'status','evaluated',
    'layer91EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer86EventId',v_exec.target_layer86_event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'layer87ReconciliationId',v_layer87.reconciliation_id,
    'layer87ReconciliationState',v_layer87.reconciliation_state,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'policyIntegrityValid',v_policy_integrity,
    'incidentBindingValid',v_incident_binding,
    'layer87ProofIntegrityValid',v_layer87_integrity,
    'executionReceiptMatches',v_execution_match,
    'beforeCoverageValid',v_before_valid,
    'afterCoverageValid',v_after_valid,
    'layer91ActionResult',v_exec.action_result,
    'layer87Receipt',v_layer87_snapshot,
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
    'mutationPerformed',false
  );
end;
$layer92_evaluate$;

revoke all on function foundation.evaluate_case_audit_layer91_execution_outcome_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer91_execution_outcome_v1(
  uuid,timestamptz
) to foundation_runtime,service_role;
