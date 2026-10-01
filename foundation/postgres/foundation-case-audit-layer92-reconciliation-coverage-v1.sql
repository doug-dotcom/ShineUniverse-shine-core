-- Foundation Layer 93: coverage audit for Layer-92 reconciliation.
-- Every successful Layer-91 bounded Layer-87 reconciliation execution requires
-- one immutable Layer-92 reconciliation receipt. Coverage is separated from
-- reconciliation health, and Layer-92 proof integrity is recomputed read-only.

create or replace function foundation.get_case_audit_layer92_reconciliation_coverage_v1(
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
as $layer93_coverage$
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
    raise exception 'case-audit-layer92-coverage-input-invalid';
  end if;

  with successful_exec as (
    select
      e.event_sequence,
      e.event_id as layer91_event_id,
      e.environment,
      e.target_layer86_event_id,
      e.coverage_incident_event_id,
      e.action_key,
      e.cause_class,
      e.policy_fingerprint,
      e.reason_code as layer91_reason_code,
      e.action_result as layer91_action_result,
      e.requested_at,
      greatest(
        0,
        floor(extract(epoch from (p_as_of-e.requested_at)))::integer
      ) as age_seconds,
      r.reconciliation_id,
      r.layer87_reconciliation_id,
      r.reconciliation_state,
      r.reason_code as layer92_reason_code,
      r.policy_integrity_valid,
      r.incident_binding_valid,
      r.layer87_proof_integrity_valid,
      r.execution_receipt_matches,
      r.before_coverage_valid,
      r.after_coverage_valid,
      r.layer91_snapshot,
      r.layer87_snapshot,
      r.reconciliation_proof,
      r.reconciliation_proof_sha256,
      r.reconciled_at,
      l87.layer86_event_id as l87_layer86_event_id,
      l87.target_executor_event_id as l87_target_executor_event_id,
      l87.layer82_reconciliation_id as l87_layer82_reconciliation_id,
      l87.reconciliation_state as l87_reconciliation_state,
      l87.reason_code as l87_reason_code,
      l87.policy_integrity_valid as l87_policy_integrity_valid,
      l87.incident_binding_valid as l87_incident_binding_valid,
      l87.layer82_proof_integrity_valid as l87_layer82_proof_integrity_valid,
      l87.execution_receipt_matches as l87_execution_receipt_matches,
      l87.before_coverage_valid as l87_before_coverage_valid,
      l87.after_coverage_valid as l87_after_coverage_valid,
      l87.reconciliation_proof_sha256 as l87_reconciliation_proof_sha256,
      l87.reconciled_at as l87_reconciled_at
    from foundation.case_audit_reconcile_exec_reconcile_exec_events e
    left join foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations r
      on r.layer91_event_id=e.event_id
    left join foundation.case_audit_verify_reconcile_exec_reconciliations l87
      on l87.reconciliation_id=r.layer87_reconciliation_id
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
                'foundationCaseAuditLayer91ExecutionReconciliationProof'
              is not distinct from
                'shine-foundation/case-audit-layer91-execution-reconciliation-proof-v1'
          and x.reconciliation_proof->>'schemaVersion'
              is not distinct from '1.0.0'
          and x.reconciliation_proof->>'reconciliationId'
              is not distinct from x.reconciliation_id::text
          and x.reconciliation_proof->>'layer91EventId'
              is not distinct from x.layer91_event_id::text
          and x.reconciliation_proof->>'environment'
              is not distinct from x.environment
          and x.reconciliation_proof->>'targetLayer86EventId'
              is not distinct from x.target_layer86_event_id::text
          and x.reconciliation_proof->>'layer87ReconciliationId'
              is not distinct from x.layer87_reconciliation_id::text
          and x.reconciliation_proof->>'reconciliationState'
              is not distinct from x.reconciliation_state
          and x.reconciliation_proof->>'reasonCode'
              is not distinct from x.layer92_reason_code
          and x.reconciliation_proof->'policyIntegrityValid'
              is not distinct from to_jsonb(x.policy_integrity_valid)
          and x.reconciliation_proof->'incidentBindingValid'
              is not distinct from to_jsonb(x.incident_binding_valid)
          and nullif(
                x.reconciliation_proof->'layer87ProofIntegrityValid',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.layer87_proof_integrity_valid)
          and nullif(
                x.reconciliation_proof->'executionReceiptMatches',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.execution_receipt_matches)
          and x.reconciliation_proof->'beforeCoverageValid'
              is not distinct from to_jsonb(x.before_coverage_valid)
          and x.reconciliation_proof->'afterCoverageValid'
              is not distinct from to_jsonb(x.after_coverage_valid)
          and x.reconciliation_proof->'layer91ActionResult'
              is not distinct from x.layer91_action_result
          and nullif(
                x.reconciliation_proof->'layer87Receipt',
                'null'::jsonb
              ) is not distinct from x.layer87_snapshot
          and x.reconciliation_proof->'reconciledAt'
              is not distinct from to_jsonb(x.reconciled_at)
          and x.reconciliation_proof->'layer87RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer86RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer82RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer81RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer87ReceiptRewritePerformed'='false'::jsonb
          and x.reconciliation_proof->'layer86ReceiptRewritePerformed'='false'::jsonb
          and x.reconciliation_proof->'layer82ReceiptRewritePerformed'='false'::jsonb
          and x.reconciliation_proof->'releaseTruthMutationPerformed'='false'::jsonb
          and x.reconciliation_proof->'incidentHistoryMutationPerformed'='false'::jsonb
          and x.reconciliation_proof->'approvalGranted'='false'::jsonb
          and x.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
          and x.reconciliation_proof->'mutationPerformed'='false'::jsonb
          and x.layer91_snapshot->>'layer91EventId'
              is not distinct from x.layer91_event_id::text
          and x.layer91_snapshot->>'targetLayer86EventId'
              is not distinct from x.target_layer86_event_id::text
          and x.layer91_snapshot->>'coverageIncidentEventId'
              is not distinct from x.coverage_incident_event_id::text
          and x.layer91_snapshot->>'actionKey'
              is not distinct from x.action_key
          and x.layer91_snapshot->>'causeClass'
              is not distinct from x.cause_class
          and x.layer91_snapshot->>'policyFingerprint'
              is not distinct from x.policy_fingerprint
          and x.layer91_snapshot->>'eventType'
              is not distinct from 'executed'
          and x.layer91_snapshot->>'reasonCode'
              is not distinct from x.layer91_reason_code
          and x.layer91_snapshot->'requestedAt'
              is not distinct from to_jsonb(x.requested_at)
          and (
            (
              x.layer87_reconciliation_id is null
              and x.layer87_snapshot is null
              and x.reconciliation_state='missing-layer87-receipt'
              and x.layer87_proof_integrity_valid is null
              and x.execution_receipt_matches is null
            )
            or
            (
              x.layer87_reconciliation_id is not null
              and x.l87_layer86_event_id is not null
              and x.layer87_snapshot->>'reconciliationId'
                  is not distinct from x.layer87_reconciliation_id::text
              and x.layer87_snapshot->>'layer86EventId'
                  is not distinct from x.l87_layer86_event_id::text
              and x.layer87_snapshot->>'targetExecutorEventId'
                  is not distinct from x.l87_target_executor_event_id::text
              and x.layer87_snapshot->>'layer82ReconciliationId'
                  is not distinct from x.l87_layer82_reconciliation_id::text
              and x.layer87_snapshot->>'reconciliationState'
                  is not distinct from x.l87_reconciliation_state
              and x.layer87_snapshot->>'reasonCode'
                  is not distinct from x.l87_reason_code
              and x.layer87_snapshot->'policyIntegrityValid'
                  is not distinct from to_jsonb(x.l87_policy_integrity_valid)
              and x.layer87_snapshot->'incidentBindingValid'
                  is not distinct from to_jsonb(x.l87_incident_binding_valid)
              and nullif(
                    x.layer87_snapshot->'layer82ProofIntegrityValid',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l87_layer82_proof_integrity_valid)
              and nullif(
                    x.layer87_snapshot->'executionReceiptMatches',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l87_execution_receipt_matches)
              and x.layer87_snapshot->'beforeCoverageValid'
                  is not distinct from to_jsonb(x.l87_before_coverage_valid)
              and x.layer87_snapshot->'afterCoverageValid'
                  is not distinct from to_jsonb(x.l87_after_coverage_valid)
              and x.layer87_snapshot->>'reconciliationProofSha256'
                  is not distinct from x.l87_reconciliation_proof_sha256
              and x.layer87_snapshot->'reconciledAt'
                  is not distinct from to_jsonb(x.l87_reconciled_at)
            )
          )
          and (
            (
              x.reconciliation_state='reconciled'
              and x.layer87_reconciliation_id is not null
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is true
              and x.layer87_proof_integrity_valid is true
              and x.execution_receipt_matches is true
              and x.before_coverage_valid is true
              and x.after_coverage_valid is true
            )
            or
            (
              x.reconciliation_state='missing-layer87-receipt'
              and x.layer87_reconciliation_id is null
            )
            or
            (
              x.reconciliation_state='invalid-layer87-receipt'
              and x.layer87_reconciliation_id is not null
              and x.layer87_proof_integrity_valid is false
            )
            or
            (
              x.reconciliation_state='execution-receipt-mismatch'
              and x.layer87_reconciliation_id is not null
              and x.layer87_proof_integrity_valid is true
              and x.execution_receipt_matches is false
            )
            or
            (
              x.reconciliation_state='policy-drift'
              and x.layer87_reconciliation_id is not null
              and x.layer87_proof_integrity_valid is true
              and x.policy_integrity_valid is false
            )
            or
            (
              x.reconciliation_state='incident-drift'
              and x.layer87_reconciliation_id is not null
              and x.layer87_proof_integrity_valid is true
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is false
            )
            or
            (
              x.reconciliation_state='coverage-drift'
              and x.layer87_reconciliation_id is not null
              and x.layer87_proof_integrity_valid is true
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is true
              and x.execution_receipt_matches is true
              and (
                x.before_coverage_valid is false
                or x.after_coverage_valid is false
              )
            )
          )
      end as layer92_proof_integrity_valid
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
        when coalesce(x.layer92_proof_integrity_valid,false)=false
          then 'invalid-reconciliation'
        else x.reconciliation_state
      end as coverage_state,
      case
        when x.reconciliation_id is null
             and x.age_seconds<=p_reconciliation_grace_seconds
          then 'case-audit-layer92-within-grace'
        when x.reconciliation_id is null
          then 'case-audit-layer92-overdue'
        when coalesce(x.layer92_proof_integrity_valid,false)=false
          then 'case-audit-layer92-receipt-invalid'
        when x.reconciliation_state='reconciled'
          then 'case-audit-layer92-covered'
        else x.layer92_reason_code
      end as coverage_reason_code
    from inspected x
  ),
  totals as (
    select
      count(*)::integer as execution_count,
      count(*) filter (where reconciliation_id is not null)::integer as receipt_count,
      count(*) filter (where coverage_state='reconciled')::integer as reconciled_count,
      count(*) filter (where coverage_state='pending')::integer as pending_count,
      count(*) filter (where coverage_state='overdue')::integer as overdue_count,
      count(*) filter (where coverage_state='invalid-reconciliation')::integer
        as invalid_reconciliation_count,
      count(*) filter (where coverage_state='missing-layer87-receipt')::integer
        as missing_layer87_count,
      count(*) filter (where coverage_state='invalid-layer87-receipt')::integer
        as invalid_layer87_count,
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
          'layer91EventId',q.layer91_event_id,
          'targetLayer86EventId',q.target_layer86_event_id,
          'coverageIncidentEventId',q.coverage_incident_event_id,
          'executionRequestedAt',q.requested_at,
          'executionAgeSeconds',q.age_seconds,
          'coverageState',q.coverage_state,
          'reasonCode',q.coverage_reason_code,
          'layer92ReconciliationId',q.reconciliation_id,
          'layer92ReconciliationState',q.reconciliation_state,
          'layer87ReconciliationId',q.layer87_reconciliation_id,
          'layer87ReconciliationState',q.l87_reconciliation_state,
          'layer92ProofIntegrityValid',q.layer92_proof_integrity_valid,
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
    'foundationCaseAuditLayer92ReconciliationCoverage',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',case
      when t.execution_count=0 then 'idle'
      when t.invalid_reconciliation_count>0 then 'invalid'
      when t.overdue_count>0
        or t.missing_layer87_count>0
        or t.invalid_layer87_count>0
        or t.execution_receipt_mismatch_count>0
        or t.policy_drift_count>0
        or t.incident_drift_count>0
        or t.coverage_drift_count>0 then 'gap'
      when t.pending_count>0 then 'pending'
      else 'normal'
    end,
    'reasonCode',case
      when t.execution_count=0 then 'case-audit-layer92-no-executions'
      when t.invalid_reconciliation_count>0 then 'case-audit-layer92-receipt-invalid'
      when t.overdue_count>0 then 'case-audit-layer92-overdue'
      when t.missing_layer87_count>0 then 'case-audit-layer91-layer87-receipt-missing'
      when t.invalid_layer87_count>0 then 'case-audit-layer91-layer87-receipt-invalid'
      when t.execution_receipt_mismatch_count>0 then 'case-audit-layer91-receipt-mismatch'
      when t.policy_drift_count>0 then 'case-audit-layer91-policy-drift'
      when t.incident_drift_count>0 then 'case-audit-layer91-incident-drift'
      when t.coverage_drift_count>0 then 'case-audit-layer91-coverage-drift'
      when t.pending_count>0 then 'case-audit-layer92-within-grace'
      else 'case-audit-layer92-covered'
    end,
    'successfulLayer91ExecutionCount',t.execution_count,
    'layer92ReconciliationRequiredCount',t.execution_count,
    'layer92ReconciliationReceiptCount',t.receipt_count,
    'reconciledCount',t.reconciled_count,
    'pendingCount',t.pending_count,
    'overdueCount',t.overdue_count,
    'invalidLayer92ReconciliationCount',t.invalid_reconciliation_count,
    'missingLayer87ReceiptCount',t.missing_layer87_count,
    'invalidLayer87ReceiptCount',t.invalid_layer87_count,
    'executionReceiptMismatchCount',t.execution_receipt_mismatch_count,
    'policyDriftCount',t.policy_drift_count,
    'incidentDriftCount',t.incident_drift_count,
    'coverageDriftCount',t.coverage_drift_count,
    'problemCount',
      t.overdue_count+t.invalid_reconciliation_count+
      t.missing_layer87_count+t.invalid_layer87_count+
      t.execution_receipt_mismatch_count+t.policy_drift_count+
      t.incident_drift_count+t.coverage_drift_count,
    'layer92ReconciliationCoveragePercent',case
      when t.execution_count=0 then 100.00
      else round((100.0*t.receipt_count/t.execution_count)::numeric,2)
    end,
    'healthyLayer92ReconciliationPercent',case
      when t.execution_count=0 then 100.00
      else round((100.0*t.reconciled_count/t.execution_count)::numeric,2)
    end,
    'visibleCount',jsonb_array_length(v.items),
    'hasMore',t.execution_count>jsonb_array_length(v.items),
    'items',v.items,
    'onlySuccessfulLayer91ExecutionsRequireLayer92Reconciliation',true,
    'layer92ProofIntegrityRecomputed',true,
    'linkedLayer87SnapshotRevalidated',true,
    'layer92ReconciliationPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'layer92ReceiptRewritePerformed',false,
    'layer87ReceiptRewritePerformed',false,
    'layer86ReceiptRewritePerformed',false,
    'layer82ReceiptRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  )
  into v_result
  from totals t cross join visible v;

  return v_result;
end;
$layer93_coverage$;

revoke all on function foundation.get_case_audit_layer92_reconciliation_coverage_v1(
  text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer92_reconciliation_coverage_v1(
  text,timestamptz,integer,integer
) to foundation_runtime,service_role;
