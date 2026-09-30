-- Foundation Layer 88: coverage audit for Layer-87 reconciliation.
-- Every successful Layer-86 reconciliation execution requires one immutable
-- Layer-87 reconciliation receipt. This reader separates receipt coverage from
-- healthy reconciliation outcome and independently recomputes Layer-87 receipt
-- integrity without rerunning or mutating any upstream control.

create or replace function foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(
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
as $layer88_coverage$
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
    raise exception 'case-audit-reconcile-exec-coverage-input-invalid';
  end if;

  with successful_exec as (
    select
      e.event_sequence,
      e.event_id as layer86_event_id,
      e.environment,
      e.target_executor_event_id,
      e.reconciliation_incident_event_id,
      e.action_key,
      e.cause_class,
      e.policy_fingerprint,
      e.reason_code as layer86_reason_code,
      e.action_result as layer86_action_result,
      e.requested_at,
      greatest(
        0,
        floor(extract(epoch from (p_as_of-e.requested_at)))::integer
      ) as age_seconds,
      r.reconciliation_id,
      r.layer82_reconciliation_id,
      r.reconciliation_state,
      r.reason_code as layer87_reason_code,
      r.policy_integrity_valid,
      r.incident_binding_valid,
      r.layer82_proof_integrity_valid,
      r.execution_receipt_matches,
      r.before_coverage_valid,
      r.after_coverage_valid,
      r.layer86_snapshot,
      r.layer82_snapshot,
      r.reconciliation_proof,
      r.reconciliation_proof_sha256,
      r.reconciled_at,
      l82.executor_event_id as l82_executor_event_id,
      l82.target_execution_event_id as l82_target_execution_event_id,
      l82.verification_id as l82_verification_id,
      l82.verification_state as l82_verification_state,
      l82.reconciliation_state as l82_reconciliation_state,
      l82.reason_code as l82_reason_code,
      l82.proof_integrity_valid as l82_proof_integrity_valid,
      l82.receipt_matches_proof as l82_receipt_matches_proof,
      l82.current_evaluation_matches as l82_current_evaluation_matches,
      l82.coverage_target_visible as l82_coverage_target_visible,
      l82.coverage_target_matches as l82_coverage_target_matches,
      l82.reconciliation_proof_sha256 as l82_reconciliation_proof_sha256,
      l82.reconciled_at as l82_reconciled_at
    from foundation.case_audit_verify_reconcile_exec_events e
    left join foundation.case_audit_verify_reconcile_exec_reconciliations r
      on r.layer86_event_id=e.event_id
    left join foundation.case_audit_verify_exec_reconciliations l82
      on l82.reconciliation_id=r.layer82_reconciliation_id
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
          and x.reconciliation_proof->>
                'foundationCaseAuditReconciliationExecutionReconciliationProof'
              is not distinct from
                'shine-foundation/case-audit-reconciliation-execution-reconciliation-proof-v1'
          and x.reconciliation_proof->>'schemaVersion'
              is not distinct from '1.0.0'
          and x.reconciliation_proof->>'reconciliationId'
              is not distinct from x.reconciliation_id::text
          and x.reconciliation_proof->>'layer86EventId'
              is not distinct from x.layer86_event_id::text
          and x.reconciliation_proof->>'environment'
              is not distinct from x.environment
          and x.reconciliation_proof->>'targetExecutorEventId'
              is not distinct from x.target_executor_event_id::text
          and x.reconciliation_proof->>'layer82ReconciliationId'
              is not distinct from x.layer82_reconciliation_id::text
          and x.reconciliation_proof->>'reconciliationState'
              is not distinct from x.reconciliation_state
          and x.reconciliation_proof->>'reasonCode'
              is not distinct from x.layer87_reason_code
          and x.reconciliation_proof->'policyIntegrityValid'
              is not distinct from to_jsonb(x.policy_integrity_valid)
          and x.reconciliation_proof->'incidentBindingValid'
              is not distinct from to_jsonb(x.incident_binding_valid)
          and nullif(
                x.reconciliation_proof->'layer82ProofIntegrityValid',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.layer82_proof_integrity_valid)
          and nullif(
                x.reconciliation_proof->'executionReceiptMatches',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.execution_receipt_matches)
          and x.reconciliation_proof->'beforeCoverageValid'
              is not distinct from to_jsonb(x.before_coverage_valid)
          and x.reconciliation_proof->'afterCoverageValid'
              is not distinct from to_jsonb(x.after_coverage_valid)
          and x.reconciliation_proof->'layer86ActionResult'
              is not distinct from x.layer86_action_result
          and nullif(
                x.reconciliation_proof->'layer82Receipt',
                'null'::jsonb
              ) is not distinct from x.layer82_snapshot
          and x.reconciliation_proof->'reconciledAt'
              is not distinct from to_jsonb(x.reconciled_at)
          and x.reconciliation_proof->'layer82RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer81RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
          and x.reconciliation_proof->'reconciliationReceiptRewritePerformed'
              ='false'::jsonb
          and x.reconciliation_proof->'verificationProofRewritePerformed'
              ='false'::jsonb
          and x.reconciliation_proof->'releaseTruthMutationPerformed'
              ='false'::jsonb
          and x.reconciliation_proof->'incidentHistoryMutationPerformed'
              ='false'::jsonb
          and x.reconciliation_proof->'approvalGranted'='false'::jsonb
          and x.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
          and x.reconciliation_proof->'mutationPerformed'='false'::jsonb
          and x.layer86_snapshot->>'layer86EventId'
              is not distinct from x.layer86_event_id::text
          and x.layer86_snapshot->>'targetExecutorEventId'
              is not distinct from x.target_executor_event_id::text
          and x.layer86_snapshot->>'reconciliationIncidentEventId'
              is not distinct from x.reconciliation_incident_event_id::text
          and x.layer86_snapshot->>'actionKey'
              is not distinct from x.action_key
          and x.layer86_snapshot->>'causeClass'
              is not distinct from x.cause_class
          and x.layer86_snapshot->>'policyFingerprint'
              is not distinct from x.policy_fingerprint
          and x.layer86_snapshot->>'eventType'
              is not distinct from 'executed'
          and x.layer86_snapshot->>'reasonCode'
              is not distinct from x.layer86_reason_code
          and x.layer86_snapshot->'requestedAt'
              is not distinct from to_jsonb(x.requested_at)
          and (
            (
              x.layer82_reconciliation_id is null
              and x.layer82_snapshot is null
              and x.reconciliation_state='missing-layer82-receipt'
              and x.layer82_proof_integrity_valid is null
              and x.execution_receipt_matches is null
            )
            or
            (
              x.layer82_reconciliation_id is not null
              and x.l82_executor_event_id is not null
              and x.layer82_snapshot->>'reconciliationId'
                  is not distinct from x.layer82_reconciliation_id::text
              and x.layer82_snapshot->>'executorEventId'
                  is not distinct from x.l82_executor_event_id::text
              and x.layer82_snapshot->>'targetExecutionEventId'
                  is not distinct from x.l82_target_execution_event_id::text
              and x.layer82_snapshot->>'verificationId'
                  is not distinct from x.l82_verification_id::text
              and x.layer82_snapshot->>'verificationState'
                  is not distinct from x.l82_verification_state
              and x.layer82_snapshot->>'reconciliationState'
                  is not distinct from x.l82_reconciliation_state
              and x.layer82_snapshot->>'reasonCode'
                  is not distinct from x.l82_reason_code
              and nullif(
                    x.layer82_snapshot->'proofIntegrityValid',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l82_proof_integrity_valid)
              and nullif(
                    x.layer82_snapshot->'receiptMatchesProof',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l82_receipt_matches_proof)
              and nullif(
                    x.layer82_snapshot->'currentEvaluationMatches',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l82_current_evaluation_matches)
              and x.layer82_snapshot->'coverageTargetVisible'
                  is not distinct from to_jsonb(x.l82_coverage_target_visible)
              and nullif(
                    x.layer82_snapshot->'coverageTargetMatches',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l82_coverage_target_matches)
              and x.layer82_snapshot->>'reconciliationProofSha256'
                  is not distinct from x.l82_reconciliation_proof_sha256
              and x.layer82_snapshot->'reconciledAt'
                  is not distinct from to_jsonb(x.l82_reconciled_at)
            )
          )
          and (
            (
              x.reconciliation_state='reconciled'
              and x.layer82_reconciliation_id is not null
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is true
              and x.layer82_proof_integrity_valid is true
              and x.execution_receipt_matches is true
              and x.before_coverage_valid is true
              and x.after_coverage_valid is true
            )
            or
            (
              x.reconciliation_state='missing-layer82-receipt'
              and x.layer82_reconciliation_id is null
            )
            or
            (
              x.reconciliation_state='invalid-layer82-receipt'
              and x.layer82_reconciliation_id is not null
              and x.layer82_proof_integrity_valid is false
            )
            or
            (
              x.reconciliation_state='execution-receipt-mismatch'
              and x.layer82_reconciliation_id is not null
              and x.layer82_proof_integrity_valid is true
              and x.execution_receipt_matches is false
            )
            or
            (
              x.reconciliation_state='policy-drift'
              and x.layer82_reconciliation_id is not null
              and x.layer82_proof_integrity_valid is true
              and x.policy_integrity_valid is false
            )
            or
            (
              x.reconciliation_state='incident-drift'
              and x.layer82_reconciliation_id is not null
              and x.layer82_proof_integrity_valid is true
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is false
            )
            or
            (
              x.reconciliation_state='coverage-drift'
              and x.layer82_reconciliation_id is not null
              and x.layer82_proof_integrity_valid is true
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is true
              and x.execution_receipt_matches is true
              and (
                x.before_coverage_valid is false
                or x.after_coverage_valid is false
              )
            )
          )
      end as layer87_proof_integrity_valid
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
        when coalesce(x.layer87_proof_integrity_valid,false)=false
          then 'invalid-reconciliation'
        else x.reconciliation_state
      end as coverage_state,
      case
        when x.reconciliation_id is null
             and x.age_seconds<=p_reconciliation_grace_seconds
          then 'case-audit-reconcile-exec-layer87-within-grace'
        when x.reconciliation_id is null
          then 'case-audit-reconcile-exec-layer87-overdue'
        when coalesce(x.layer87_proof_integrity_valid,false)=false
          then 'case-audit-reconcile-exec-layer87-receipt-invalid'
        when x.reconciliation_state='reconciled'
          then 'case-audit-reconcile-exec-layer87-covered'
        else x.layer87_reason_code
      end as coverage_reason_code
    from inspected x
  ),
  totals as (
    select
      count(*)::integer as execution_count,
      count(*) filter (where reconciliation_id is not null)::integer
        as receipt_count,
      count(*) filter (where coverage_state='reconciled')::integer
        as reconciled_count,
      count(*) filter (where coverage_state='pending')::integer
        as pending_count,
      count(*) filter (where coverage_state='overdue')::integer
        as overdue_count,
      count(*) filter (where coverage_state='invalid-reconciliation')::integer
        as invalid_reconciliation_count,
      count(*) filter (where coverage_state='missing-layer82-receipt')::integer
        as missing_layer82_count,
      count(*) filter (where coverage_state='invalid-layer82-receipt')::integer
        as invalid_layer82_count,
      count(*) filter (where coverage_state='execution-receipt-mismatch')::integer
        as execution_receipt_mismatch_count,
      count(*) filter (where coverage_state='policy-drift')::integer
        as policy_drift_count,
      count(*) filter (where coverage_state='incident-drift')::integer
        as incident_drift_count,
      count(*) filter (where coverage_state='coverage-drift')::integer
        as coverage_drift_count
    from classified
  ),
  visible as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'layer86EventId',q.layer86_event_id,
          'targetExecutorEventId',q.target_executor_event_id,
          'reconciliationIncidentEventId',q.reconciliation_incident_event_id,
          'executionRequestedAt',q.requested_at,
          'executionAgeSeconds',q.age_seconds,
          'coverageState',q.coverage_state,
          'reasonCode',q.coverage_reason_code,
          'layer87ReconciliationId',q.reconciliation_id,
          'layer87ReconciliationState',q.reconciliation_state,
          'layer82ReconciliationId',q.layer82_reconciliation_id,
          'layer82ReconciliationState',q.l82_reconciliation_state,
          'layer87ProofIntegrityValid',q.layer87_proof_integrity_valid,
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
    'foundationCaseAuditReconciliationExecutionReconciliationCoverage',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',case
      when t.execution_count=0 then 'idle'
      when t.invalid_reconciliation_count>0 then 'invalid'
      when t.overdue_count>0
        or t.missing_layer82_count>0
        or t.invalid_layer82_count>0
        or t.execution_receipt_mismatch_count>0
        or t.policy_drift_count>0
        or t.incident_drift_count>0
        or t.coverage_drift_count>0 then 'gap'
      when t.pending_count>0 then 'pending'
      else 'normal'
    end,
    'reasonCode',case
      when t.execution_count=0
        then 'case-audit-reconcile-exec-layer87-no-executions'
      when t.invalid_reconciliation_count>0
        then 'case-audit-reconcile-exec-layer87-receipt-invalid'
      when t.overdue_count>0
        then 'case-audit-reconcile-exec-layer87-overdue'
      when t.missing_layer82_count>0
        then 'case-audit-reconcile-exec-layer82-receipt-missing'
      when t.invalid_layer82_count>0
        then 'case-audit-reconcile-exec-layer82-receipt-invalid'
      when t.execution_receipt_mismatch_count>0
        then 'case-audit-reconcile-exec-receipt-mismatch'
      when t.policy_drift_count>0
        then 'case-audit-reconcile-exec-policy-drift'
      when t.incident_drift_count>0
        then 'case-audit-reconcile-exec-incident-drift'
      when t.coverage_drift_count>0
        then 'case-audit-reconcile-exec-coverage-drift'
      when t.pending_count>0
        then 'case-audit-reconcile-exec-layer87-within-grace'
      else 'case-audit-reconcile-exec-layer87-covered'
    end,
    'successfulLayer86ExecutionCount',t.execution_count,
    'layer87ReconciliationRequiredCount',t.execution_count,
    'layer87ReconciliationReceiptCount',t.receipt_count,
    'reconciledCount',t.reconciled_count,
    'pendingCount',t.pending_count,
    'overdueCount',t.overdue_count,
    'invalidLayer87ReconciliationCount',t.invalid_reconciliation_count,
    'missingLayer82ReceiptCount',t.missing_layer82_count,
    'invalidLayer82ReceiptCount',t.invalid_layer82_count,
    'executionReceiptMismatchCount',t.execution_receipt_mismatch_count,
    'policyDriftCount',t.policy_drift_count,
    'incidentDriftCount',t.incident_drift_count,
    'coverageDriftCount',t.coverage_drift_count,
    'problemCount',
      t.overdue_count+t.invalid_reconciliation_count+
      t.missing_layer82_count+t.invalid_layer82_count+
      t.execution_receipt_mismatch_count+t.policy_drift_count+
      t.incident_drift_count+t.coverage_drift_count,
    'layer87ReconciliationCoveragePercent',case
      when t.execution_count=0 then 100.00
      else round((100.0*t.receipt_count/t.execution_count)::numeric,2)
    end,
    'healthyLayer87ReconciliationPercent',case
      when t.execution_count=0 then 100.00
      else round((100.0*t.reconciled_count/t.execution_count)::numeric,2)
    end,
    'visibleCount',jsonb_array_length(v.items),
    'hasMore',t.execution_count>jsonb_array_length(v.items),
    'items',v.items,
    'onlySuccessfulLayer86ExecutionsRequireLayer87Reconciliation',true,
    'layer87ProofIntegrityRecomputed',true,
    'linkedLayer82SnapshotRevalidated',true,
    'layer87ReconciliationPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
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
$layer88_coverage$;

revoke all on function foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(
  text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(
  text,timestamptz,integer,integer
) to foundation_runtime,service_role;
