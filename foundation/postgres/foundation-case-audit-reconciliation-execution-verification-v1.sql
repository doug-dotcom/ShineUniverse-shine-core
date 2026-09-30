-- Foundation Layer 87: independent verification of Layer-86 reconciliation execution.
-- Layer 86 may claim that it invoked Layer 82 for one overdue Layer-81 event.
-- Layer 87 never trusts that claim by itself. It re-reads the durable Layer-82
-- receipt, independently validates its proof, recomputes the Layer-86 policy
-- envelope, and records immutable verification without rerunning any upstream work.

create table foundation.case_audit_verify_reconcile_exec_verifications (
  verification_sequence bigint generated always as identity primary key,
  verification_id uuid not null unique default gen_random_uuid(),
  reconcile_exec_event_id uuid not null unique
    references foundation.case_audit_verify_reconcile_exec_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_executor_event_id uuid not null
    references foundation.case_audit_verify_exec_events(event_id),
  reconciliation_id uuid
    references foundation.case_audit_verify_exec_reconciliations(reconciliation_id),
  verification_state text not null
    check (
      verification_state in (
        'verified',
        'missing-reconciliation',
        'policy-mismatch',
        'receipt-mismatch',
        'invalid-reconciliation-proof'
      )
    ),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  policy_integrity_valid boolean not null,
  target_snapshot_matches boolean not null,
  incident_snapshot_matches boolean not null,
  reconciliation_proof_integrity_valid boolean,
  receipt_matches_reconciliation boolean,
  layer86_snapshot jsonb not null
    check (jsonb_typeof(layer86_snapshot)='object'),
  layer82_snapshot jsonb
    check (
      layer82_snapshot is null
      or jsonb_typeof(layer82_snapshot)='object'
    ),
  verification_proof jsonb not null
    check (jsonb_typeof(verification_proof)='object'),
  verification_proof_sha256 text not null
    check (verification_proof_sha256 ~ '^[a-f0-9]{64}$'),
  verified_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_verify_reconcile_exec_verifications
  enable row level security;

create policy foundation_runtime_case_audit_reconcile_exec_verify_select
on foundation.case_audit_verify_reconcile_exec_verifications
for select
to foundation_runtime
using (true);

revoke all on foundation.case_audit_verify_reconcile_exec_verifications
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_verify_reconcile_exec_verifications
  to foundation_runtime,service_role;

create index case_audit_reconcile_exec_verify_target_idx
  on foundation.case_audit_verify_reconcile_exec_verifications(
    target_executor_event_id,verified_at desc,verification_sequence desc
  );

create index case_audit_reconcile_exec_verify_state_idx
  on foundation.case_audit_verify_reconcile_exec_verifications(
    verification_state,verified_at desc,verification_sequence desc
  );

create trigger case_audit_reconcile_exec_verify_append_only
before update or delete
on foundation.case_audit_verify_reconcile_exec_verifications
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.evaluate_case_audit_reconcile_exec_verification_v1(
  p_reconcile_exec_event_id uuid,
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
  v_incident foundation.case_audit_verify_reconcile_incident_events%rowtype;
  v_reconciliation foundation.case_audit_verify_exec_reconciliations%rowtype;
  v_policy_integrity boolean := false;
  v_target_match boolean := false;
  v_incident_match boolean := false;
  v_reconciliation_proof_integrity boolean := false;
  v_receipt_match boolean := false;
  v_recomputed_reconciliation_hash text;
  v_state text;
  v_reason text;
  v_layer86_snapshot jsonb;
  v_layer82_snapshot jsonb;
begin
  if p_reconcile_exec_event_id is null then
    raise exception 'case-audit-reconcile-exec-verify-event-id-required';
  end if;

  if p_as_of is null then
    raise exception 'case-audit-reconcile-exec-verify-input-invalid';
  end if;

  select * into v_exec
  from foundation.case_audit_verify_reconcile_exec_events
  where event_id=p_reconcile_exec_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionVerificationOutcome',
        'shine-foundation/case-audit-reconciliation-execution-verification-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-found',
      'reconcileExecEventId',p_reconcile_exec_event_id,
      'verificationState','not-applicable',
      'reasonCode','case-audit-reconcile-exec-verify-event-not-found',
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionVerificationOutcome',
        'shine-foundation/case-audit-reconciliation-execution-verification-outcome-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'reconcileExecEventId',v_exec.event_id,
      'targetExecutorEventId',v_exec.target_executor_event_id,
      'environment',v_exec.environment,
      'sourceExecutorEventType',v_exec.event_type,
      'verificationState','not-applicable',
      'reasonCode','case-audit-reconcile-exec-verify-source-not-executed',
      'layer82RerunPerformed',false,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  select * into v_target
  from foundation.case_audit_verify_exec_events
  where event_id=v_exec.target_executor_event_id
    and environment=v_exec.environment;

  if v_exec.reconciliation_incident_event_id is not null then
    select * into v_incident
    from foundation.case_audit_verify_reconcile_incident_events
    where event_id=v_exec.reconciliation_incident_event_id
      and environment=v_exec.environment;
  end if;

  select * into v_reconciliation
  from foundation.case_audit_verify_exec_reconciliations
  where executor_event_id=v_exec.target_executor_event_id;

  v_target_match :=
    v_target.event_id is not null
    and v_target.event_type='executed'
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
    and nullif(v_exec.target_snapshot->>'reconciliationId','') is null
    and nullif(v_exec.target_snapshot->>'reconciliationState','') is null;

  v_incident_match :=
    v_incident.event_id is not null
    and v_incident.event_type in ('detected','opened','changed')
    and v_incident.source_state in ('gap','invalid')
    and v_exec.incident_snapshot->>'state' in ('watching','critical')
    and v_exec.incident_snapshot#>>'{currentEvent,eventId}'
      is not distinct from v_incident.event_id::text
    and v_exec.incident_snapshot#>>'{currentEvent,eventType}'
      is not distinct from v_incident.event_type
    and v_exec.incident_snapshot#>>'{currentEvent,sourceState}'
      is not distinct from v_incident.source_state
    and v_exec.incident_snapshot#>>'{currentEvent,evidenceFingerprint}'
      is not distinct from v_incident.evidence_fingerprint;

  v_policy_integrity :=
    v_exec.action_key='run-independent-reconciliation'
    and v_exec.cause_class='reconciliation-omission'
    and v_exec.reason_code='case-audit-overdue-reconciliation-layer82-ran'
    and foundation.case_audit_verify_reconcile_exec_policy_fp_v1(
          v_exec.decision_snapshot,
          v_exec.incident_snapshot,
          v_exec.target_snapshot
        ) is not distinct from v_exec.policy_fingerprint
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
    and v_exec.decision_snapshot->>'actionClass'='evidence'
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
    and v_exec.before_coverage->>
          'foundationCaseAuditVerificationReconciliationCoverage'
      ='shine-foundation/case-audit-verification-reconciliation-coverage-v1'
    and v_exec.after_coverage->>
          'foundationCaseAuditVerificationReconciliationCoverage'
      ='shine-foundation/case-audit-verification-reconciliation-coverage-v1';

  if v_reconciliation.reconciliation_id is not null then
    v_recomputed_reconciliation_hash := encode(
      extensions.digest(
        convert_to(v_reconciliation.reconciliation_proof::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    v_reconciliation_proof_integrity :=
      v_recomputed_reconciliation_hash
        is not distinct from v_reconciliation.reconciliation_proof_sha256
      and v_reconciliation.reconciliation_proof->>
            'foundationCaseAuditVerificationExecutionReconciliationProof'
        is not distinct from
            'shine-foundation/case-audit-verification-execution-reconciliation-proof-v1'
      and v_reconciliation.reconciliation_proof->>'schemaVersion'
        is not distinct from '1.0.0'
      and v_reconciliation.reconciliation_proof->>'reconciliationId'
        is not distinct from v_reconciliation.reconciliation_id::text
      and v_reconciliation.reconciliation_proof->>'executorEventId'
        is not distinct from v_reconciliation.executor_event_id::text
      and v_reconciliation.reconciliation_proof->>'environment'
        is not distinct from v_reconciliation.environment
      and v_reconciliation.reconciliation_proof->>'targetExecutionEventId'
        is not distinct from v_reconciliation.target_execution_event_id::text
      and v_reconciliation.reconciliation_proof->>'verificationId'
        is not distinct from v_reconciliation.verification_id::text
      and v_reconciliation.reconciliation_proof->>'verificationState'
        is not distinct from v_reconciliation.verification_state
      and v_reconciliation.reconciliation_proof->>'reconciliationState'
        is not distinct from v_reconciliation.reconciliation_state
      and v_reconciliation.reconciliation_proof->>'reasonCode'
        is not distinct from v_reconciliation.reason_code
      and nullif(v_reconciliation.reconciliation_proof->'verification','null'::jsonb)
        is not distinct from v_reconciliation.verification_snapshot
      and nullif(v_reconciliation.reconciliation_proof->'currentEvaluation','null'::jsonb)
        is not distinct from v_reconciliation.current_evaluation
      and v_reconciliation.reconciliation_proof->'currentCoverage'
        is not distinct from v_reconciliation.current_coverage
      and v_reconciliation.reconciliation_proof->'layer81ActionResult'
        is not distinct from v_reconciliation.layer81_action_result
      and v_reconciliation.layer81_action_result is not distinct from v_target.action_result
      and nullif(v_reconciliation.reconciliation_proof->'proofIntegrityValid','null'::jsonb)
        is not distinct from to_jsonb(v_reconciliation.proof_integrity_valid)
      and nullif(v_reconciliation.reconciliation_proof->'receiptMatchesProof','null'::jsonb)
        is not distinct from to_jsonb(v_reconciliation.receipt_matches_proof)
      and nullif(v_reconciliation.reconciliation_proof->'currentEvaluationMatches','null'::jsonb)
        is not distinct from to_jsonb(v_reconciliation.current_evaluation_matches)
      and v_reconciliation.reconciliation_proof->'coverageTargetVisible'
        is not distinct from to_jsonb(v_reconciliation.coverage_target_visible)
      and nullif(v_reconciliation.reconciliation_proof->'coverageTargetMatches','null'::jsonb)
        is not distinct from to_jsonb(v_reconciliation.coverage_target_matches)
      and v_reconciliation.reconciliation_proof->'reconciledAt'
        is not distinct from to_jsonb(v_reconciliation.reconciled_at)
      and v_reconciliation.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
      and v_reconciliation.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
      and v_reconciliation.reconciliation_proof->'verificationProofRewritePerformed'='false'::jsonb
      and v_reconciliation.reconciliation_proof->'releaseTruthMutationPerformed'='false'::jsonb
      and v_reconciliation.reconciliation_proof->'incidentHistoryMutationPerformed'='false'::jsonb
      and v_reconciliation.reconciliation_proof->'approvalGranted'='false'::jsonb
      and v_reconciliation.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
      and v_reconciliation.reconciliation_proof->'mutationPerformed'='false'::jsonb
      and (
        (v_reconciliation.reconciliation_state='reconciled'
          and v_reconciliation.verification_id is not null
          and v_reconciliation.proof_integrity_valid is true
          and v_reconciliation.receipt_matches_proof is true
          and v_reconciliation.current_evaluation_matches is true
          and (v_reconciliation.coverage_target_visible=false
               or v_reconciliation.coverage_target_matches is true))
        or (v_reconciliation.reconciliation_state='missing-proof'
            and v_reconciliation.verification_id is null)
        or (v_reconciliation.reconciliation_state='receipt-mismatch'
            and v_reconciliation.verification_id is not null
            and v_reconciliation.receipt_matches_proof is false)
        or (v_reconciliation.reconciliation_state='invalid-proof'
            and v_reconciliation.verification_id is not null
            and v_reconciliation.proof_integrity_valid is false)
        or (v_reconciliation.reconciliation_state='evidence-drift'
            and v_reconciliation.verification_id is not null
            and v_reconciliation.proof_integrity_valid is true
            and v_reconciliation.receipt_matches_proof is true
            and v_reconciliation.current_evaluation_matches is false)
        or (v_reconciliation.reconciliation_state='coverage-drift'
            and v_reconciliation.verification_id is not null
            and v_reconciliation.proof_integrity_valid is true
            and v_reconciliation.receipt_matches_proof is true
            and v_reconciliation.current_evaluation_matches is true
            and v_reconciliation.coverage_target_visible=true
            and v_reconciliation.coverage_target_matches is false)
      );

    v_receipt_match :=
      v_exec.action_result->>'foundationCaseAuditVerificationExecutionReconciliation'
        is not distinct from
          'shine-foundation/case-audit-verification-execution-reconciliation-v1'
      and v_exec.action_result->>'schemaVersion' is not distinct from '1.0.0'
      and v_exec.action_result->>'status' in ('recorded','existing')
      and v_exec.action_result->>'reconciliationId'
        is not distinct from v_reconciliation.reconciliation_id::text
      and v_exec.action_result->>'executorEventId'
        is not distinct from v_reconciliation.executor_event_id::text
      and v_exec.action_result->>'targetExecutionEventId'
        is not distinct from v_reconciliation.target_execution_event_id::text
      and v_exec.action_result->>'verificationId'
        is not distinct from v_reconciliation.verification_id::text
      and v_exec.action_result->>'reconciliationState'
        is not distinct from v_reconciliation.reconciliation_state
      and v_exec.action_result->>'reasonCode'
        is not distinct from v_reconciliation.reason_code
      and v_exec.action_result->>'verificationState'
        is not distinct from v_reconciliation.verification_state
      and v_exec.action_result->>'reconciliationProofSha256'
        is not distinct from v_reconciliation.reconciliation_proof_sha256
      and v_exec.action_result->'verificationRerunPerformed'='false'::jsonb
      and v_exec.action_result->'mutationPerformed'='false'::jsonb;
  end if;

  v_state := case
    when v_reconciliation.reconciliation_id is null then 'missing-reconciliation'
    when not v_policy_integrity or not v_target_match or not v_incident_match then 'policy-mismatch'
    when not v_reconciliation_proof_integrity then 'invalid-reconciliation-proof'
    when not v_receipt_match then 'receipt-mismatch'
    else 'verified'
  end;

  v_reason := case v_state
    when 'missing-reconciliation' then 'case-audit-reconcile-exec-verify-reconciliation-missing'
    when 'policy-mismatch' then 'case-audit-reconcile-exec-verify-policy-mismatch'
    when 'invalid-reconciliation-proof' then 'case-audit-reconcile-exec-verify-reconciliation-proof-invalid'
    when 'receipt-mismatch' then 'case-audit-reconcile-exec-verify-receipt-mismatch'
    else 'case-audit-reconcile-exec-verify-complete'
  end;

  v_layer86_snapshot := jsonb_build_object(
    'eventId',v_exec.event_id,
    'environment',v_exec.environment,
    'targetExecutorEventId',v_exec.target_executor_event_id,
    'reconciliationIncidentEventId',v_exec.reconciliation_incident_event_id,
    'actionKey',v_exec.action_key,'causeClass',v_exec.cause_class,
    'policyFingerprint',v_exec.policy_fingerprint,'eventType',v_exec.event_type,
    'reasonCode',v_exec.reason_code,'requestedAt',v_exec.requested_at,
    'actionResult',v_exec.action_result
  );

  v_layer82_snapshot := case
    when v_reconciliation.reconciliation_id is null then null
    else jsonb_build_object(
      'reconciliationId',v_reconciliation.reconciliation_id,
      'executorEventId',v_reconciliation.executor_event_id,
      'environment',v_reconciliation.environment,
      'targetExecutionEventId',v_reconciliation.target_execution_event_id,
      'verificationId',v_reconciliation.verification_id,
      'verificationState',v_reconciliation.verification_state,
      'reconciliationState',v_reconciliation.reconciliation_state,
      'reasonCode',v_reconciliation.reason_code,
      'reconciliationProofSha256',v_reconciliation.reconciliation_proof_sha256,
      'reconciledAt',v_reconciliation.reconciled_at
    )
  end;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionVerificationOutcome',
      'shine-foundation/case-audit-reconciliation-execution-verification-outcome-v1',
    'schemaVersion','1.0.0','status','evaluated',
    'reconcileExecEventId',v_exec.event_id,'environment',v_exec.environment,
    'targetExecutorEventId',v_exec.target_executor_event_id,
    'reconciliationId',v_reconciliation.reconciliation_id,
    'verificationState',v_state,'reasonCode',v_reason,
    'policyIntegrityValid',v_policy_integrity,
    'targetSnapshotMatches',v_target_match,
    'incidentSnapshotMatches',v_incident_match,
    'reconciliationProofIntegrityValid',case
      when v_reconciliation.reconciliation_id is null then null
      else v_reconciliation_proof_integrity end,
    'receiptMatchesReconciliation',case
      when v_reconciliation.reconciliation_id is null then null
      else v_receipt_match end,
    'layer86',v_layer86_snapshot,'layer82',v_layer82_snapshot,
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,'incidentHistoryMutationPerformed',false
  );
end;
$layer87_evaluate$;

revoke all on function foundation.evaluate_case_audit_reconcile_exec_verification_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_reconcile_exec_verification_v1(
  uuid,timestamptz
) to foundation_runtime,service_role;


create or replace function foundation.run_case_audit_reconcile_exec_verification_v1(
  p_reconcile_exec_event_id uuid,
  p_verified_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer87_verify$
declare
  v_exec foundation.case_audit_verify_reconcile_exec_events%rowtype;
  v_existing foundation.case_audit_verify_reconcile_exec_verifications%rowtype;
  v_eval jsonb;
  v_proof jsonb;
  v_proof_hash text;
  v_verification_id uuid;
  v_reconciliation_id uuid;
begin
  if p_reconcile_exec_event_id is null then
    raise exception 'case-audit-reconcile-exec-verify-event-id-required';
  end if;

  if p_verified_at is null
     or p_verified_at<now()-interval '5 minutes'
     or p_verified_at>now()+interval '5 minutes' then
    raise exception 'case-audit-reconcile-exec-verify-time-invalid';
  end if;

  select * into v_exec
  from foundation.case_audit_verify_reconcile_exec_events
  where event_id=p_reconcile_exec_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionVerification',
        'shine-foundation/case-audit-reconciliation-execution-verification-v1',
      'schemaVersion','1.0.0','status','not-applicable',
      'reconcileExecEventId',p_reconcile_exec_event_id,
      'reasonCode','case-audit-reconcile-exec-verify-event-not-found',
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionVerification',
        'shine-foundation/case-audit-reconciliation-execution-verification-v1',
      'schemaVersion','1.0.0','status','not-applicable',
      'reconcileExecEventId',v_exec.event_id,
      'sourceExecutorEventType',v_exec.event_type,
      'reasonCode','case-audit-reconcile-exec-verify-source-not-executed',
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'mutationPerformed',false
    );
  end if;

  select * into v_existing
  from foundation.case_audit_verify_reconcile_exec_verifications
  where reconcile_exec_event_id=v_exec.event_id;

  if v_existing.verification_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditReconciliationExecutionVerification',
        'shine-foundation/case-audit-reconciliation-execution-verification-v1',
      'schemaVersion','1.0.0','status','existing',
      'verificationId',v_existing.verification_id,
      'reconcileExecEventId',v_existing.reconcile_exec_event_id,
      'targetExecutorEventId',v_existing.target_executor_event_id,
      'reconciliationId',v_existing.reconciliation_id,
      'verificationState',v_existing.verification_state,
      'reasonCode',v_existing.reason_code,
      'verificationProofSha256',v_existing.verification_proof_sha256,
      'layer82RerunPerformed',false,'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,'mutationPerformed',false
    );
  end if;

  v_eval:=foundation.evaluate_case_audit_reconcile_exec_verification_v1(
    v_exec.event_id,p_verified_at
  );

  if v_eval->>'status'<>'evaluated'
     or v_eval->>'verificationState' not in (
       'verified','missing-reconciliation','policy-mismatch',
       'receipt-mismatch','invalid-reconciliation-proof'
     ) then
    raise exception 'case-audit-reconcile-exec-verify-evaluation-invalid';
  end if;

  begin
    v_reconciliation_id:=nullif(v_eval->>'reconciliationId','')::uuid;
  exception when invalid_text_representation then
    v_reconciliation_id:=null;
  end;

  v_verification_id:=gen_random_uuid();

  v_proof:=jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionVerificationProof',
      'shine-foundation/case-audit-reconciliation-execution-verification-proof-v1',
    'schemaVersion','1.0.0','verificationId',v_verification_id,
    'reconcileExecEventId',v_exec.event_id,'environment',v_exec.environment,
    'targetExecutorEventId',v_exec.target_executor_event_id,
    'reconciliationId',v_reconciliation_id,
    'verificationState',v_eval->>'verificationState',
    'reasonCode',v_eval->>'reasonCode',
    'policyIntegrityValid',v_eval->'policyIntegrityValid',
    'targetSnapshotMatches',v_eval->'targetSnapshotMatches',
    'incidentSnapshotMatches',v_eval->'incidentSnapshotMatches',
    'reconciliationProofIntegrityValid',v_eval->'reconciliationProofIntegrityValid',
    'receiptMatchesReconciliation',v_eval->'receiptMatchesReconciliation',
    'layer86',v_eval->'layer86','layer82',v_eval->'layer82',
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,'incidentHistoryMutationPerformed',false,
    'approvalGranted',false,'executionAuthorityGranted',false,
    'mutationPerformed',false,'verifiedAt',p_verified_at
  );

  v_proof_hash:=encode(
    extensions.digest(convert_to(v_proof::text,'UTF8'),'sha256'),'hex'
  );

  insert into foundation.case_audit_verify_reconcile_exec_verifications(
    verification_id,reconcile_exec_event_id,environment,target_executor_event_id,
    reconciliation_id,verification_state,reason_code,policy_integrity_valid,
    target_snapshot_matches,incident_snapshot_matches,
    reconciliation_proof_integrity_valid,receipt_matches_reconciliation,
    layer86_snapshot,layer82_snapshot,verification_proof,
    verification_proof_sha256,verified_at
  )
  values(
    v_verification_id,v_exec.event_id,v_exec.environment,
    v_exec.target_executor_event_id,v_reconciliation_id,
    v_eval->>'verificationState',v_eval->>'reasonCode',
    (v_eval->>'policyIntegrityValid')::boolean,
    (v_eval->>'targetSnapshotMatches')::boolean,
    (v_eval->>'incidentSnapshotMatches')::boolean,
    case when v_eval->'reconciliationProofIntegrityValid' is null then null
         else (v_eval->>'reconciliationProofIntegrityValid')::boolean end,
    case when v_eval->'receiptMatchesReconciliation' is null then null
         else (v_eval->>'receiptMatchesReconciliation')::boolean end,
    v_eval->'layer86',nullif(v_eval->'layer82','null'::jsonb),
    v_proof,v_proof_hash,p_verified_at
  );

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionVerification',
      'shine-foundation/case-audit-reconciliation-execution-verification-v1',
    'schemaVersion','1.0.0','status','recorded',
    'verificationId',v_verification_id,'reconcileExecEventId',v_exec.event_id,
    'targetExecutorEventId',v_exec.target_executor_event_id,
    'reconciliationId',v_reconciliation_id,
    'verificationState',v_eval->>'verificationState',
    'reasonCode',v_eval->>'reasonCode',
    'verificationProofSha256',v_proof_hash,
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$layer87_verify$;

revoke all on function foundation.run_case_audit_reconcile_exec_verification_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_case_audit_reconcile_exec_verification_v1(
  uuid,timestamptz
) to service_role;


create or replace function foundation.get_case_audit_reconcile_exec_verification_summary_v1(
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
  v_items jsonb:='[]'::jsonb;
  v_total integer:=0; v_verified integer:=0; v_missing integer:=0;
  v_policy integer:=0; v_receipt integer:=0; v_invalid integer:=0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'case-audit-reconcile-exec-verify-summary-input-invalid';
  end if;

  select count(*),
    count(*) filter (where verification_state='verified'),
    count(*) filter (where verification_state='missing-reconciliation'),
    count(*) filter (where verification_state='policy-mismatch'),
    count(*) filter (where verification_state='receipt-mismatch'),
    count(*) filter (where verification_state='invalid-reconciliation-proof')
  into v_total,v_verified,v_missing,v_policy,v_receipt,v_invalid
  from foundation.case_audit_verify_reconcile_exec_verifications
  where environment=p_environment;

  select coalesce(jsonb_agg(jsonb_build_object(
    'verificationId',x.verification_id,
    'reconcileExecEventId',x.reconcile_exec_event_id,
    'targetExecutorEventId',x.target_executor_event_id,
    'reconciliationId',x.reconciliation_id,
    'verificationState',x.verification_state,'reasonCode',x.reason_code,
    'policyIntegrityValid',x.policy_integrity_valid,
    'targetSnapshotMatches',x.target_snapshot_matches,
    'incidentSnapshotMatches',x.incident_snapshot_matches,
    'reconciliationProofIntegrityValid',x.reconciliation_proof_integrity_valid,
    'receiptMatchesReconciliation',x.receipt_matches_reconciliation,
    'verificationProofSha256',x.verification_proof_sha256,
    'verifiedAt',x.verified_at
  ) order by x.verification_sequence desc),'[]'::jsonb)
  into v_items
  from (
    select * from foundation.case_audit_verify_reconcile_exec_verifications
    where environment=p_environment
    order by verification_sequence desc limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionVerificationSummary',
      'shine-foundation/case-audit-reconciliation-execution-verification-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,
    'totalCount',v_total,'verifiedCount',v_verified,
    'missingReconciliationCount',v_missing,'policyMismatchCount',v_policy,
    'receiptMismatchCount',v_receipt,'invalidReconciliationProofCount',v_invalid,
    'problemCount',v_missing+v_policy+v_receipt+v_invalid,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),'items',v_items,
    'layer82RerunPerformed',false,'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$layer87_summary$;

revoke all on function foundation.get_case_audit_reconcile_exec_verification_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_reconcile_exec_verification_summary_v1(
  text,integer
) to foundation_runtime,service_role;
