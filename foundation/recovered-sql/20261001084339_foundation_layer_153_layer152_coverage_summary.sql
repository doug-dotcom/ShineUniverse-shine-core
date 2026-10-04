
create or replace function foundation.get_case_audit_layer152_reconciliation_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_total integer;
  v_receipts integer;
  v_healthy integer;
  v_pending integer;
  v_overdue integer;
  v_invalid integer;
  v_missing147 integer;
  v_mismatch integer;
  v_policy integer;
  v_state_drift integer;
  v_binding_drift integer;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600 then
    raise exception 'case-audit-layer152-coverage-input-invalid';
  end if;

  select
    count(*)::integer,
    count(*) filter(where reconciliation_id is not null)::integer,
    count(*) filter(where receipt_state='reconciled')::integer,
    count(*) filter(
      where receipt_state='missing'
      and extract(epoch from(p_as_of-requested_at))<=p_reconciliation_grace_seconds
    )::integer,
    count(*) filter(
      where receipt_state='missing'
      and extract(epoch from(p_as_of-requested_at))>p_reconciliation_grace_seconds
    )::integer,
    count(*) filter(where receipt_state='invalid-reconciliation')::integer,
    count(*) filter(where receipt_state='missing-layer147-receipt')::integer,
    count(*) filter(where receipt_state='execution-receipt-mismatch')::integer,
    count(*) filter(where receipt_state='policy-drift')::integer,
    count(*) filter(where receipt_state='incident-state-drift')::integer,
    count(*) filter(where receipt_state='incident-binding-drift')::integer
  into
    v_total,v_receipts,v_healthy,v_pending,v_overdue,v_invalid,
    v_missing147,v_mismatch,v_policy,v_state_drift,v_binding_drift
  from foundation.case_audit_layer152_coverage_rows_v1
  where environment=p_environment
    and requested_at<=p_as_of;

  return jsonb_build_object(
    'foundationCaseAuditLayer152ReconciliationCoverage',
      'shine-foundation/case-audit-layer152-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',case
      when v_total=0 then 'idle'
      when v_invalid>0 then 'invalid'
      when v_overdue+v_missing147+v_mismatch+v_policy+v_state_drift+v_binding_drift>0 then 'gap'
      when v_pending>0 then 'pending'
      else 'normal'
    end,
    'reasonCode',case
      when v_total=0 then 'case-audit-layer152-no-executions'
      when v_invalid>0 then 'case-audit-layer152-receipt-invalid'
      when v_overdue>0 then 'case-audit-layer152-overdue'
      when v_missing147>0 then 'case-audit-layer151-layer147-receipt-missing'
      when v_mismatch>0 then 'case-audit-layer151-receipt-mismatch'
      when v_policy>0 then 'case-audit-layer151-policy-drift'
      when v_state_drift>0 then 'case-audit-layer151-incident-state-drift'
      when v_binding_drift>0 then 'case-audit-layer151-incident-binding-drift'
      when v_pending>0 then 'case-audit-layer152-within-grace'
      else 'case-audit-layer152-covered'
    end,
    'successfulLayer151ExecutionCount',v_total,
    'layer152ReconciliationRequiredCount',v_total,
    'layer152ReconciliationReceiptCount',v_receipts,
    'reconciledCount',v_healthy,
    'pendingCount',v_pending,
    'overdueCount',v_overdue,
    'invalidLayer152ReconciliationCount',v_invalid,
    'missingLayer147ReceiptCount',v_missing147,
    'executionReceiptMismatchCount',v_mismatch,
    'policyDriftCount',v_policy,
    'incidentStateDriftCount',v_state_drift,
    'incidentBindingDriftCount',v_binding_drift,
    'problemCount',v_overdue+v_invalid+v_missing147+v_mismatch+v_policy+v_state_drift+v_binding_drift,
    'layer152ReconciliationCoveragePercent',
      case when v_total=0 then 100.00 else round((100.0*v_receipts/v_total)::numeric,2) end,
    'healthyLayer152ReconciliationPercent',
      case when v_total=0 then 100.00 else round((100.0*v_healthy/v_total)::numeric,2) end,
    'layer152ProofIntegrityRecomputed',true,
    'incidentStateDriftIncluded',true,
    'incidentBindingDriftIncluded',true,
    'layer152ReconciliationPerformed',false,
    'upstreamRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end $$;

revoke all on function foundation.get_case_audit_layer152_reconciliation_coverage_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer152_reconciliation_coverage_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
