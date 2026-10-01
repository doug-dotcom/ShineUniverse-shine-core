-- Foundation Layer 98: coverage audit for Layer-97 reconciliation.
-- Every successful Layer-96 bounded Layer-92 reconciliation execution requires
-- one immutable Layer-97 reconciliation receipt. Receipt coverage is separate
-- from healthy reconciliation, and Layer-97 proof integrity is recomputed read-only.

create or replace function foundation.get_case_audit_layer97_reconciliation_coverage_v1(
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
as $layer98_coverage$
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
    raise exception 'case-audit-layer97-coverage-input-invalid';
  end if;

  with successful_exec as (
    select
      e.event_sequence,
      e.event_id as layer96_event_id,
      e.environment,
      e.target_layer91_event_id,
      e.coverage_incident_event_id,
      e.action_key,
      e.cause_class,
      e.policy_fingerprint,
      e.reason_code as layer96_reason_code,
      e.action_result as layer96_action_result,
      e.requested_at,
      greatest(
        0,
        floor(extract(epoch from (p_as_of-e.requested_at)))::integer
      ) as age_seconds,
      r.reconciliation_id,
      r.layer92_reconciliation_id,
      r.reconciliation_state,
      r.reason_code as layer97_reason_code,
      r.policy_integrity_valid,
      r.incident_binding_valid,
      r.layer92_proof_integrity_valid,
      r.execution_receipt_matches,
      r.before_coverage_valid,
      r.after_coverage_valid,
      r.layer96_snapshot,
      r.layer92_snapshot,
      r.reconciliation_proof,
      r.reconciliation_proof_sha256,
      r.reconciled_at,
      l92.layer91_event_id as l92_layer91_event_id,
      l92.target_layer86_event_id as l92_target_layer86_event_id,
      l92.layer87_reconciliation_id as l92_layer87_reconciliation_id,
      l92.reconciliation_state as l92_reconciliation_state,
      l92.reason_code as l92_reason_code,
      l92.policy_integrity_valid as l92_policy_integrity_valid,
      l92.incident_binding_valid as l92_incident_binding_valid,
      l92.layer87_proof_integrity_valid as l92_layer87_proof_integrity_valid,
      l92.execution_receipt_matches as l92_execution_receipt_matches,
      l92.before_coverage_valid as l92_before_coverage_valid,
      l92.after_coverage_valid as l92_after_coverage_valid,
      l92.reconciliation_proof_sha256 as l92_reconciliation_proof_sha256,
      l92.reconciled_at as l92_reconciled_at
    from foundation.case_audit_layer92_reconcile_exec_events e
    left join foundation.case_audit_layer96_exec_reconciliations r
      on r.layer96_event_id=e.event_id
    left join foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations l92
      on l92.reconciliation_id=r.layer92_reconciliation_id
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
                'foundationCaseAuditLayer96ExecutionReconciliationProof'
              is not distinct from
                'shine-foundation/case-audit-layer96-execution-reconciliation-proof-v1'
          and x.reconciliation_proof->>'schemaVersion'
              is not distinct from '1.0.0'
          and x.reconciliation_proof->>'reconciliationId'
              is not distinct from x.reconciliation_id::text
          and x.reconciliation_proof->>'layer96EventId'
              is not distinct from x.layer96_event_id::text
          and x.reconciliation_proof->>'environment'
              is not distinct from x.environment
          and x.reconciliation_proof->>'targetLayer91EventId'
              is not distinct from x.target_layer91_event_id::text
          and x.reconciliation_proof->>'layer92ReconciliationId'
              is not distinct from x.layer92_reconciliation_id::text
          and x.reconciliation_proof->>'reconciliationState'
              is not distinct from x.reconciliation_state
          and x.reconciliation_proof->>'reasonCode'
              is not distinct from x.layer97_reason_code
          and x.reconciliation_proof->'policyIntegrityValid'
              is not distinct from to_jsonb(x.policy_integrity_valid)
          and x.reconciliation_proof->'incidentBindingValid'
              is not distinct from to_jsonb(x.incident_binding_valid)
          and nullif(
                x.reconciliation_proof->'layer92ProofIntegrityValid',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.layer92_proof_integrity_valid)
          and nullif(
                x.reconciliation_proof->'executionReceiptMatches',
                'null'::jsonb
              ) is not distinct from to_jsonb(x.execution_receipt_matches)
          and x.reconciliation_proof->'beforeCoverageValid'
              is not distinct from to_jsonb(x.before_coverage_valid)
          and x.reconciliation_proof->'afterCoverageValid'
              is not distinct from to_jsonb(x.after_coverage_valid)
          and x.reconciliation_proof->'layer96ActionResult'
              is not distinct from x.layer96_action_result
          and nullif(
                x.reconciliation_proof->'layer92Receipt',
                'null'::jsonb
              ) is not distinct from x.layer92_snapshot
          and x.reconciliation_proof->'reconciledAt'
              is not distinct from to_jsonb(x.reconciled_at)
          and x.reconciliation_proof->'layer92RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer91RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer87RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer86RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer82RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer81RerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'verificationRerunPerformed'='false'::jsonb
          and x.reconciliation_proof->'evidenceMutationPerformed'='false'::jsonb
          and x.reconciliation_proof->'layer92ReceiptRewritePerformed'='false'::jsonb
          and x.reconciliation_proof->'layer91ReceiptRewritePerformed'='false'::jsonb
          and x.reconciliation_proof->'layer87ReceiptRewritePerformed'='false'::jsonb
          and x.reconciliation_proof->'releaseTruthMutationPerformed'='false'::jsonb
          and x.reconciliation_proof->'incidentHistoryMutationPerformed'='false'::jsonb
          and x.reconciliation_proof->'approvalGranted'='false'::jsonb
          and x.reconciliation_proof->'executionAuthorityGranted'='false'::jsonb
          and x.reconciliation_proof->'mutationPerformed'='false'::jsonb
          and x.layer96_snapshot->>'layer96EventId'
              is not distinct from x.layer96_event_id::text
          and x.layer96_snapshot->>'targetLayer91EventId'
              is not distinct from x.target_layer91_event_id::text
          and x.layer96_snapshot->>'coverageIncidentEventId'
              is not distinct from x.coverage_incident_event_id::text
          and x.layer96_snapshot->>'actionKey'
              is not distinct from x.action_key
          and x.layer96_snapshot->>'causeClass'
              is not distinct from x.cause_class
          and x.layer96_snapshot->>'policyFingerprint'
              is not distinct from x.policy_fingerprint
          and x.layer96_snapshot->>'eventType'
              is not distinct from 'executed'
          and x.layer96_snapshot->>'reasonCode'
              is not distinct from x.layer96_reason_code
          and x.layer96_snapshot->'requestedAt'
              is not distinct from to_jsonb(x.requested_at)
          and (
            (
              x.layer92_reconciliation_id is null
              and x.layer92_snapshot is null
              and x.reconciliation_state='missing-layer92-receipt'
              and x.layer92_proof_integrity_valid is null
              and x.execution_receipt_matches is null
            )
            or
            (
              x.layer92_reconciliation_id is not null
              and x.l92_layer91_event_id is not null
              and x.layer92_snapshot->>'reconciliationId'
                  is not distinct from x.layer92_reconciliation_id::text
              and x.layer92_snapshot->>'layer91EventId'
                  is not distinct from x.l92_layer91_event_id::text
              and x.layer92_snapshot->>'targetLayer86EventId'
                  is not distinct from x.l92_target_layer86_event_id::text
              and x.layer92_snapshot->>'layer87ReconciliationId'
                  is not distinct from x.l92_layer87_reconciliation_id::text
              and x.layer92_snapshot->>'reconciliationState'
                  is not distinct from x.l92_reconciliation_state
              and x.layer92_snapshot->>'reasonCode'
                  is not distinct from x.l92_reason_code
              and x.layer92_snapshot->'policyIntegrityValid'
                  is not distinct from to_jsonb(x.l92_policy_integrity_valid)
              and x.layer92_snapshot->'incidentBindingValid'
                  is not distinct from to_jsonb(x.l92_incident_binding_valid)
              and nullif(
                    x.layer92_snapshot->'layer87ProofIntegrityValid',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l92_layer87_proof_integrity_valid)
              and nullif(
                    x.layer92_snapshot->'executionReceiptMatches',
                    'null'::jsonb
                  ) is not distinct from to_jsonb(x.l92_execution_receipt_matches)
              and x.layer92_snapshot->'beforeCoverageValid'
                  is not distinct from to_jsonb(x.l92_before_coverage_valid)
              and x.layer92_snapshot->'afterCoverageValid'
                  is not distinct from to_jsonb(x.l92_after_coverage_valid)
              and x.layer92_snapshot->>'reconciliationProofSha256'
                  is not distinct from x.l92_reconciliation_proof_sha256
              and x.layer92_snapshot->'reconciledAt'
                  is not distinct from to_jsonb(x.l92_reconciled_at)
            )
          )
          and (
            (
              x.reconciliation_state='reconciled'
              and x.layer92_reconciliation_id is not null
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is true
              and x.layer92_proof_integrity_valid is true
              and x.execution_receipt_matches is true
              and x.before_coverage_valid is true
              and x.after_coverage_valid is true
            )
            or
            (
              x.reconciliation_state='missing-layer92-receipt'
              and x.layer92_reconciliation_id is null
            )
            or
            (
              x.reconciliation_state='invalid-layer92-receipt'
              and x.layer92_reconciliation_id is not null
              and x.layer92_proof_integrity_valid is false
            )
            or
            (
              x.reconciliation_state='execution-receipt-mismatch'
              and x.layer92_reconciliation_id is not null
              and x.layer92_proof_integrity_valid is true
              and x.execution_receipt_matches is false
            )
            or
            (
              x.reconciliation_state='policy-drift'
              and x.layer92_reconciliation_id is not null
              and x.layer92_proof_integrity_valid is true
              and x.policy_integrity_valid is false
            )
            or
            (
              x.reconciliation_state='incident-drift'
              and x.layer92_reconciliation_id is not null
              and x.layer92_proof_integrity_valid is true
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is false
            )
            or
            (
              x.reconciliation_state='coverage-drift'
              and x.layer92_reconciliation_id is not null
              and x.layer92_proof_integrity_valid is true
              and x.policy_integrity_valid is true
              and x.incident_binding_valid is true
              and x.execution_receipt_matches is true
              and (
                x.before_coverage_valid is false
                or x.after_coverage_valid is false
              )
            )
          )
      end as layer97_proof_integrity_valid
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
        when coalesce(x.layer97_proof_integrity_valid,false)=false
          then 'invalid-reconciliation'
        else x.reconciliation_state
      end as coverage_state,
      case
        when x.reconciliation_id is null
             and x.age_seconds<=p_reconciliation_grace_seconds
          then 'case-audit-layer97-within-grace'
        when x.reconciliation_id is null
          then 'case-audit-layer97-overdue'
        when coalesce(x.layer97_proof_integrity_valid,false)=false
          then 'case-audit-layer97-receipt-invalid'
        when x.reconciliation_state='reconciled'
          then 'case-audit-layer97-covered'
        else x.layer97_reason_code
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
      count(*) filter (where coverage_state='missing-layer92-receipt')::integer
        as missing_layer92_count,
      count(*) filter (where coverage_state='invalid-layer92-receipt')::integer
        as invalid_layer92_count,
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
          'layer96EventId',q.layer96_event_id,
          'targetLayer91EventId',q.target_layer91_event_id,
          'coverageIncidentEventId',q.coverage_incident_event_id,
          'executionRequestedAt',q.requested_at,
          'executionAgeSeconds',q.age_seconds,
          'coverageState',q.coverage_state,
          'reasonCode',q.coverage_reason_code,
          'layer97ReconciliationId',q.reconciliation_id,
          'layer97ReconciliationState',q.reconciliation_state,
          'layer92ReconciliationId',q.layer92_reconciliation_id,
          'layer92ReconciliationState',q.l92_reconciliation_state,
          'layer97ProofIntegrityValid',q.layer97_proof_integrity_valid,
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
    'foundationCaseAuditLayer97ReconciliationCoverage',
      'shine-foundation/case-audit-layer97-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',case
      when t.execution_count=0 then 'idle'
      when t.invalid_reconciliation_count>0 then 'invalid'
      when t.overdue_count>0
        or t.missing_layer92_count>0
        or t.invalid_layer92_count>0
        or t.execution_receipt_mismatch_count>0
        or t.policy_drift_count>0
        or t.incident_drift_count>0
        or t.coverage_drift_count>0 then 'gap'
      when t.pending_count>0 then 'pending'
      else 'normal'
    end,
    'reasonCode',case
      when t.execution_count=0 then 'case-audit-layer97-no-executions'
      when t.invalid_reconciliation_count>0 then 'case-audit-layer97-receipt-invalid'
      when t.overdue_count>0 then 'case-audit-layer97-overdue'
      when t.missing_layer92_count>0 then 'case-audit-layer96-layer92-receipt-missing'
      when t.invalid_layer92_count>0 then 'case-audit-layer96-layer92-receipt-invalid'
      when t.execution_receipt_mismatch_count>0 then 'case-audit-layer96-receipt-mismatch'
      when t.policy_drift_count>0 then 'case-audit-layer96-policy-drift'
      when t.incident_drift_count>0 then 'case-audit-layer96-incident-drift'
      when t.coverage_drift_count>0 then 'case-audit-layer96-coverage-drift'
      when t.pending_count>0 then 'case-audit-layer97-within-grace'
      else 'case-audit-layer97-covered'
    end,
    'successfulLayer96ExecutionCount',t.execution_count,
    'layer97ReconciliationRequiredCount',t.execution_count,
    'layer97ReconciliationReceiptCount',t.receipt_count,
    'reconciledCount',t.reconciled_count,
    'pendingCount',t.pending_count,
    'overdueCount',t.overdue_count,
    'invalidLayer97ReconciliationCount',t.invalid_reconciliation_count,
    'missingLayer92ReceiptCount',t.missing_layer92_count,
    'invalidLayer92ReceiptCount',t.invalid_layer92_count,
    'executionReceiptMismatchCount',t.execution_receipt_mismatch_count,
    'policyDriftCount',t.policy_drift_count,
    'incidentDriftCount',t.incident_drift_count,
    'coverageDriftCount',t.coverage_drift_count,
    'problemCount',
      t.overdue_count+t.invalid_reconciliation_count+
      t.missing_layer92_count+t.invalid_layer92_count+
      t.execution_receipt_mismatch_count+t.policy_drift_count+
      t.incident_drift_count+t.coverage_drift_count,
    'layer97ReconciliationCoveragePercent',case
      when t.execution_count=0 then 100.00
      else round((100.0*t.receipt_count/t.execution_count)::numeric,2)
    end,
    'healthyLayer97ReconciliationPercent',case
      when t.execution_count=0 then 100.00
      else round((100.0*t.reconciled_count/t.execution_count)::numeric,2)
    end,
    'visibleCount',jsonb_array_length(v.items),
    'hasMore',t.execution_count>jsonb_array_length(v.items),
    'items',v.items,
    'onlySuccessfulLayer96ExecutionsRequireLayer97Reconciliation',true,
    'layer97ProofIntegrityRecomputed',true,
    'linkedLayer92SnapshotRevalidated',true,
    'layer97ReconciliationPerformed',false,
    'layer96RerunPerformed',false,
    'layer92RerunPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'layer97ReceiptRewritePerformed',false,
    'layer92ReceiptRewritePerformed',false,
    'layer91ReceiptRewritePerformed',false,
    'layer87ReceiptRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  )
  into v_result
  from totals t cross join visible v;

  return v_result;
end;
$layer98_coverage$;

revoke all on function foundation.get_case_audit_layer97_reconciliation_coverage_v1(
  text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer97_reconciliation_coverage_v1(
  text,timestamptz,integer,integer
) to foundation_runtime,service_role;
