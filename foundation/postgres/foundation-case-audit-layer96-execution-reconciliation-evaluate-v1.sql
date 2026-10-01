-- Foundation Layer 97: independently evaluate one Layer-96 execution against durable Layer-92 truth.

create or replace function foundation.evaluate_case_audit_layer96_execution_outcome_v1(
  p_layer96_event_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer97_evaluate$
declare
  v_exec foundation.case_audit_layer92_reconcile_exec_events%rowtype;
  v_target foundation.case_audit_reconcile_exec_reconcile_exec_events%rowtype;
  v_layer92 foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_layer92_coverage_incident_events%rowtype;
  v_policy_integrity boolean := false;
  v_incident_binding boolean := false;
  v_layer92_integrity boolean;
  v_execution_match boolean;
  v_before_valid boolean := false;
  v_after_valid boolean := false;
  v_recomputed_layer92_hash text;
  v_state text;
  v_reason text;
  v_layer92_snapshot jsonb;
begin
  if p_layer96_event_id is null then
    raise exception 'case-audit-layer96-outcome-event-id-required';
  end if;

  if p_as_of is null then
    raise exception 'case-audit-layer96-outcome-time-required';
  end if;

  select * into v_exec
  from foundation.case_audit_layer92_reconcile_exec_events
  where event_id=p_layer96_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditLayer96ExecutionOutcome',
        'shine-foundation/case-audit-layer96-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-found',
      'layer96EventId',p_layer96_event_id,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-layer96-event-not-found',
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
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
      'foundationCaseAuditLayer96ExecutionOutcome',
        'shine-foundation/case-audit-layer96-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'layer96EventId',v_exec.event_id,
      'targetLayer91EventId',v_exec.target_layer91_event_id,
      'environment',v_exec.environment,
      'sourceEventType',v_exec.event_type,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-layer96-source-not-executed',
      'layer92RerunPerformed',false,
      'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,
      'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  select * into v_target
  from foundation.case_audit_reconcile_exec_reconcile_exec_events
  where event_id=v_exec.target_layer91_event_id
    and environment=v_exec.environment;

  select * into v_layer92
  from foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations
  where layer91_event_id=v_exec.target_layer91_event_id;

  select * into v_incident
  from foundation.case_audit_layer92_coverage_incident_events
  where event_id=v_exec.coverage_incident_event_id
    and environment=v_exec.environment;

  v_policy_integrity :=
    v_target.event_id is not null
    and foundation.case_audit_layer92_reconcile_exec_policy_fp_v1(
          v_exec.decision_snapshot,
          v_exec.incident_snapshot,
          v_exec.target_snapshot
        ) is not distinct from v_exec.policy_fingerprint
    and v_exec.action_key='run-independent-layer92-reconciliation'
    and v_exec.cause_class='layer92-reconciliation-omission'
    and v_exec.reason_code='case-audit-overdue-layer92-reconciliation-ran'
    and v_exec.decision_snapshot->>
          'foundationCaseAuditLayer92CoverageIncidentResponseDecision'
        is not distinct from
          'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-response-decision-v1'
    and v_exec.decision_snapshot->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.decision_snapshot->>'decision'='admit'
    and v_exec.decision_snapshot->>'requiredControl'='layer-92-bounded-reconciler'
    and v_exec.decision_snapshot->>'causeClass'='layer92-reconciliation-omission'
    and v_exec.decision_snapshot->>'actionKey'='run-independent-layer92-reconciliation'
    and v_exec.decision_snapshot->'authorityExpansion'='false'::jsonb
    and v_exec.decision_snapshot->'automaticLayer92ReconciliationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticReconciliationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticRepairAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer92ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer91ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer87ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'historyRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer91RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer87RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer86RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer82RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer81RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'verificationRerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'executesAction'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer92Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer91Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer87Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer91'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer87'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer86'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer82'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer81'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsVerification'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesAuthoritativeTruth'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesIncidentHistory'='false'::jsonb
    and v_exec.target_snapshot->>'layer91EventId'
        is not distinct from v_target.event_id::text
    and v_exec.target_snapshot->>'targetLayer86EventId'
        is not distinct from v_target.target_layer86_event_id::text
    and v_exec.target_snapshot->>'coverageIncidentEventId'
        is not distinct from v_target.coverage_incident_event_id::text
    and v_exec.target_snapshot->>'actionKey' is not distinct from v_target.action_key
    and v_exec.target_snapshot->>'causeClass' is not distinct from v_target.cause_class
    and v_exec.target_snapshot->>'policyFingerprint'
        is not distinct from v_target.policy_fingerprint
    and v_exec.target_snapshot->>'eventType' is not distinct from v_target.event_type
    and v_exec.target_snapshot->>'reasonCode' is not distinct from v_target.reason_code
    and v_exec.target_snapshot->'requestedAt'
        is not distinct from to_jsonb(v_target.requested_at)
    and v_exec.target_snapshot->'layer92ReconciliationAbsent'='true'::jsonb
    and nullif(v_exec.target_snapshot->>'layer92ReconciliationId','') is null;

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
    v_exec.before_coverage->>'foundationCaseAuditLayer92ReconciliationCoverage'
      is not distinct from
        'shine-foundation/case-audit-layer92-reconciliation-coverage-v1'
    and v_exec.before_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.before_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.before_coverage->>'state'='gap'
    and coalesce((v_exec.before_coverage->>'overdueCount')::integer,0)>0
    and v_exec.before_coverage->'layer92ReconciliationPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer91RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer87RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer86RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer82RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'mutationPerformed'='false'::jsonb;

  v_after_valid :=
    v_exec.after_coverage is not null
    and v_exec.after_coverage->>'foundationCaseAuditLayer92ReconciliationCoverage'
      is not distinct from
        'shine-foundation/case-audit-layer92-reconciliation-coverage-v1'
    and v_exec.after_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.after_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.after_coverage->'layer92ReconciliationPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer91RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer87RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer86RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer82RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'mutationPerformed'='false'::jsonb;

  if v_layer92.reconciliation_id is not null then
    v_recomputed_layer92_hash := encode(
      extensions.digest(
        convert_to(v_layer92.reconciliation_proof::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    v_layer92_integrity :=
      v_recomputed_layer92_hash
        is not distinct from v_layer92.reconciliation_proof_sha256
      and v_layer92.reconciliation_proof->>
            'foundationCaseAuditLayer91ExecutionReconciliationProof'
          is not distinct from
            'shine-foundation/case-audit-layer91-execution-reconciliation-proof-v1'
      and v_layer92.reconciliation_proof->>'schemaVersion'
          is not distinct from '1.0.0'
      and v_layer92.reconciliation_proof->>'reconciliationId'
          is not distinct from v_layer92.reconciliation_id::text
      and v_layer92.reconciliation_proof->>'layer91EventId'
          is not distinct from v_layer92.layer91_event_id::text
      and v_layer92.reconciliation_proof->>'environment'
          is not distinct from v_layer92.environment
      and v_layer92.reconciliation_proof->>'targetLayer86EventId'
          is not distinct from v_layer92.target_layer86_event_id::text
      and v_layer92.reconciliation_proof->>'layer87ReconciliationId'
          is not distinct from v_layer92.layer87_reconciliation_id::text
      and v_layer92.reconciliation_proof->>'reconciliationState'
          is not distinct from v_layer92.reconciliation_state
      and v_layer92.reconciliation_proof->>'reasonCode'
          is not distinct from v_layer92.reason_code
      and v_layer92.reconciliation_proof->'policyIntegrityValid'
          is not distinct from to_jsonb(v_layer92.policy_integrity_valid)
      and v_layer92.reconciliation_proof->'incidentBindingValid'
          is not distinct from to_jsonb(v_layer92.incident_binding_valid)
      and nullif(
            v_layer92.reconciliation_proof->'layer87ProofIntegrityValid',
            'null'::jsonb
          ) is not distinct from to_jsonb(v_layer92.layer87_proof_integrity_valid)
      and nullif(
            v_layer92.reconciliation_proof->'executionReceiptMatches',
            'null'::jsonb
          ) is not distinct from to_jsonb(v_layer92.execution_receipt_matches)
      and v_layer92.reconciliation_proof->'beforeCoverageValid'
          is not distinct from to_jsonb(v_layer92.before_coverage_valid)
      and v_layer92.reconciliation_proof->'afterCoverageValid'
          is not distinct from to_jsonb(v_layer92.after_coverage_valid)
      and v_layer92.reconciliation_proof->'layer91ActionResult'
          is not distinct from v_target.action_result
      and nullif(v_layer92.reconciliation_proof->'layer87Receipt','null'::jsonb)
          is not distinct from v_layer92.layer87_snapshot
      and v_layer92.reconciliation_proof->'reconciledAt'
          is not distinct from to_jsonb(v_layer92.reconciled_at)
      and v_layer92.reconciliation_proof->'layer87RerunPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'layer86RerunPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'layer82RerunPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'layer81RerunPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'layer87ReceiptRewritePerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'layer86ReceiptRewritePerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'layer82ReceiptRewritePerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'releaseTruthMutationPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'incidentHistoryMutationPerformed'='false'::jsonb
      and v_layer92.reconciliation_proof->'approvalGranted'='false'::jsonb
      and v_layer92.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
      and v_layer92.reconciliation_proof->'mutationPerformed'='false'::jsonb
      and v_layer92.layer91_snapshot->>'layer91EventId'
          is not distinct from v_target.event_id::text
      and v_layer92.layer91_snapshot->>'targetLayer86EventId'
          is not distinct from v_target.target_layer86_event_id::text
      and v_layer92.layer91_snapshot->>'coverageIncidentEventId'
          is not distinct from v_target.coverage_incident_event_id::text
      and v_layer92.layer91_snapshot->>'actionKey'
          is not distinct from v_target.action_key
      and v_layer92.layer91_snapshot->>'causeClass'
          is not distinct from v_target.cause_class
      and v_layer92.layer91_snapshot->>'policyFingerprint'
          is not distinct from v_target.policy_fingerprint
      and v_layer92.layer91_snapshot->>'eventType'
          is not distinct from v_target.event_type
      and v_layer92.layer91_snapshot->>'reasonCode'
          is not distinct from v_target.reason_code
      and v_layer92.layer91_snapshot->'requestedAt'
          is not distinct from to_jsonb(v_target.requested_at)
      and (
        (v_layer92.reconciliation_state='reconciled'
         and v_layer92.layer87_reconciliation_id is not null
         and v_layer92.policy_integrity_valid
         and v_layer92.incident_binding_valid
         and v_layer92.layer87_proof_integrity_valid is true
         and v_layer92.execution_receipt_matches is true
         and v_layer92.before_coverage_valid
         and v_layer92.after_coverage_valid)
        or
        (v_layer92.reconciliation_state='missing-layer87-receipt'
         and v_layer92.layer87_reconciliation_id is null
         and v_layer92.layer87_snapshot is null)
        or
        (v_layer92.reconciliation_state='invalid-layer87-receipt'
         and v_layer92.layer87_reconciliation_id is not null
         and v_layer92.layer87_proof_integrity_valid is false)
        or
        (v_layer92.reconciliation_state='execution-receipt-mismatch'
         and v_layer92.layer87_reconciliation_id is not null
         and v_layer92.layer87_proof_integrity_valid is true
         and v_layer92.execution_receipt_matches is false)
        or
        (v_layer92.reconciliation_state='policy-drift'
         and v_layer92.layer87_reconciliation_id is not null
         and v_layer92.layer87_proof_integrity_valid is true
         and v_layer92.policy_integrity_valid is false)
        or
        (v_layer92.reconciliation_state='incident-drift'
         and v_layer92.layer87_reconciliation_id is not null
         and v_layer92.layer87_proof_integrity_valid is true
         and v_layer92.policy_integrity_valid is true
         and v_layer92.incident_binding_valid is false)
        or
        (v_layer92.reconciliation_state='coverage-drift'
         and v_layer92.layer87_reconciliation_id is not null
         and v_layer92.layer87_proof_integrity_valid is true
         and v_layer92.policy_integrity_valid is true
         and v_layer92.incident_binding_valid is true
         and v_layer92.execution_receipt_matches is true
         and (
           v_layer92.before_coverage_valid is false
           or v_layer92.after_coverage_valid is false
         ))
      );

    v_execution_match :=
      v_exec.action_result->>'foundationCaseAuditLayer91ExecutionReconciliation'
        is not distinct from
          'shine-foundation/case-audit-layer91-execution-reconciliation-v1'
      and v_exec.action_result->>'schemaVersion' is not distinct from '1.0.0'
      and v_exec.action_result->>'status' in ('recorded','existing')
      and v_exec.action_result->>'reconciliationId'
          is not distinct from v_layer92.reconciliation_id::text
      and v_exec.action_result->>'layer91EventId'
          is not distinct from v_layer92.layer91_event_id::text
      and v_exec.action_result->>'targetLayer86EventId'
          is not distinct from v_layer92.target_layer86_event_id::text
      and v_exec.action_result->>'layer87ReconciliationId'
          is not distinct from v_layer92.layer87_reconciliation_id::text
      and v_exec.action_result->>'reconciliationState'
          is not distinct from v_layer92.reconciliation_state
      and v_exec.action_result->>'reasonCode'
          is not distinct from v_layer92.reason_code
      and v_exec.action_result->>'reconciliationProofSha256'
          is not distinct from v_layer92.reconciliation_proof_sha256
      and v_exec.action_result->'layer87RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer86RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer82RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer81RerunPerformed'='false'::jsonb
      and v_exec.action_result->'verificationRerunPerformed'='false'::jsonb
      and v_exec.action_result->'mutationPerformed'='false'::jsonb;

    v_layer92_snapshot := jsonb_build_object(
      'reconciliationId',v_layer92.reconciliation_id,
      'layer91EventId',v_layer92.layer91_event_id,
      'targetLayer86EventId',v_layer92.target_layer86_event_id,
      'layer87ReconciliationId',v_layer92.layer87_reconciliation_id,
      'reconciliationState',v_layer92.reconciliation_state,
      'reasonCode',v_layer92.reason_code,
      'policyIntegrityValid',v_layer92.policy_integrity_valid,
      'incidentBindingValid',v_layer92.incident_binding_valid,
      'layer87ProofIntegrityValid',v_layer92.layer87_proof_integrity_valid,
      'executionReceiptMatches',v_layer92.execution_receipt_matches,
      'beforeCoverageValid',v_layer92.before_coverage_valid,
      'afterCoverageValid',v_layer92.after_coverage_valid,
      'reconciliationProofSha256',v_layer92.reconciliation_proof_sha256,
      'reconciledAt',v_layer92.reconciled_at
    );
  end if;

  if v_layer92.reconciliation_id is null then
    v_state := 'missing-layer92-receipt';
    v_reason := 'case-audit-layer96-layer92-receipt-missing';
  elsif coalesce(v_layer92_integrity,false)=false then
    v_state := 'invalid-layer92-receipt';
    v_reason := 'case-audit-layer96-layer92-receipt-invalid';
  elsif not v_policy_integrity then
    v_state := 'policy-drift';
    v_reason := 'case-audit-layer96-policy-drift';
  elsif not v_incident_binding then
    v_state := 'incident-drift';
    v_reason := 'case-audit-layer96-incident-drift';
  elsif coalesce(v_execution_match,false)=false then
    v_state := 'execution-receipt-mismatch';
    v_reason := 'case-audit-layer96-receipt-mismatch';
  elsif not v_before_valid or not v_after_valid then
    v_state := 'coverage-drift';
    v_reason := 'case-audit-layer96-coverage-drift';
  else
    v_state := 'reconciled';
    v_reason := 'case-audit-layer96-complete';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer96ExecutionOutcome',
      'shine-foundation/case-audit-layer96-execution-outcome-v1',
    'schemaVersion','1.0.0',
    'status','evaluated',
    'layer96EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer91EventId',v_exec.target_layer91_event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'layer92ReconciliationId',v_layer92.reconciliation_id,
    'layer92ReconciliationState',v_layer92.reconciliation_state,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'policyIntegrityValid',v_policy_integrity,
    'incidentBindingValid',v_incident_binding,
    'layer92ProofIntegrityValid',v_layer92_integrity,
    'executionReceiptMatches',v_execution_match,
    'beforeCoverageValid',v_before_valid,
    'afterCoverageValid',v_after_valid,
    'layer96ActionResult',v_exec.action_result,
    'layer92Receipt',v_layer92_snapshot,
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
    'mutationPerformed',false
  );
end;
$layer97_evaluate$;

revoke all on function foundation.evaluate_case_audit_layer96_execution_outcome_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer96_execution_outcome_v1(
  uuid,timestamptz
) to foundation_runtime,service_role;
