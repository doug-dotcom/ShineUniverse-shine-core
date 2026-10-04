
create or replace function foundation.get_case_audit_layer147_reconciliation_coverage_v1(
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
  v_total int;
  v_receipts int;
  v_healthy int;
  v_pending int;
  v_overdue int;
  v_invalid int;
  v_missing142 int;
  v_mismatch int;
  v_policy int;
  v_state_drift int;
  v_binding_drift int;
begin
  select
    count(*)::int,
    count(*) filter(where reconciliation_id is not null)::int,
    count(*) filter(where receipt_state='reconciled')::int,
    count(*) filter(where receipt_state='missing'
      and extract(epoch from (p_as_of-requested_at))<=p_reconciliation_grace_seconds)::int,
    count(*) filter(where receipt_state='missing'
      and extract(epoch from (p_as_of-requested_at))>p_reconciliation_grace_seconds)::int,
    count(*) filter(where receipt_state='invalid-reconciliation')::int,
    count(*) filter(where receipt_state='missing-layer142-receipt')::int,
    count(*) filter(where receipt_state='execution-receipt-mismatch')::int,
    count(*) filter(where receipt_state='policy-drift')::int,
    count(*) filter(where receipt_state='incident-state-drift')::int,
    count(*) filter(where receipt_state='incident-binding-drift')::int
  into
    v_total,v_receipts,v_healthy,v_pending,v_overdue,v_invalid,
    v_missing142,v_mismatch,v_policy,v_state_drift,v_binding_drift
  from foundation.case_audit_layer147_coverage_rows_v1
  where environment=p_environment and requested_at<=p_as_of;

  return jsonb_build_object(
    'foundationCaseAuditLayer147ReconciliationCoverage',
      'shine-foundation/case-audit-layer147-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',case
      when v_total=0 then 'idle'
      when v_invalid>0 then 'invalid'
      when v_overdue+v_missing142+v_mismatch+v_policy+v_state_drift+v_binding_drift>0 then 'gap'
      when v_pending>0 then 'pending'
      else 'normal'
    end,
    'successfulLayer146ExecutionCount',v_total,
    'layer147ReconciliationReceiptCount',v_receipts,
    'reconciledCount',v_healthy,
    'pendingCount',v_pending,
    'overdueCount',v_overdue,
    'invalidLayer147ReconciliationCount',v_invalid,
    'missingLayer142ReceiptCount',v_missing142,
    'executionReceiptMismatchCount',v_mismatch,
    'policyDriftCount',v_policy,
    'incidentStateDriftCount',v_state_drift,
    'incidentBindingDriftCount',v_binding_drift,
    'problemCount',v_overdue+v_invalid+v_missing142+v_mismatch+v_policy+v_state_drift+v_binding_drift,
    'layer147ReconciliationCoveragePercent',
      case when v_total=0 then 100.00 else round((100.0*v_receipts/v_total)::numeric,2) end,
    'healthyLayer147ReconciliationPercent',
      case when v_total=0 then 100.00 else round((100.0*v_healthy/v_total)::numeric,2) end,
    'layer147ProofIntegrityRecomputed',true,
    'incidentStateDriftIncluded',true,
    'incidentBindingDriftIncluded',true,
    'mutationPerformed',false
  );
end $$;

revoke all on function foundation.get_case_audit_layer147_reconciliation_coverage_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer147_reconciliation_coverage_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
