-- Foundation Layer 87: independent reconciliation of Layer-86 execution receipts.
-- Layer 86 may claim that it invoked Layer 82 for one overdue Layer-81 target.
-- Layer 87 never trusts that claim by itself. It independently binds the
-- Layer-86 policy/incident/target envelope to the durable Layer-82 receipt,
-- recomputes Layer-82 proof integrity, and records immutable reconciliation
-- without rerunning Layer 82, Layer 81, verification, or any earlier control.

create table foundation.case_audit_verify_reconcile_exec_reconciliations (
  reconciliation_sequence bigint generated always as identity primary key,
  reconciliation_id uuid not null unique default gen_random_uuid(),
  layer86_event_id uuid not null unique
    references foundation.case_audit_verify_reconcile_exec_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_executor_event_id uuid not null
    references foundation.case_audit_verify_exec_events(event_id),
  layer82_reconciliation_id uuid
    references foundation.case_audit_verify_exec_reconciliations(reconciliation_id),
  reconciliation_state text not null
    check (
      reconciliation_state in (
        'reconciled',
        'missing-layer82-receipt',
        'invalid-layer82-receipt',
        'execution-receipt-mismatch',
        'policy-drift',
        'incident-drift',
        'coverage-drift'
      )
    ),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  policy_integrity_valid boolean not null,
  incident_binding_valid boolean not null,
  layer82_proof_integrity_valid boolean,
  execution_receipt_matches boolean,
  before_coverage_valid boolean not null,
  after_coverage_valid boolean not null,
  layer86_snapshot jsonb not null
    check (jsonb_typeof(layer86_snapshot)='object'),
  layer82_snapshot jsonb
    check (layer82_snapshot is null or jsonb_typeof(layer82_snapshot)='object'),
  reconciliation_proof jsonb not null
    check (jsonb_typeof(reconciliation_proof)='object'),
  reconciliation_proof_sha256 text not null
    check (reconciliation_proof_sha256 ~ '^[a-f0-9]{64}$'),
  reconciled_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_verify_reconcile_exec_reconciliations
  enable row level security;

create policy foundation_runtime_case_audit_verify_reconcile_exec_reconcile_select
on foundation.case_audit_verify_reconcile_exec_reconciliations
for select
to foundation_runtime
using (true);

revoke all on foundation.case_audit_verify_reconcile_exec_reconciliations
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_verify_reconcile_exec_reconciliations
  to foundation_runtime,service_role;

create index case_audit_verify_reconcile_exec_reconcile_target_idx
  on foundation.case_audit_verify_reconcile_exec_reconciliations(
    target_executor_event_id,reconciled_at desc,reconciliation_sequence desc
  );

create index case_audit_verify_reconcile_exec_reconcile_state_idx
  on foundation.case_audit_verify_reconcile_exec_reconciliations(
    reconciliation_state,reconciled_at desc,reconciliation_sequence desc
  );

create trigger case_audit_verify_reconcile_exec_reconcile_append_only
before update or delete
on foundation.case_audit_verify_reconcile_exec_reconciliations
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
  p_layer86_event_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer87_evaluate$
declare
  v_exec foundation.case_audit_verify_reconcile_exec_events%rowtype;
  v_target foundation.case_audit_verify_exec_events%rowtype;
  v_layer82 foundation.case_audit_verify_exec_reconciliations%rowtype;
  v_incident foundation.case_audit_verify_reconcile_incident_events%rowtype;
  v_policy_integrity boolean := false;
  v_incident_binding boolean := false;
  v_layer82_integrity boolean;
  v_execution_match boolean;
  v_before_valid boolean := false;
  v_after_valid boolean := false;
  v_recomputed_layer82_hash text;
  v_state text;
  v_reason text;
  v_layer82_snapshot jsonb;
begin
  if p_layer86_event_id is null then
    raise exception 'case-audit-reconcile-exec-outcome-event-id-required';
  end if;

  if p_as_of is null then
    raise exception 'case-audit-reconcile-exec-outcome-time-required';
  end if;

  select * into v_exec
  from foundation.case_audit_verify_reconcile_exec_events
  where event_id=p_layer86_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionOutcome',
        'shine-foundation/case-audit-reconciliation-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-found',
      'layer86EventId',p_layer86_event_id,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-reconcile-exec-event-not-found',
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionOutcome',
        'shine-foundation/case-audit-reconciliation-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'layer86EventId',v_exec.event_id,
      'targetExecutorEventId',v_exec.target_executor_event_id,
      'environment',v_exec.environment,
      'sourceEventType',v_exec.event_type,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-reconcile-exec-source-not-executed',
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  select * into v_target
  from foundation.case_audit_verify_exec_events
  where event_id=v_exec.target_executor_event_id
    and environment=v_exec.environment;

  select * into v_layer82
  from foundation.case_audit_verify_exec_reconciliations
  where executor_event_id=v_exec.target_executor_event_id;

  select * into v_incident
  from foundation.case_audit_verify_reconcile_incident_events
  where event_id=v_exec.reconciliation_incident_event_id
    and environment=v_exec.environment;

  v_policy_integrity :=
    v_target.event_id is not null
    and foundation.case_audit_verify_reconcile_exec_policy_fp_v1(
          v_exec.decision_snapshot,
          v_exec.incident_snapshot,
          v_exec.target_snapshot
        ) is not distinct from v_exec.policy_fingerprint
    and v_exec.action_key='run-independent-reconciliation'
    and v_exec.cause_class='reconciliation-omission'
    and v_exec.reason_code='case-audit-overdue-reconciliation-layer82-ran'
    and v_exec.decision_snapshot->>
          'foundationCaseAuditVerificationReconciliationIncidentResponseDecision'
        is not distinct from
          'shine-foundation/case-audit-verification-reconciliation-incident-response-decision-v1'
    and v_exec.decision_snapshot->>'schemaVersion'
        is not distinct from '1.0.0'
    and v_exec.decision_snapshot->>'decision'='admit'
    and v_exec.decision_snapshot->>'requiredControl'
        ='layer-82-bounded-reconciler'
    and v_exec.decision_snapshot->>'causeClass'='reconciliation-omission'
    and v_exec.decision_snapshot->>'actionKey'='run-independent-reconciliation'
    and v_exec.decision_snapshot->'authorityExpansion'='false'::jsonb
    and v_exec.decision_snapshot->'automaticReconciliationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticVerificationAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'automaticRepairAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'reconciliationReceiptRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'verificationProofRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'historyRewriteAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'layer81RerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'verificationRerunAllowed'='false'::jsonb
    and v_exec.decision_snapshot->'executesAction'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsLayer81'='false'::jsonb
    and v_exec.decision_snapshot->'rerunsVerification'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesReconciliationReceipt'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesVerificationProof'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesAuthoritativeTruth'='false'::jsonb
    and v_exec.decision_snapshot->'mutatesIncidentHistory'='false'::jsonb
    and v_exec.target_snapshot->>'executorEventId'
        is not distinct from v_target.event_id::text
    and v_exec.target_snapshot->>'targetExecutionEventId'
        is not distinct from v_target.target_execution_event_id::text
    and v_exec.target_snapshot->>'verificationIncidentEventId'
        is not distinct from v_target.verification_incident_event_id::text
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
    and v_exec.target_snapshot->'reconciliationAbsent'='true'::jsonb
    and nullif(v_exec.target_snapshot->>'reconciliationId','') is null;

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
          'foundationCaseAuditVerificationReconciliationCoverage'
      is not distinct from
          'shine-foundation/case-audit-verification-reconciliation-coverage-v1'
    and v_exec.before_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.before_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.before_coverage->>'state'='gap'
    and coalesce((v_exec.before_coverage->>'overdueCount')::integer,0)>0
    and v_exec.before_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.before_coverage->'mutationPerformed'='false'::jsonb;

  v_after_valid :=
    v_exec.after_coverage is not null
    and v_exec.after_coverage->>
          'foundationCaseAuditVerificationReconciliationCoverage'
      is not distinct from
          'shine-foundation/case-audit-verification-reconciliation-coverage-v1'
    and v_exec.after_coverage->>'schemaVersion' is not distinct from '1.0.0'
    and v_exec.after_coverage->>'environment' is not distinct from v_exec.environment
    and v_exec.after_coverage->'verificationRerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'layer81RerunPerformed'='false'::jsonb
    and v_exec.after_coverage->'mutationPerformed'='false'::jsonb;

  if v_layer82.reconciliation_id is not null then
    v_recomputed_layer82_hash := encode(
      extensions.digest(
        convert_to(v_layer82.reconciliation_proof::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    v_layer82_integrity :=
      v_recomputed_layer82_hash
        is not distinct from v_layer82.reconciliation_proof_sha256
      and v_layer82.reconciliation_proof->>
            'foundationCaseAuditVerificationExecutionReconciliationProof'
          is not distinct from
            'shine-foundation/case-audit-verification-execution-reconciliation-proof-v1'
      and v_layer82.reconciliation_proof->>'schemaVersion'
          is not distinct from '1.0.0'
      and v_layer82.reconciliation_proof->>'reconciliationId'
          is not distinct from v_layer82.reconciliation_id::text
      and v_layer82.reconciliation_proof->>'executorEventId'
          is not distinct from v_layer82.executor_event_id::text
      and v_layer82.reconciliation_proof->>'environment'
          is not distinct from v_layer82.environment
      and v_layer82.reconciliation_proof->>'targetExecutionEventId'
          is not distinct from v_layer82.target_execution_event_id::text
      and v_layer82.reconciliation_proof->>'verificationId'
          is not distinct from v_layer82.verification_id::text
      and v_layer82.reconciliation_proof->>'verificationState'
          is not distinct from v_layer82.verification_state
      and v_layer82.reconciliation_proof->>'reconciliationState'
          is not distinct from v_layer82.reconciliation_state
      and v_layer82.reconciliation_proof->>'reasonCode'
          is not distinct from v_layer82.reason_code
      and v_layer82.reconciliation_proof->'layer81ActionResult'
          is not distinct from v_layer82.layer81_action_result
      and v_layer82.layer81_action_result is not distinct from v_target.action_result
      and nullif(v_layer82.reconciliation_proof->'proofIntegrityValid','null'::jsonb)
          is not distinct from to_jsonb(v_layer82.proof_integrity_valid)
      and nullif(v_layer82.reconciliation_proof->'receiptMatchesProof','null'::jsonb)
          is not distinct from to_jsonb(v_layer82.receipt_matches_proof)
      and nullif(v_layer82.reconciliation_proof->'currentEvaluationMatches','null'::jsonb)
          is not distinct from to_jsonb(v_layer82.current_evaluation_matches)
      and v_layer82.reconciliation_proof->'coverageTargetVisible'
          is not distinct from to_jsonb(v_layer82.coverage_target_visible)
      and nullif(v_layer82.reconciliation_proof->'coverageTargetMatches','null'::jsonb)
          is not distinct from to_jsonb(v_layer82.coverage_target_matches)
      and nullif(v_layer82.reconciliation_proof->'verification','null'::jsonb)
          is not distinct from v_layer82.verification_snapshot
      and nullif(v_layer82.reconciliation_proof->'currentEvaluation','null'::jsonb)
          is not distinct from v_layer82.current_evaluation
      and v_layer82.reconciliation_proof->'currentCoverage'
          is not distinct from v_layer82.current_coverage
      and v_layer82.reconciliation_proof->'reconciledAt'
          is not distinct from to_jsonb(v_layer82.reconciled_at)
      and v_layer82.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
      and v_layer82.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
      and v_layer82.reconciliation_proof->'verificationProofRewritePerformed'='false'::jsonb
      and v_layer82.reconciliation_proof->'releaseTruthMutationPerformed'='false'::jsonb
      and v_layer82.reconciliation_proof->'incidentHistoryMutationPerformed'='false'::jsonb
      and v_layer82.reconciliation_proof->'approvalGranted'='false'::jsonb
      and v_layer82.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
      and v_layer82.reconciliation_proof->'mutationPerformed'='false'::jsonb
      and (
        (
          v_layer82.reconciliation_state='reconciled'
          and v_layer82.verification_id is not null
          and v_layer82.proof_integrity_valid is true
          and v_layer82.receipt_matches_proof is true
          and v_layer82.current_evaluation_matches is true
          and (
            v_layer82.coverage_target_visible=false
            or v_layer82.coverage_target_matches is true
          )
        )
        or
        (
          v_layer82.reconciliation_state='missing-proof'
          and v_layer82.verification_id is null
        )
        or
        (
          v_layer82.reconciliation_state='receipt-mismatch'
          and v_layer82.verification_id is not null
          and v_layer82.receipt_matches_proof is false
        )
        or
        (
          v_layer82.reconciliation_state='invalid-proof'
          and v_layer82.verification_id is not null
          and v_layer82.proof_integrity_valid is false
        )
        or
        (
          v_layer82.reconciliation_state='evidence-drift'
          and v_layer82.verification_id is not null
          and v_layer82.proof_integrity_valid is true
          and v_layer82.receipt_matches_proof is true
          and v_layer82.current_evaluation_matches is false
        )
        or
        (
          v_layer82.reconciliation_state='coverage-drift'
          and v_layer82.verification_id is not null
          and v_layer82.proof_integrity_valid is true
          and v_layer82.receipt_matches_proof is true
          and v_layer82.current_evaluation_matches is true
          and v_layer82.coverage_target_visible=true
          and v_layer82.coverage_target_matches is false
        )
      );

    v_execution_match :=
      v_exec.action_result->>
          'foundationCaseAuditVerificationExecutionReconciliation'
        is not distinct from
          'shine-foundation/case-audit-verification-execution-reconciliation-v1'
      and v_exec.action_result->>'schemaVersion' is not distinct from '1.0.0'
      and v_exec.action_result->>'status' in ('recorded','existing')
      and v_exec.action_result->>'reconciliationId'
          is not distinct from v_layer82.reconciliation_id::text
      and v_exec.action_result->>'executorEventId'
          is not distinct from v_layer82.executor_event_id::text
      and v_exec.action_result->>'targetExecutionEventId'
          is not distinct from v_layer82.target_execution_event_id::text
      and v_exec.action_result->>'verificationId'
          is not distinct from v_layer82.verification_id::text
      and v_exec.action_result->>'reconciliationState'
          is not distinct from v_layer82.reconciliation_state
      and v_exec.action_result->>'reasonCode'
          is not distinct from v_layer82.reason_code
      and v_exec.action_result->>'verificationState'
          is not distinct from v_layer82.verification_state
      and v_exec.action_result->>'reconciliationProofSha256'
          is not distinct from v_layer82.reconciliation_proof_sha256
      and v_exec.action_result->'verificationRerunPerformed'='false'::jsonb
      and coalesce(v_exec.action_result->'evidenceMutationPerformed','false'::jsonb)
          ='false'::jsonb
      and coalesce(v_exec.action_result->'verificationProofRewritePerformed','false'::jsonb)
          ='false'::jsonb
      and coalesce(v_exec.action_result->'releaseTruthMutationPerformed','false'::jsonb)
          ='false'::jsonb
      and coalesce(v_exec.action_result->'incidentHistoryMutationPerformed','false'::jsonb)
          ='false'::jsonb
      and v_exec.action_result->'mutationPerformed'='false'::jsonb;

    v_layer82_snapshot := jsonb_build_object(
      'reconciliationId',v_layer82.reconciliation_id,
      'executorEventId',v_layer82.executor_event_id,
      'targetExecutionEventId',v_layer82.target_execution_event_id,
      'verificationId',v_layer82.verification_id,
      'verificationState',v_layer82.verification_state,
      'reconciliationState',v_layer82.reconciliation_state,
      'reasonCode',v_layer82.reason_code,
      'proofIntegrityValid',v_layer82.proof_integrity_valid,
      'receiptMatchesProof',v_layer82.receipt_matches_proof,
      'currentEvaluationMatches',v_layer82.current_evaluation_matches,
      'coverageTargetVisible',v_layer82.coverage_target_visible,
      'coverageTargetMatches',v_layer82.coverage_target_matches,
      'reconciliationProofSha256',v_layer82.reconciliation_proof_sha256,
      'reconciledAt',v_layer82.reconciled_at
    );
  end if;

  if v_layer82.reconciliation_id is null then
    v_state := 'missing-layer82-receipt';
    v_reason := 'case-audit-reconcile-exec-layer82-receipt-missing';
  elsif coalesce(v_layer82_integrity,false)=false then
    v_state := 'invalid-layer82-receipt';
    v_reason := 'case-audit-reconcile-exec-layer82-receipt-invalid';
  elsif not v_policy_integrity then
    v_state := 'policy-drift';
    v_reason := 'case-audit-reconcile-exec-policy-drift';
  elsif not v_incident_binding then
    v_state := 'incident-drift';
    v_reason := 'case-audit-reconcile-exec-incident-drift';
  elsif coalesce(v_execution_match,false)=false then
    v_state := 'execution-receipt-mismatch';
    v_reason := 'case-audit-reconcile-exec-receipt-mismatch';
  elsif not v_before_valid or not v_after_valid then
    v_state := 'coverage-drift';
    v_reason := 'case-audit-reconcile-exec-coverage-drift';
  else
    v_state := 'reconciled';
    v_reason := 'case-audit-reconcile-exec-complete';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionOutcome',
      'shine-foundation/case-audit-reconciliation-execution-outcome-v1',
    'schemaVersion','1.0.0',
    'status','evaluated',
    'layer86EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetExecutorEventId',v_exec.target_executor_event_id,
    'reconciliationIncidentEventId',v_exec.reconciliation_incident_event_id,
    'layer82ReconciliationId',v_layer82.reconciliation_id,
    'layer82ReconciliationState',v_layer82.reconciliation_state,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'policyIntegrityValid',v_policy_integrity,
    'incidentBindingValid',v_incident_binding,
    'layer82ProofIntegrityValid',v_layer82_integrity,
    'executionReceiptMatches',v_execution_match,
    'beforeCoverageValid',v_before_valid,
    'afterCoverageValid',v_after_valid,
    'layer86ActionResult',v_exec.action_result,
    'layer82Receipt',v_layer82_snapshot,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$layer87_evaluate$;

revoke all on function foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
  uuid,timestamptz
) to foundation_runtime,service_role;


create or replace function foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
  p_layer86_event_id uuid,
  p_reconciled_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer87_reconcile$
declare
  v_exec foundation.case_audit_verify_reconcile_exec_events%rowtype;
  v_existing foundation.case_audit_verify_reconcile_exec_reconciliations%rowtype;
  v_eval jsonb;
  v_proof jsonb;
  v_proof_hash text;
  v_reconciliation_id uuid;
  v_layer82_id uuid;
begin
  if p_layer86_event_id is null then
    raise exception 'case-audit-reconcile-exec-event-id-required';
  end if;

  if p_reconciled_at is null
     or p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes' then
    raise exception 'case-audit-reconcile-exec-time-invalid';
  end if;

  select * into v_exec
  from foundation.case_audit_verify_reconcile_exec_events
  where event_id=p_layer86_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionReconciliation',
        'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'layer86EventId',p_layer86_event_id,
      'reasonCode','case-audit-reconcile-exec-event-not-found',
      'layer82RerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionReconciliation',
        'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'layer86EventId',v_exec.event_id,
      'sourceEventType',v_exec.event_type,
      'reasonCode','case-audit-reconcile-exec-source-not-executed',
      'layer82RerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  select * into v_existing
  from foundation.case_audit_verify_reconcile_exec_reconciliations
  where layer86_event_id=v_exec.event_id;

  if v_existing.reconciliation_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionReconciliation',
        'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'reconciliationId',v_existing.reconciliation_id,
      'layer86EventId',v_existing.layer86_event_id,
      'targetExecutorEventId',v_existing.target_executor_event_id,
      'layer82ReconciliationId',v_existing.layer82_reconciliation_id,
      'reconciliationState',v_existing.reconciliation_state,
      'reasonCode',v_existing.reason_code,
      'reconciliationProofSha256',v_existing.reconciliation_proof_sha256,
      'layer82RerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  v_eval :=
    foundation.evaluate_case_audit_verify_reconcile_exec_outcome_v1(
      v_exec.event_id,p_reconciled_at
    );

  if v_eval->>'status'<>'evaluated'
     or v_eval->>'reconciliationState' not in (
       'reconciled',
       'missing-layer82-receipt',
       'invalid-layer82-receipt',
       'execution-receipt-mismatch',
       'policy-drift',
       'incident-drift',
       'coverage-drift'
     ) then
    raise exception 'case-audit-reconcile-exec-evaluation-invalid';
  end if;

  begin
    v_layer82_id := nullif(v_eval->>'layer82ReconciliationId','')::uuid;
  exception when invalid_text_representation then
    v_layer82_id := null;
  end;

  v_reconciliation_id := gen_random_uuid();

  v_proof := jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionReconciliationProof',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-proof-v1',
    'schemaVersion','1.0.0',
    'reconciliationId',v_reconciliation_id,
    'layer86EventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetExecutorEventId',v_exec.target_executor_event_id,
    'layer82ReconciliationId',v_layer82_id,
    'reconciliationState',v_eval->>'reconciliationState',
    'reasonCode',v_eval->>'reasonCode',
    'policyIntegrityValid',v_eval->'policyIntegrityValid',
    'incidentBindingValid',v_eval->'incidentBindingValid',
    'layer82ProofIntegrityValid',v_eval->'layer82ProofIntegrityValid',
    'executionReceiptMatches',v_eval->'executionReceiptMatches',
    'beforeCoverageValid',v_eval->'beforeCoverageValid',
    'afterCoverageValid',v_eval->'afterCoverageValid',
    'layer86ActionResult',v_eval->'layer86ActionResult',
    'layer82Receipt',v_eval->'layer82Receipt',
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'mutationPerformed',false,
    'reconciledAt',p_reconciled_at
  );

  v_proof_hash := encode(
    extensions.digest(convert_to(v_proof::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.case_audit_verify_reconcile_exec_reconciliations(
    reconciliation_id,layer86_event_id,environment,target_executor_event_id,
    layer82_reconciliation_id,reconciliation_state,reason_code,
    policy_integrity_valid,incident_binding_valid,
    layer82_proof_integrity_valid,execution_receipt_matches,
    before_coverage_valid,after_coverage_valid,layer86_snapshot,
    layer82_snapshot,reconciliation_proof,reconciliation_proof_sha256,
    reconciled_at
  )
  values(
    v_reconciliation_id,v_exec.event_id,v_exec.environment,
    v_exec.target_executor_event_id,v_layer82_id,
    v_eval->>'reconciliationState',v_eval->>'reasonCode',
    coalesce((v_eval->>'policyIntegrityValid')::boolean,false),
    coalesce((v_eval->>'incidentBindingValid')::boolean,false),
    case
      when v_eval->'layer82ProofIntegrityValid' is null then null
      else (v_eval->>'layer82ProofIntegrityValid')::boolean
    end,
    case
      when v_eval->'executionReceiptMatches' is null then null
      else (v_eval->>'executionReceiptMatches')::boolean
    end,
    coalesce((v_eval->>'beforeCoverageValid')::boolean,false),
    coalesce((v_eval->>'afterCoverageValid')::boolean,false),
    jsonb_build_object(
      'layer86EventId',v_exec.event_id,
      'targetExecutorEventId',v_exec.target_executor_event_id,
      'reconciliationIncidentEventId',v_exec.reconciliation_incident_event_id,
      'actionKey',v_exec.action_key,
      'causeClass',v_exec.cause_class,
      'policyFingerprint',v_exec.policy_fingerprint,
      'eventType',v_exec.event_type,
      'reasonCode',v_exec.reason_code,
      'requestedAt',v_exec.requested_at
    ),
    nullif(v_eval->'layer82Receipt','null'::jsonb),
    v_proof,v_proof_hash,p_reconciled_at
  );

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionReconciliation',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'reconciliationId',v_reconciliation_id,
    'layer86EventId',v_exec.event_id,
    'targetExecutorEventId',v_exec.target_executor_event_id,
    'layer82ReconciliationId',v_layer82_id,
    'reconciliationState',v_eval->>'reconciliationState',
    'reasonCode',v_eval->>'reasonCode',
    'reconciliationProofSha256',v_proof_hash,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'mutationPerformed',false
  );
end;
$layer87_reconcile$;

revoke all on function foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1(
  uuid,timestamptz
) to service_role;


create or replace function foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer87_summary$
declare
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_reconciled integer := 0;
  v_missing integer := 0;
  v_invalid integer := 0;
  v_receipt_mismatch integer := 0;
  v_policy_drift integer := 0;
  v_incident_drift integer := 0;
  v_coverage_drift integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_limit is null
     or p_limit<1
     or p_limit>100 then
    raise exception 'case-audit-reconcile-exec-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter (where reconciliation_state='reconciled'),
    count(*) filter (where reconciliation_state='missing-layer82-receipt'),
    count(*) filter (where reconciliation_state='invalid-layer82-receipt'),
    count(*) filter (where reconciliation_state='execution-receipt-mismatch'),
    count(*) filter (where reconciliation_state='policy-drift'),
    count(*) filter (where reconciliation_state='incident-drift'),
    count(*) filter (where reconciliation_state='coverage-drift')
  into
    v_total,v_reconciled,v_missing,v_invalid,v_receipt_mismatch,
    v_policy_drift,v_incident_drift,v_coverage_drift
  from foundation.case_audit_verify_reconcile_exec_reconciliations
  where environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reconciliationId',x.reconciliation_id,
        'layer86EventId',x.layer86_event_id,
        'targetExecutorEventId',x.target_executor_event_id,
        'layer82ReconciliationId',x.layer82_reconciliation_id,
        'reconciliationState',x.reconciliation_state,
        'reasonCode',x.reason_code,
        'policyIntegrityValid',x.policy_integrity_valid,
        'incidentBindingValid',x.incident_binding_valid,
        'layer82ProofIntegrityValid',x.layer82_proof_integrity_valid,
        'executionReceiptMatches',x.execution_receipt_matches,
        'beforeCoverageValid',x.before_coverage_valid,
        'afterCoverageValid',x.after_coverage_valid,
        'reconciliationProofSha256',x.reconciliation_proof_sha256,
        'reconciledAt',x.reconciled_at
      )
      order by x.reconciliation_sequence desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select *
    from foundation.case_audit_verify_reconcile_exec_reconciliations
    where environment=p_environment
    order by reconciliation_sequence desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionReconciliationSummary',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'totalCount',v_total,
    'reconciledCount',v_reconciled,
    'missingLayer82ReceiptCount',v_missing,
    'invalidLayer82ReceiptCount',v_invalid,
    'executionReceiptMismatchCount',v_receipt_mismatch,
    'policyDriftCount',v_policy_drift,
    'incidentDriftCount',v_incident_drift,
    'coverageDriftCount',v_coverage_drift,
    'problemCount',
      v_missing+v_invalid+v_receipt_mismatch+
      v_policy_drift+v_incident_drift+v_coverage_drift,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$layer87_summary$;

revoke all on function foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_reconcile_exec_reconciliation_summary_v1(
  text,integer
) to foundation_runtime,service_role;
