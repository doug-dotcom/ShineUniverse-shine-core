-- Foundation Layer 102: independently evaluate one Layer-101 execution against durable Layer-97 truth.

create or replace function foundation.evaluate_case_audit_layer101_execution_outcome_v1(
  p_layer101_event_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer102_evaluate$
declare
  v_exec foundation.case_audit_layer97_reconcile_exec_events%rowtype;
  v_target foundation.case_audit_layer92_reconcile_exec_events%rowtype;
  v_layer97 foundation.case_audit_layer96_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_layer97_coverage_incident_events%rowtype;
  v_policy_integrity boolean := false;
  v_incident_binding boolean := false;
  v_layer97_integrity boolean;
  v_execution_match boolean;
  v_before_valid boolean := false;
  v_after_valid boolean := false;
  v_hash text;
  v_state text;
  v_reason text;
  v_layer97_snapshot jsonb;
begin
  if p_layer101_event_id is null then
    raise exception 'case-audit-layer101-outcome-event-id-required';
  end if;
  if p_as_of is null then
    raise exception 'case-audit-layer101-outcome-time-required';
  end if;

  select * into v_exec
  from foundation.case_audit_layer97_reconcile_exec_events
  where event_id=p_layer101_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditLayer101ExecutionOutcome',
        'shine-foundation/case-audit-layer101-execution-outcome-v1',
      'schemaVersion','1.0.0','status','not-found',
      'layer101EventId',p_layer101_event_id,
      'reconciliationState','not-applicable',
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
      'foundationCaseAuditLayer101ExecutionOutcome',
        'shine-foundation/case-audit-layer101-execution-outcome-v1',
      'schemaVersion','1.0.0','status','not-applicable',
      'layer101EventId',v_exec.event_id,
      'targetLayer96EventId',v_exec.target_layer96_event_id,
      'environment',v_exec.environment,
      'sourceEventType',v_exec.event_type,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-layer101-source-not-executed',
      'layer97RerunPerformed',false,'layer96RerunPerformed',false,
      'layer92RerunPerformed',false,'layer91RerunPerformed',false,
      'layer87RerunPerformed',false,'layer86RerunPerformed',false,
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'mutationPerformed',false
    );
  end if;

  select * into v_target
  from foundation.case_audit_layer92_reconcile_exec_events
  where event_id=v_exec.target_layer96_event_id
    and environment=v_exec.environment;

  select * into v_layer97
  from foundation.case_audit_layer96_exec_reconciliations
  where layer96_event_id=v_exec.target_layer96_event_id;

  select * into v_incident
  from foundation.case_audit_layer97_coverage_incident_events
  where event_id=v_exec.coverage_incident_event_id
    and environment=v_exec.environment;

  v_policy_integrity :=
    v_target.event_id is not null
    and foundation.case_audit_layer97_reconcile_exec_policy_fp_v1(
      v_exec.decision_snapshot,v_exec.incident_snapshot,v_exec.target_snapshot
    ) is not distinct from v_exec.policy_fingerprint
    and v_exec.action_key='run-independent-layer97-reconciliation'
    and v_exec.cause_class='layer97-reconciliation-omission'
    and v_exec.reason_code='case-audit-overdue-layer97-reconciliation-ran'
    and v_exec.decision_snapshot->>'foundationCaseAuditLayer97CoverageIncidentResponseDecision'
      is not distinct from
        'shine-foundation/case-audit-layer97-reconciliation-coverage-incident-response-decision-v1'
    and v_exec.decision_snapshot->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.decision_snapshot->>'decision'='admit'
    and v_exec.decision_snapshot->>'requiredControl'='layer-97-bounded-reconciler'
    and v_exec.decision_snapshot->>'causeClass'='layer97-reconciliation-omission'
    and v_exec.decision_snapshot->>'actionKey'='run-independent-layer97-reconciliation'
    and v_exec.decision_snapshot->'authorityExpansion'='false'::jsonb
    and v_exec.decision_snapshot->'automaticLayer97ReconciliationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticReconciliationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticRepairAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer97ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer96ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer92ReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'historyRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer96RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer92RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer91RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer87RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer86RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer82RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer81RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'verificationRerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'executesAction'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer97Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer96Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesLayer92Receipt'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer96'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer92'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer91'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer87'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer86'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer82'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer81'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsVerification'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesAuthoritativeTruth'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesIncidentHistory'='false'::jsonb
    and v_exec.target_snapshot->>'layer96EventId'
      is not distinct from v_target.event_id::text
    and v_exec.target_snapshot->>'targetLayer91EventId'
      is not distinct from v_target.target_layer91_event_id::text
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
    and v_exec.target_snapshot->'layer97ReconciliationAbsent'='true'::jsonb
    and nullif(v_exec.target_snapshot->>'layer97ReconciliationId','') is null;

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
    v_exec.before_coverage->>'foundationCaseAuditLayer97ReconciliationCoverage'
      is not distinct from
        'shine-foundation/case-audit-layer97-reconciliation-coverage-v1'
    and v_exec.before_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.before_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.before_coverage->>'state'='gap'
    and coalesce((v_exec.before_coverage->>'overdueCount')::integer,0)>0
    and v_exec.before_coverage->'layer97ReconciliationPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer96RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer92RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer91RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer87RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer86RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer82RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'mutationPerformed'='false'::jsonb;

  v_after_valid :=
    v_exec.after_coverage is not null
    and v_exec.after_coverage->>'foundationCaseAuditLayer97ReconciliationCoverage'
      is not distinct from
        'shine-foundation/case-audit-layer97-reconciliation-coverage-v1'
    and v_exec.after_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.after_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.after_coverage->'layer97ReconciliationPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer96RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer92RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer91RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer87RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer86RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer82RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'mutationPerformed'='false'::jsonb;

  if v_layer97.reconciliation_id is not null then
    v_hash := encode(
      extensions.digest(convert_to(v_layer97.reconciliation_proof::text,'UTF8'),'sha256'),
      'hex'
    );

    v_layer97_integrity :=
      v_hash is not distinct from v_layer97.reconciliation_proof_sha256
      and v_layer97.reconciliation_proof->>'foundationCaseAuditLayer96ExecutionReconciliationProof'
        is not distinct from
          'shine-foundation/case-audit-layer96-execution-reconciliation-proof-v1'
      and v_layer97.reconciliation_proof->>'schemaVersion' is not distinct from '1.0.0'
      and v_layer97.reconciliation_proof->>'reconciliationId'
        is not distinct from v_layer97.reconciliation_id::text
      and v_layer97.reconciliation_proof->>'layer96EventId'
        is not distinct from v_layer97.layer96_event_id::text
      and v_layer97.reconciliation_proof->>'environment'
        is not distinct from v_layer97.environment
      and v_layer97.reconciliation_proof->>'targetLayer91EventId'
        is not distinct from v_layer97.target_layer91_event_id::text
      and v_layer97.reconciliation_proof->>'layer92ReconciliationId'
        is not distinct from v_layer97.layer92_reconciliation_id::text
      and v_layer97.reconciliation_proof->>'reconciliationState'
        is not distinct from v_layer97.reconciliation_state
      and v_layer97.reconciliation_proof->>'reasonCode'
        is not distinct from v_layer97.reason_code
      and v_layer97.reconciliation_proof->'policyIntegrityValid'
        is not distinct from to_jsonb(v_layer97.policy_integrity_valid)
      and v_layer97.reconciliation_proof->'incidentBindingValid'
        is not distinct from to_jsonb(v_layer97.incident_binding_valid)
      and nullif(v_layer97.reconciliation_proof->'layer92ProofIntegrityValid','null'::jsonb)
        is not distinct from to_jsonb(v_layer97.layer92_proof_integrity_valid)
      and nullif(v_layer97.reconciliation_proof->'executionReceiptMatches','null'::jsonb)
        is not distinct from to_jsonb(v_layer97.execution_receipt_matches)
      and v_layer97.reconciliation_proof->'beforeCoverageValid'
        is not distinct from to_jsonb(v_layer97.before_coverage_valid)
      and v_layer97.reconciliation_proof->'afterCoverageValid'
        is not distinct from to_jsonb(v_layer97.after_coverage_valid)
      and v_layer97.reconciliation_proof->'layer96ActionResult'
        is not distinct from v_target.action_result
      and nullif(v_layer97.reconciliation_proof->'layer92Receipt','null'::jsonb)
        is not distinct from v_layer97.layer92_snapshot
      and v_layer97.reconciliation_proof->'reconciledAt'
        is not distinct from to_jsonb(v_layer97.reconciled_at)
      and v_layer97.reconciliation_proof->'layer92RerunPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer91RerunPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer87RerunPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer86RerunPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer82RerunPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer81RerunPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer92ReceiptRewritePerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer91ReceiptRewritePerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'layer87ReceiptRewritePerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'releaseTruthMutationPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'incidentHistoryMutationPerformed'='false'::jsonb
      and v_layer97.reconciliation_proof->'approvalGranted'='false'::jsonb
      and v_layer97.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
      and v_layer97.reconciliation_proof->'mutationPerformed'='false'::jsonb
      and v_layer97.layer96_snapshot->>'layer96EventId'
        is not distinct from v_target.event_id::text
      and v_layer97.layer96_snapshot->>'targetLayer91EventId'
        is not distinct from v_target.target_layer91_event_id::text
      and v_layer97.layer96_snapshot->>'coverageIncidentEventId'
        is not distinct from v_target.coverage_incident_event_id::text
      and v_layer97.layer96_snapshot->>'actionKey'
        is not distinct from v_target.action_key
      and v_layer97.layer96_snapshot->>'causeClass'
        is not distinct from v_target.cause_class
      and v_layer97.layer96_snapshot->>'policyFingerprint'
        is not distinct from v_target.policy_fingerprint
      and v_layer97.layer96_snapshot->>'eventType'
        is not distinct from v_target.event_type
      and v_layer97.layer96_snapshot->>'reasonCode'
        is not distinct from v_target.reason_code
      and v_layer97.layer96_snapshot->'requestedAt'
        is not distinct from to_jsonb(v_target.requested_at);

    v_execution_match :=
      v_exec.action_result->>'foundationCaseAuditLayer96ExecutionReconciliation'
        is not distinct from
          'shine-foundation/case-audit-layer96-execution-reconciliation-v1'
      and v_exec.action_result->>'schemaVersion' is not distinct from '1.0.0'
      and v_exec.action_result->>'status' in ('recorded','existing')
      and v_exec.action_result->>'reconciliationId'
        is not distinct from v_layer97.reconciliation_id::text
      and v_exec.action_result->>'layer96EventId'
        is not distinct from v_layer97.layer96_event_id::text
      and v_exec.action_result->>'targetLayer91EventId'
        is not distinct from v_layer97.target_layer91_event_id::text
      and v_exec.action_result->>'layer92ReconciliationId'
        is not distinct from v_layer97.layer92_reconciliation_id::text
      and v_exec.action_result->>'reconciliationState'
        is not distinct from v_layer97.reconciliation_state
      and v_exec.action_result->>'reasonCode'
        is not distinct from v_layer97.reason_code
      and v_exec.action_result->>'reconciliationProofSha256'
        is not distinct from v_layer97.reconciliation_proof_sha256
      and v_exec.action_result->'layer92RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer91RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer87RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer86RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer82RerunPerformed'='false'::jsonb
      and v_exec.action_result->'layer81RerunPerformed'='false'::jsonb
      and v_exec.action_result->'verificationRerunPerformed'='false'::jsonb
      and v_exec.action_result->'mutationPerformed'='false'::jsonb;

    v_layer97_snapshot := jsonb_build_object(
      'reconciliationId',v_layer97.reconciliation_id,
      'layer96EventId',v_layer97.layer96_event_id,
      'targetLayer91EventId',v_layer97.target_layer91_event_id,
      'layer92ReconciliationId',v_layer97.layer92_reconciliation_id,
      'reconciliationState',v_layer97.reconciliation_state,
      'reasonCode',v_layer97.reason_code,
      'policyIntegrityValid',v_layer97.policy_integrity_valid,
      'incidentBindingValid',v_layer97.incident_binding_valid,
      'layer92ProofIntegrityValid',v_layer97.layer92_proof_integrity_valid,
      'executionReceiptMatches',v_layer97.execution_receipt_matches,
      'beforeCoverageValid',v_layer97.before_coverage_valid,
      'afterCoverageValid',v_layer97.after_coverage_valid,
      'reconciliationProofSha256',v_layer97.reconciliation_proof_sha256,
      'reconciledAt',v_layer97.reconciled_at
    );
  end if;

  if v_layer97.reconciliation_id is null then
    v_state := 'missing-layer97-receipt';
    v_reason := 'case-audit-layer101-layer97-receipt-missing';
  elsif coalesce(v_layer97_integrity,false)=false then
    v_state := 'invalid-layer97-receipt';
    v_reason := 'case-audit-layer101-layer97-receipt-invalid';
  elsif not v_policy_integrity then
    v_state := 'policy-drift';
    v_reason := 'case-audit-layer101-policy-drift';
  elsif not v_incident_binding then
    v_state := 'incident-drift';
    v_reason := 'case-audit-layer101-incident-drift';
  elsif coalesce(v_execution_match,false)=false then
    v_state := 'execution-receipt-mismatch';
    v_reason := 'case-audit-layer101-receipt-mismatch';
  elsif not v_before_valid or not v_after_valid then
    v_state := 'coverage-drift';
    v_reason := 'case-audit-layer101-coverage-drift';
  else
    v_state := 'reconciled';
    v_reason := 'case-audit-layer101-complete';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer101ExecutionOutcome',
      'shine-foundation/case-audit-layer101-execution-outcome-v1',
    'schemaVersion','1.0.0','status','evaluated',
    'layer101EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetLayer96EventId',v_exec.target_layer96_event_id,
    'coverageIncidentEventId',v_exec.coverage_incident_event_id,
    'layer97ReconciliationId',v_layer97.reconciliation_id,
    'layer97ReconciliationState',v_layer97.reconciliation_state,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'policyIntegrityValid',v_policy_integrity,
    'incidentBindingValid',v_incident_binding,
    'layer97ProofIntegrityValid',v_layer97_integrity,
    'executionReceiptMatches',v_execution_match,
    'beforeCoverageValid',v_before_valid,
    'afterCoverageValid',v_after_valid,
    'layer101ActionResult',v_exec.action_result,
    'layer97Receipt',v_layer97_snapshot,
    'layer97RerunPerformed',false,'layer96RerunPerformed',false,
    'layer92RerunPerformed',false,'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
    'layer97ReceiptRewritePerformed',false,'layer96ReceiptRewritePerformed',false,
    'layer92ReceiptRewritePerformed',false,'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,'mutationPerformed',false
  );
end;
$layer102_evaluate$;

revoke all on function foundation.evaluate_case_audit_layer101_execution_outcome_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer101_execution_outcome_v1(
  uuid,timestamptz
) to foundation_runtime,service_role;
