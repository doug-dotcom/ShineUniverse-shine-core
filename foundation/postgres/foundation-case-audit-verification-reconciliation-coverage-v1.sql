-- Foundation Layer 83: coverage audit for Layer-82 reconciliation.
-- Every successful Layer-81 execution requires one immutable Layer-82
-- reconciliation receipt. This reader separates receipt coverage from healthy
-- reconciliation outcome and independently recomputes Layer-82 proof integrity.

create or replace function foundation.get_case_audit_verify_reconcile_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer83_coverage$
declare
  v_result jsonb;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600
     or p_limit is null
     or p_limit<1
     or p_limit>100 then
    raise exception 'case-audit-verify-reconcile-coverage-input-invalid';
  end if;

  with successful_exec as (
    select
      e.event_sequence,
      e.event_id as executor_event_id,
      e.environment,
      e.target_execution_event_id,
      e.verification_incident_event_id,
      e.policy_fingerprint,
      e.action_result,
      e.requested_at,
      greatest(
        0,
        floor(extract(epoch from (p_as_of-e.requested_at)))::integer
      ) as age_seconds,
      r.reconciliation_id,
      r.verification_id,
      r.reconciliation_state,
      r.reason_code as reconciliation_reason_code,
      r.verification_state,
      r.proof_integrity_valid,
      r.receipt_matches_proof,
      r.current_evaluation_matches,
      r.coverage_target_visible,
      r.coverage_target_matches,
      r.verification_snapshot,
      r.current_evaluation,
      r.current_coverage,
      r.layer81_action_result,
      r.reconciliation_proof,
      r.reconciliation_proof_sha256,
      r.reconciled_at
    from foundation.case_audit_verify_exec_events e
    left join foundation.case_audit_verify_exec_reconciliations r
      on r.executor_event_id=e.event_id
    where e.environment=p_environment
      and e.event_type='executed'
      and e.requested_at<=p_as_of
  ),
  inspected as (
    select
      x.*,
      case
        when x.reconciliation_id is null then null
        else
          encode(
            extensions.digest(
              convert_to(x.reconciliation_proof::text,'UTF8'),
              'sha256'
            ),
            'hex'
          ) is not distinct from x.reconciliation_proof_sha256
          and x.reconciliation_proof->
                'foundationCaseAuditVerificationExecutionReconciliationProof'
              is not null
          and x.reconciliation_proof->>
                'foundationCaseAuditVerificationExecutionReconciliationProof'
              is not distinct from
                'shine-foundation/case-audit-verification-execution-reconciliation-proof-v1'
          and x.reconciliation_proof->>'schemaVersion'
              is not distinct from '1.0.0'
          and x.reconciliation_proof->>'reconciliationId'
              is not distinct from x.reconciliation_id::text
          and x.reconciliation_proof->>'executorEventId'
              is not distinct from x.executor_event_id::text
          and x.reconciliation_proof->>'environment'
              is not distinct from x.environment
          and x.reconciliation_proof->>'targetExecutionEventId'
              is not distinct from x.target_execution_event_id::text
          and x.reconciliation_proof->>'verificationIncidentEventId'
              is not distinct from x.verification_incident_event_id::text
          and x.reconciliation_proof->>'verificationId'
              is not distinct from x.verification_id::text
          and x.reconciliation_proof->>'verificationState'
              is not distinct from x.verification_state
          and x.reconciliation_proof->>'reconciliationState'
              is not distinct from x.reconciliation_state
          and x.reconciliation_proof->>'reasonCode'
              is not distinct from x.reconciliation_reason_code
          and nullif(
                x.reconciliation_proof->'verification',
                'null'::jsonb
              ) is not distinct from x.verification_snapshot
          and nullif(
                x.reconciliation_proof->'currentEvaluation',
                'null'::jsonb
              ) is not distinct from x.current_evaluation
          and x.reconciliation_proof->'currentCoverage'
              is not distinct from x.current_coverage
          and x.reconciliation_proof->'layer81ActionResult'
              is not distinct from x.layer81_action_result
          and x.layer81_action_result is not distinct from x.action_result
          and nullif(
                x.reconciliation_proof->'proofIntegrityValid',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.proof_integrity_valid)
          and nullif(
                x.reconciliation_proof->'receiptMatchesProof',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.receipt_matches_proof)
          and nullif(
                x.reconciliation_proof->'currentEvaluationMatches',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.current_evaluation_matches)
          and x.reconciliation_proof->'coverageTargetVisible'
              is not distinct from to_jsonb(x.coverage_target_visible)
          and nullif(
                x.reconciliation_proof->'coverageTargetMatches',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.coverage_target_matches)
          and x.reconciliation_proof->'reconciledAt'
              is not distinct from to_jsonb(x.reconciled_at)
          and x.reconciliation_proof->'verificationRerunPerformed'
              = 'false'::jsonb
          and x.reconciliation_proof->'evidenceMutationPerformed'
              = 'false'::jsonb
          and x.reconciliation_proof->'verificationProofRewritePerformed'
              = 'false'::jsonb
          and x.reconciliation_proof->'releaseTruthMutationPerformed'
              = 'false'::jsonb
          and x.reconciliation_proof->'incidentHistoryMutationPerformed'
              = 'false'::jsonb
          and x.reconciliation_proof->'approvalGranted'
              = 'false'::jsonb
          and x.reconciliation_proof->'executionAuthorityGranted'
              = 'false'::jsonb
          and x.reconciliation_proof->'mutationPerformed'
              = 'false'::jsonb
          and (
            (
              x.reconciliation_state='reconciled'
              and x.verification_id is not null
              and x.proof_integrity_valid is true
              and x.receipt_matches_proof is true
              and x.current_evaluation_matches is true
              and (
                x.coverage_target_visible=false
                or x.coverage_target_matches is true
              )
            )
            or
            (
              x.reconciliation_state='missing-proof'
              and x.verification_id is null
            )
            or
            (
              x.reconciliation_state='receipt-mismatch'
              and x.verification_id is not null
              and x.receipt_matches_proof is false
            )
            or
            (
              x.reconciliation_state='invalid-proof'
              and x.verification_id is not null
              and x.proof_integrity_valid is false
            )
            or
            (
              x.reconciliation_state='evidence-drift'
              and x.verification_id is not null
              and x.proof_integrity_valid is true
              and x.receipt_matches_proof is true
              and x.current_evaluation_matches is false
            )
            or
            (
              x.reconciliation_state='coverage-drift'
              and x.verification_id is not null
              and x.proof_integrity_valid is true
              and x.receipt_matches_proof is true
              and x.current_evaluation_matches is true
              and x.coverage_target_visible=true
              and x.coverage_target_matches is false
            )
          )
      end as reconciliation_proof_integrity_valid
    from successful_exec x
  ),
  classified as (
    select
      x.*,
      case
        when x.reconciliation_id is null
             and x.age_seconds<=p_reconciliation_grace_seconds
          then 'pending'
        when x.reconciliation_id is null
          then 'overdue'
        when coalesce(x.reconciliation_proof_integrity_valid,false)=false
          then 'invalid-reconciliation'
        else x.reconciliation_state
      end as coverage_state,
      case
        when x.reconciliation_id is null
             and x.age_seconds<=p_reconciliation_grace_seconds
          then 'case-audit-verify-reconcile-within-grace'
        when x.reconciliation_id is null
          then 'case-audit-verify-reconcile-overdue'
        when coalesce(x.reconciliation_proof_integrity_valid,false)=false
          then 'case-audit-verify-reconcile-receipt-invalid'
        when x.reconciliation_state='reconciled'
          then 'case-audit-verify-reconcile-covered'
        else x.reconciliation_reason_code
      end as coverage_reason_code
    from inspected x
  ),
  totals as (
    select
      count(*)::integer as execution_count,
      count(*) filter (where reconciliation_id is not null)::integer
        as reconciliation_receipt_count,
      count(*) filter (where coverage_state='reconciled')::integer
        as reconciled_count,
      count(*) filter (where coverage_state='pending')::integer
        as pending_count,
      count(*) filter (where coverage_state='overdue')::integer
        as overdue_count,
      count(*) filter (where coverage_state='invalid-reconciliation')::integer
        as invalid_reconciliation_count,
      count(*) filter (where coverage_state='missing-proof')::integer
        as missing_proof_count,
      count(*) filter (where coverage_state='receipt-mismatch')::integer
        as receipt_mismatch_count,
      count(*) filter (where coverage_state='invalid-proof')::integer
        as invalid_proof_count,
      count(*) filter (where coverage_state='evidence-drift')::integer
        as evidence_drift_count,
      count(*) filter (where coverage_state='coverage-drift')::integer
        as coverage_drift_count
    from classified
  ),
  visible as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'executorEventId',q.executor_event_id,
          'targetExecutionEventId',q.target_execution_event_id,
          'verificationIncidentEventId',q.verification_incident_event_id,
          'executionRequestedAt',q.requested_at,
          'executionAgeSeconds',q.age_seconds,
          'coverageState',q.coverage_state,
          'reasonCode',q.coverage_reason_code,
          'reconciliationId',q.reconciliation_id,
          'reconciliationState',q.reconciliation_state,
          'verificationId',q.verification_id,
          'verificationState',q.verification_state,
          'reconciliationProofIntegrityValid',
            q.reconciliation_proof_integrity_valid,
          'reconciledAt',q.reconciled_at
        )
        order by q.event_sequence desc
      ),
      '[]'::jsonb
    ) as items
    from (
      select *
      from classified
      order by event_sequence desc
      limit p_limit
    ) q
  )
  select jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationCoverage',
      'shine-foundation/case-audit-verification-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',case
      when t.execution_count=0 then 'idle'
      when t.invalid_reconciliation_count>0 then 'invalid'
      when t.overdue_count>0
        or t.missing_proof_count>0
        or t.receipt_mismatch_count>0
        or t.invalid_proof_count>0
        or t.evidence_drift_count>0
        or t.coverage_drift_count>0 then 'gap'
      when t.pending_count>0 then 'pending'
      else 'normal'
    end,
    'reasonCode',case
      when t.execution_count=0
        then 'case-audit-verify-reconcile-no-executions'
      when t.invalid_reconciliation_count>0
        then 'case-audit-verify-reconcile-receipt-invalid'
      when t.overdue_count>0
        then 'case-audit-verify-reconcile-overdue'
      when t.missing_proof_count>0
        then 'case-audit-verify-exec-reconcile-proof-missing'
      when t.receipt_mismatch_count>0
        then 'case-audit-verify-exec-reconcile-receipt-mismatch'
      when t.invalid_proof_count>0
        then 'case-audit-verify-exec-reconcile-proof-invalid'
      when t.evidence_drift_count>0
        then 'case-audit-verify-exec-reconcile-evidence-drift'
      when t.coverage_drift_count>0
        then 'case-audit-verify-exec-reconcile-coverage-drift'
      when t.pending_count>0
        then 'case-audit-verify-reconcile-within-grace'
      else 'case-audit-verify-reconcile-covered'
    end,
    'successfulExecutorCount',t.execution_count,
    'reconciliationRequiredCount',t.execution_count,
    'reconciliationReceiptCount',t.reconciliation_receipt_count,
    'reconciledCount',t.reconciled_count,
    'pendingCount',t.pending_count,
    'overdueCount',t.overdue_count,
    'invalidReconciliationCount',t.invalid_reconciliation_count,
    'missingProofCount',t.missing_proof_count,
    'receiptMismatchCount',t.receipt_mismatch_count,
    'invalidProofCount',t.invalid_proof_count,
    'evidenceDriftCount',t.evidence_drift_count,
    'coverageDriftCount',t.coverage_drift_count,
    'problemCount',
      t.overdue_count+t.invalid_reconciliation_count+
      t.missing_proof_count+t.receipt_mismatch_count+
      t.invalid_proof_count+t.evidence_drift_count+
      t.coverage_drift_count,
    'reconciliationCoveragePercent',case
      when t.execution_count=0 then 100.00
      else round(
        (100.0*t.reconciliation_receipt_count/t.execution_count)::numeric,
        2
      )
    end,
    'healthyReconciliationPercent',case
      when t.execution_count=0 then 100.00
      else round(
        (100.0*t.reconciled_count/t.execution_count)::numeric,
        2
      )
    end,
    'visibleCount',jsonb_array_length(v.items),
    'hasMore',t.execution_count>jsonb_array_length(v.items),
    'items',v.items,
    'onlySuccessfulLayer81ExecutionsRequireReconciliation',true,
    'reconciliationProofIntegrityRecomputed',true,
    'verificationRerunPerformed',false,
    'layer81RerunPerformed',false,
    'evidenceMutationPerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  )
  into v_result
  from totals t
  cross join visible v;

  return v_result;
end;
$layer83_coverage$;

revoke all on function foundation.get_case_audit_verify_reconcile_coverage_v1(
  text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_reconcile_coverage_v1(
  text,timestamptz,integer,integer
) to foundation_runtime,service_role;
