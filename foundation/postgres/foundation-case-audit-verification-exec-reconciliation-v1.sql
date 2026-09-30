-- Foundation Layer 82: independent reconciliation for Layer-81 execution receipts.
-- Layer 81 may claim that it invoked Layer 77 for one overdue target.
-- Layer 82 never trusts that receipt by itself. It re-reads the durable Layer-77
-- proof, recomputes proof integrity, re-evaluates the original Layer-76 evidence,
-- and compares current Layer-78 coverage before recording immutable reconciliation.

create table foundation.case_audit_verify_exec_reconciliations (
  reconciliation_sequence bigint generated always as identity primary key,
  reconciliation_id uuid not null unique default gen_random_uuid(),
  executor_event_id uuid not null unique
    references foundation.case_audit_verify_exec_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_execution_event_id uuid not null
    references foundation.case_audit_safe_response_exec_events(event_id),
  verification_id uuid
    references foundation.case_audit_safe_response_verifications(verification_id),
  reconciliation_state text not null
    check (
      reconciliation_state in (
        'reconciled',
        'missing-proof',
        'receipt-mismatch',
        'invalid-proof',
        'evidence-drift',
        'coverage-drift'
      )
    ),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  verification_state text
    check (
      verification_state is null
      or verification_state in ('verified','missing','mismatch')
    ),
  proof_integrity_valid boolean,
  receipt_matches_proof boolean,
  current_evaluation_matches boolean,
  coverage_target_visible boolean not null,
  coverage_target_matches boolean,
  verification_snapshot jsonb
    check (
      verification_snapshot is null
      or jsonb_typeof(verification_snapshot)='object'
    ),
  current_evaluation jsonb
    check (
      current_evaluation is null
      or jsonb_typeof(current_evaluation)='object'
    ),
  current_coverage jsonb not null
    check (jsonb_typeof(current_coverage)='object'),
  layer81_action_result jsonb not null
    check (jsonb_typeof(layer81_action_result)='object'),
  reconciliation_proof jsonb not null
    check (jsonb_typeof(reconciliation_proof)='object'),
  reconciliation_proof_sha256 text not null
    check (reconciliation_proof_sha256 ~ '^[a-f0-9]{64}$'),
  reconciled_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_verify_exec_reconciliations
  enable row level security;

create policy foundation_runtime_case_audit_verify_reconcile_select
on foundation.case_audit_verify_exec_reconciliations
for select
to foundation_runtime
using (true);

revoke all on foundation.case_audit_verify_exec_reconciliations
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_verify_exec_reconciliations
  to foundation_runtime,service_role;

create index case_audit_verify_reconcile_target_idx
  on foundation.case_audit_verify_exec_reconciliations(
    target_execution_event_id,reconciled_at desc,reconciliation_sequence desc
  );

create index case_audit_verify_reconcile_state_idx
  on foundation.case_audit_verify_exec_reconciliations(
    reconciliation_state,reconciled_at desc,reconciliation_sequence desc
  );

create trigger case_audit_verify_reconcile_append_only
before update or delete
on foundation.case_audit_verify_exec_reconciliations
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.evaluate_case_audit_verify_exec_outcome_v1(
  p_executor_event_id uuid,
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer82_evaluate$
declare
  v_exec foundation.case_audit_verify_exec_events%rowtype;
  v_target foundation.case_audit_safe_response_exec_events%rowtype;
  v_verification foundation.case_audit_safe_response_verifications%rowtype;
  v_current_eval jsonb;
  v_coverage jsonb;
  v_coverage_item jsonb;
  v_recomputed_proof_hash text;
  v_proof_integrity boolean := false;
  v_receipt_match boolean := false;
  v_current_eval_match boolean := false;
  v_coverage_target_visible boolean := false;
  v_coverage_target_match boolean := false;
  v_expected_coverage_state text;
  v_state text;
  v_reason text;
  v_verification_snapshot jsonb;
begin
  if p_executor_event_id is null then
    raise exception 'case-audit-verify-exec-reconcile-event-id-required';
  end if;

  if p_as_of is null
     or p_verification_grace_seconds is null
     or p_verification_grace_seconds<60
     or p_verification_grace_seconds>3600 then
    raise exception 'case-audit-verify-exec-reconcile-input-invalid';
  end if;

  select * into v_exec
  from foundation.case_audit_verify_exec_events
  where event_id=p_executor_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditVerificationExecutionOutcome',
        'shine-foundation/case-audit-verification-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-found',
      'executorEventId',p_executor_event_id,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-verify-exec-reconcile-event-not-found',
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditVerificationExecutionOutcome',
        'shine-foundation/case-audit-verification-execution-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executorEventId',v_exec.event_id,
      'targetExecutionEventId',v_exec.target_execution_event_id,
      'environment',v_exec.environment,
      'sourceExecutorEventType',v_exec.event_type,
      'reconciliationState','not-applicable',
      'reasonCode','case-audit-verify-exec-reconcile-source-not-executed',
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  select * into v_target
  from foundation.case_audit_safe_response_exec_events
  where event_id=v_exec.target_execution_event_id
    and environment=v_exec.environment;

  select * into v_verification
  from foundation.case_audit_safe_response_verifications
  where execution_event_id=v_exec.target_execution_event_id;

  v_coverage :=
    foundation.get_case_audit_safe_response_verification_coverage_v1(
      v_exec.environment,p_as_of,p_verification_grace_seconds,100
    );

  if v_target.event_id is null then
    v_state := 'receipt-mismatch';
    v_reason := 'case-audit-verify-exec-reconcile-target-missing';

  elsif v_verification.verification_id is null then
    v_state := 'missing-proof';
    v_reason := 'case-audit-verify-exec-reconcile-proof-missing';

  else
    v_recomputed_proof_hash := encode(
      extensions.digest(
        convert_to(v_verification.verification_proof::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    v_proof_integrity :=
      v_recomputed_proof_hash
        is not distinct from v_verification.verification_proof_sha256
      and v_verification.execution_action_result
        is not distinct from v_target.action_result
      and v_verification.verification_proof->>
            'foundationCaseAuditSafeResponseVerificationProof'
        is not distinct from
            'shine-foundation/case-audit-safe-response-verification-proof-v1'
      and v_verification.verification_proof->>'schemaVersion'
        is not distinct from '1.0.0'
      and v_verification.verification_proof->>'executionEventId'
        is not distinct from v_target.event_id::text
      and v_verification.verification_proof->>'environment'
        is not distinct from v_target.environment
      and v_verification.verification_proof->>'incidentEventId'
        is not distinct from v_target.incident_event_id::text
      and v_verification.verification_proof->>'actionKey'
        is not distinct from v_target.action_key
      and v_verification.verification_proof->>'executionPolicyFingerprint'
        is not distinct from v_target.policy_fingerprint
      and v_verification.verification_proof->'executionRequestedAt'
        is not distinct from to_jsonb(v_target.requested_at)
      and v_verification.verification_proof->>'verificationState'
        is not distinct from v_verification.verification_state
      and v_verification.verification_proof->>'reasonCode'
        is not distinct from v_verification.reason_code
      and v_verification.verification_proof->>'durableEvidenceId'
        is not distinct from v_verification.durable_evidence_id::text
      and v_verification.verification_proof->>'durableEvidenceFingerprint'
        is not distinct from v_verification.durable_evidence_fingerprint
      and nullif(
            v_verification.verification_proof->'durableEvidence',
            'null'::jsonb
          ) is not distinct from v_verification.durable_evidence_snapshot
      and v_verification.verification_proof->'executionActionResult'
        is not distinct from v_target.action_result
      and v_verification.verification_proof->'verifiedAt'
        is not distinct from to_jsonb(v_verification.verified_at)
      and v_verification.verification_proof->'independentDurableEvidenceRead'
        = 'true'::jsonb
      and v_verification.verification_proof->'targetReexecuted'
        = 'false'::jsonb
      and v_verification.verification_proof->'historyRewritePerformed'
        = 'false'::jsonb
      and v_verification.verification_proof->'releaseTruthMutationPerformed'
        = 'false'::jsonb
      and v_verification.verification_proof->'incidentHistoryMutationPerformed'
        = 'false'::jsonb
      and v_verification.verification_proof->'approvalGranted'
        = 'false'::jsonb
      and v_verification.verification_proof->'executionAuthorityGranted'
        = 'false'::jsonb
      and v_verification.verification_proof->'mutationPerformed'
        = 'false'::jsonb;

    v_receipt_match :=
      v_exec.action_key='run-independent-verification'
      and v_exec.reason_code='case-audit-overdue-verification-layer77-ran'
      and foundation.case_audit_verify_exec_policy_fp_v1(
            v_exec.decision_snapshot,
            v_exec.incident_snapshot,
            v_exec.target_snapshot
          ) is not distinct from v_exec.policy_fingerprint
      and v_exec.target_snapshot->>'executionEventId'
        is not distinct from v_target.event_id::text
      and v_exec.target_snapshot->>'incidentEventId'
        is not distinct from v_target.incident_event_id::text
      and v_exec.target_snapshot->>'actionKey'
        is not distinct from v_target.action_key
      and v_exec.target_snapshot->>'executionPolicyFingerprint'
        is not distinct from v_target.policy_fingerprint
      and v_exec.target_snapshot->'executionRequestedAt'
        is not distinct from to_jsonb(v_target.requested_at)
      and v_exec.decision_snapshot->>'decision'='admit'
      and v_exec.decision_snapshot->>'requiredControl'
        ='layer-77-bounded-verifier'
      and v_exec.decision_snapshot->>'causeClass'='verification-omission'
      and v_exec.decision_snapshot->'authorityExpansion'='false'::jsonb
      and v_exec.decision_snapshot->'automaticVerificationAllowed'='false'::jsonb
      and v_exec.decision_snapshot->'automaticRepairAllowed'='false'::jsonb
      and v_exec.decision_snapshot->'verificationProofRewriteAllowed'='false'::jsonb
      and v_exec.decision_snapshot->'historyRewriteAllowed'='false'::jsonb
      and v_exec.decision_snapshot->'executesAction'='false'::jsonb
      and v_exec.decision_snapshot->'rerunsSafeResponse'='false'::jsonb
      and v_exec.decision_snapshot->'mutatesVerificationProof'='false'::jsonb
      and v_exec.decision_snapshot->'mutatesAuthoritativeTruth'='false'::jsonb
      and v_exec.decision_snapshot->'mutatesIncidentHistory'='false'::jsonb
      and v_exec.before_coverage->>
            'foundationCaseAuditSafeResponseVerificationCoverage'
        ='shine-foundation/case-audit-safe-response-verification-coverage-v1'
      and v_exec.after_coverage->>
            'foundationCaseAuditSafeResponseVerificationCoverage'
        ='shine-foundation/case-audit-safe-response-verification-coverage-v1'
      and v_exec.action_result->>
          'foundationCaseAuditSafeResponseVerification'
        is not distinct from
          'shine-foundation/case-audit-safe-response-verification-response-v1'
      and v_exec.action_result->>'schemaVersion'
        is not distinct from '1.0.0'
      and v_exec.action_result->>'status' in ('recorded','existing')
      and v_exec.action_result->>'verificationId'
        is not distinct from v_verification.verification_id::text
      and v_exec.action_result->>'executionEventId'
        is not distinct from v_target.event_id::text
      and v_exec.action_result->>'verificationState'
        is not distinct from v_verification.verification_state
      and v_exec.action_result->>'reasonCode'
        is not distinct from v_verification.reason_code
      and v_exec.action_result->>'durableEvidenceId'
        is not distinct from v_verification.durable_evidence_id::text
      and v_exec.action_result->>'durableEvidenceFingerprint'
        is not distinct from v_verification.durable_evidence_fingerprint
      and v_exec.action_result->>'verificationProofSha256'
        is not distinct from v_verification.verification_proof_sha256
      and v_exec.action_result->'targetReexecuted'='false'::jsonb
      and v_exec.action_result->'mutationPerformed'='false'::jsonb;

    v_current_eval :=
      foundation.evaluate_case_audit_safe_response_execution_v1(
        v_target.event_id
      );

    v_current_eval_match :=
      v_current_eval->>'status'='evaluated'
      and v_current_eval->>'verificationState'
        is not distinct from v_verification.verification_state
      and v_current_eval->>'reasonCode'
        is not distinct from v_verification.reason_code
      and v_current_eval->>'durableEvidenceId'
        is not distinct from v_verification.durable_evidence_id::text
      and v_current_eval->>'durableEvidenceFingerprint'
        is not distinct from v_verification.durable_evidence_fingerprint
      and v_current_eval->'targetReexecuted'='false'::jsonb
      and v_current_eval->'mutationPerformed'='false'::jsonb;

    v_expected_coverage_state := case
      when not v_proof_integrity then 'invalid'
      else v_verification.verification_state
    end;

    select item into v_coverage_item
    from jsonb_array_elements(
      coalesce(v_coverage->'items','[]'::jsonb)
    ) item
    where item->>'executionEventId'=v_target.event_id::text
    limit 1;

    v_coverage_target_visible := v_coverage_item is not null;

    if v_coverage_target_visible then
      v_coverage_target_match :=
        v_coverage_item->>'coverageState'
          is not distinct from v_expected_coverage_state
        and v_coverage_item->>'verificationId'
          is not distinct from v_verification.verification_id::text
        and v_coverage_item->>'verificationState'
          is not distinct from v_verification.verification_state
        and v_coverage_item->>'proofIntegrityVerified'
          is not distinct from v_proof_integrity::text;
    end if;

    if not v_proof_integrity then
      v_state := 'invalid-proof';
      v_reason := 'case-audit-verify-exec-reconcile-proof-invalid';

    elsif not v_receipt_match then
      v_state := 'receipt-mismatch';
      v_reason := 'case-audit-verify-exec-reconcile-receipt-mismatch';

    elsif not v_current_eval_match then
      v_state := 'evidence-drift';
      v_reason := 'case-audit-verify-exec-reconcile-evidence-drift';

    elsif v_coverage_target_visible and not v_coverage_target_match then
      v_state := 'coverage-drift';
      v_reason := 'case-audit-verify-exec-reconcile-coverage-drift';

    else
      v_state := 'reconciled';
      v_reason := 'case-audit-verify-exec-reconcile-complete';
    end if;

    v_verification_snapshot := jsonb_build_object(
      'verificationId',v_verification.verification_id,
      'executionEventId',v_verification.execution_event_id,
      'environment',v_verification.environment,
      'incidentEventId',v_verification.incident_event_id,
      'actionKey',v_verification.action_key,
      'executionPolicyFingerprint',
        v_verification.execution_policy_fingerprint,
      'verificationState',v_verification.verification_state,
      'reasonCode',v_verification.reason_code,
      'durableEvidenceId',v_verification.durable_evidence_id,
      'durableEvidenceFingerprint',
        v_verification.durable_evidence_fingerprint,
      'verificationProofSha256',
        v_verification.verification_proof_sha256,
      'verifiedAt',v_verification.verified_at
    );
  end if;

  return jsonb_build_object(
    'foundationCaseAuditVerificationExecutionOutcome',
      'shine-foundation/case-audit-verification-execution-outcome-v1',
    'schemaVersion','1.0.0',
    'status','evaluated',
    'executorEventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetExecutionEventId',v_exec.target_execution_event_id,
    'verificationIncidentEventId',v_exec.verification_incident_event_id,
    'reconciliationState',v_state,
    'reasonCode',v_reason,
    'verificationId',v_verification.verification_id,
    'verificationState',v_verification.verification_state,
    'proofIntegrityValid',case
      when v_verification.verification_id is null then null
      else v_proof_integrity
    end,
    'receiptMatchesProof',case
      when v_verification.verification_id is null then null
      else v_receipt_match
    end,
    'currentEvaluationMatches',case
      when v_verification.verification_id is null then null
      else v_current_eval_match
    end,
    'coverageTargetVisible',v_coverage_target_visible,
    'coverageTargetMatches',case
      when v_coverage_target_visible then v_coverage_target_match
      else null
    end,
    'verification',v_verification_snapshot,
    'currentEvaluation',v_current_eval,
    'currentCoverage',v_coverage,
    'layer81ActionResult',v_exec.action_result,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false
  );
end;
$layer82_evaluate$;

revoke all on function foundation.evaluate_case_audit_verify_exec_outcome_v1(
  uuid,timestamptz,integer
) from public,anon,authenticated,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_verify_exec_outcome_v1(
  uuid,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.run_case_audit_verify_exec_reconciliation_v1(
  p_executor_event_id uuid,
  p_reconciled_at timestamptz default now(),
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer82_reconcile$
declare
  v_exec foundation.case_audit_verify_exec_events%rowtype;
  v_existing foundation.case_audit_verify_exec_reconciliations%rowtype;
  v_eval jsonb;
  v_proof jsonb;
  v_proof_hash text;
  v_reconciliation_id uuid;
  v_verification_id uuid;
begin
  if p_executor_event_id is null then
    raise exception 'case-audit-verify-exec-reconcile-event-id-required';
  end if;

  if p_reconciled_at is null
     or p_reconciled_at<now()-interval '5 minutes'
     or p_reconciled_at>now()+interval '5 minutes'
     or p_verification_grace_seconds is null
     or p_verification_grace_seconds<60
     or p_verification_grace_seconds>3600 then
    raise exception 'case-audit-verify-exec-reconcile-input-invalid';
  end if;

  select * into v_exec
  from foundation.case_audit_verify_exec_events
  where event_id=p_executor_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditVerificationExecutionReconciliation',
        'shine-foundation/case-audit-verification-execution-reconciliation-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executorEventId',p_executor_event_id,
      'reasonCode','case-audit-verify-exec-reconcile-event-not-found',
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditVerificationExecutionReconciliation',
        'shine-foundation/case-audit-verification-execution-reconciliation-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executorEventId',v_exec.event_id,
      'sourceExecutorEventType',v_exec.event_type,
      'reasonCode','case-audit-verify-exec-reconcile-source-not-executed',
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  select * into v_existing
  from foundation.case_audit_verify_exec_reconciliations
  where executor_event_id=v_exec.event_id;

  if v_existing.reconciliation_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditVerificationExecutionReconciliation',
        'shine-foundation/case-audit-verification-execution-reconciliation-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'reconciliationId',v_existing.reconciliation_id,
      'executorEventId',v_existing.executor_event_id,
      'targetExecutionEventId',v_existing.target_execution_event_id,
      'verificationId',v_existing.verification_id,
      'reconciliationState',v_existing.reconciliation_state,
      'reasonCode',v_existing.reason_code,
      'verificationState',v_existing.verification_state,
      'reconciliationProofSha256',
        v_existing.reconciliation_proof_sha256,
      'verificationRerunPerformed',false,
      'mutationPerformed',false
    );
  end if;

  v_eval :=
    foundation.evaluate_case_audit_verify_exec_outcome_v1(
      v_exec.event_id,p_reconciled_at,p_verification_grace_seconds
    );

  if v_eval->>'status'<>'evaluated'
     or v_eval->>'reconciliationState' not in (
       'reconciled',
       'missing-proof',
       'receipt-mismatch',
       'invalid-proof',
       'evidence-drift',
       'coverage-drift'
     ) then
    raise exception 'case-audit-verify-exec-reconcile-evaluation-invalid';
  end if;

  begin
    v_verification_id :=
      nullif(v_eval->>'verificationId','')::uuid;
  exception when invalid_text_representation then
    v_verification_id := null;
  end;

  v_proof := jsonb_build_object(
    'foundationCaseAuditVerificationExecutionReconciliationProof',
      'shine-foundation/case-audit-verification-execution-reconciliation-proof-v1',
    'schemaVersion','1.0.0',
    'reconciliationId',null,
    'executorEventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetExecutionEventId',v_exec.target_execution_event_id,
    'verificationIncidentEventId',v_exec.verification_incident_event_id,
    'verificationId',v_verification_id,
    'verificationState',nullif(v_eval->>'verificationState',''),
    'reconciliationState',v_eval->>'reconciliationState',
    'reasonCode',v_eval->>'reasonCode',
    'proofIntegrityValid',v_eval->'proofIntegrityValid',
    'receiptMatchesProof',v_eval->'receiptMatchesProof',
    'currentEvaluationMatches',v_eval->'currentEvaluationMatches',
    'coverageTargetVisible',v_eval->'coverageTargetVisible',
    'coverageTargetMatches',v_eval->'coverageTargetMatches',
    'verification',v_eval->'verification',
    'currentEvaluation',v_eval->'currentEvaluation',
    'currentCoverage',v_eval->'currentCoverage',
    'layer81ActionResult',v_exec.action_result,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'mutationPerformed',false,
    'reconciledAt',p_reconciled_at
  );

  v_reconciliation_id := gen_random_uuid();

  v_proof := jsonb_set(
    v_proof,
    '{reconciliationId}',
    to_jsonb(v_reconciliation_id)
  );

  v_proof_hash := encode(
    extensions.digest(
      convert_to(v_proof::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.case_audit_verify_exec_reconciliations(
    reconciliation_id,
    executor_event_id,
    environment,
    target_execution_event_id,
    verification_id,
    reconciliation_state,
    reason_code,
    verification_state,
    proof_integrity_valid,
    receipt_matches_proof,
    current_evaluation_matches,
    coverage_target_visible,
    coverage_target_matches,
    verification_snapshot,
    current_evaluation,
    current_coverage,
    layer81_action_result,
    reconciliation_proof,
    reconciliation_proof_sha256,
    reconciled_at
  )
  values(
    v_reconciliation_id,
    v_exec.event_id,
    v_exec.environment,
    v_exec.target_execution_event_id,
    v_verification_id,
    v_eval->>'reconciliationState',
    v_eval->>'reasonCode',
    nullif(v_eval->>'verificationState',''),
    case
      when v_eval->'proofIntegrityValid' is null then null
      else (v_eval->>'proofIntegrityValid')::boolean
    end,
    case
      when v_eval->'receiptMatchesProof' is null then null
      else (v_eval->>'receiptMatchesProof')::boolean
    end,
    case
      when v_eval->'currentEvaluationMatches' is null then null
      else (v_eval->>'currentEvaluationMatches')::boolean
    end,
    coalesce((v_eval->>'coverageTargetVisible')::boolean,false),
    case
      when v_eval->'coverageTargetMatches' is null then null
      else (v_eval->>'coverageTargetMatches')::boolean
    end,
    nullif(v_eval->'verification','null'::jsonb),
    nullif(v_eval->'currentEvaluation','null'::jsonb),
    v_eval->'currentCoverage',
    v_exec.action_result,
    v_proof,
    v_proof_hash,
    p_reconciled_at
  );

  return jsonb_build_object(
    'foundationCaseAuditVerificationExecutionReconciliation',
      'shine-foundation/case-audit-verification-execution-reconciliation-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'reconciliationId',v_reconciliation_id,
    'executorEventId',v_exec.event_id,
    'targetExecutionEventId',v_exec.target_execution_event_id,
    'verificationId',v_verification_id,
    'reconciliationState',v_eval->>'reconciliationState',
    'reasonCode',v_eval->>'reasonCode',
    'verificationState',nullif(v_eval->>'verificationState',''),
    'reconciliationProofSha256',v_proof_hash,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$layer82_reconcile$;

revoke all on function foundation.run_case_audit_verify_exec_reconciliation_v1(
  uuid,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_case_audit_verify_exec_reconciliation_v1(
  uuid,timestamptz,integer
) to service_role;


create or replace function foundation.get_case_audit_verify_reconcile_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer82_summary$
declare
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_reconciled integer := 0;
  v_missing integer := 0;
  v_receipt_mismatch integer := 0;
  v_invalid integer := 0;
  v_evidence_drift integer := 0;
  v_coverage_drift integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_limit is null
     or p_limit<1
     or p_limit>100 then
    raise exception 'case-audit-verify-reconcile-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter (where reconciliation_state='reconciled'),
    count(*) filter (where reconciliation_state='missing-proof'),
    count(*) filter (where reconciliation_state='receipt-mismatch'),
    count(*) filter (where reconciliation_state='invalid-proof'),
    count(*) filter (where reconciliation_state='evidence-drift'),
    count(*) filter (where reconciliation_state='coverage-drift')
  into
    v_total,v_reconciled,v_missing,v_receipt_mismatch,v_invalid,
    v_evidence_drift,v_coverage_drift
  from foundation.case_audit_verify_exec_reconciliations
  where environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'reconciliationId',x.reconciliation_id,
        'executorEventId',x.executor_event_id,
        'targetExecutionEventId',x.target_execution_event_id,
        'verificationId',x.verification_id,
        'reconciliationState',x.reconciliation_state,
        'reasonCode',x.reason_code,
        'verificationState',x.verification_state,
        'proofIntegrityValid',x.proof_integrity_valid,
        'receiptMatchesProof',x.receipt_matches_proof,
        'currentEvaluationMatches',x.current_evaluation_matches,
        'coverageTargetVisible',x.coverage_target_visible,
        'coverageTargetMatches',x.coverage_target_matches,
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
    from foundation.case_audit_verify_exec_reconciliations
    where environment=p_environment
    order by reconciliation_sequence desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditVerificationExecutionReconciliationSummary',
      'shine-foundation/case-audit-verification-execution-reconciliation-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'totalCount',v_total,
    'reconciledCount',v_reconciled,
    'missingProofCount',v_missing,
    'receiptMismatchCount',v_receipt_mismatch,
    'invalidProofCount',v_invalid,
    'evidenceDriftCount',v_evidence_drift,
    'coverageDriftCount',v_coverage_drift,
    'problemCount',
      v_missing+v_receipt_mismatch+v_invalid+v_evidence_drift+v_coverage_drift,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$layer82_summary$;

revoke all on function foundation.get_case_audit_verify_reconcile_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_reconcile_summary_v1(
  text,integer
) to foundation_runtime,service_role;
