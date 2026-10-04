
create or replace view foundation.case_audit_layer189_coverage_rows_v1
with (security_invoker=true) as
select e.event_sequence,e.event_id as layer188_event_id,e.environment,e.target_layer182_event_id,e.coverage_incident_event_id,
 e.requested_at,r.reconciliation_id,r.reconciliation_state,r.reason_code,r.admission_validation_sha256,
 r.reconciliation_proof,r.reconciliation_proof_sha256,r.reconciled_at,
 case when r.reconciliation_id is null then 'missing'
      when encode(extensions.digest(convert_to(r.reconciliation_proof::text,'UTF8'),'sha256'),'hex') is distinct from r.reconciliation_proof_sha256 then 'invalid-reconciliation'
      else r.reconciliation_state end receipt_state
from foundation.case_audit_layer183_reconcile_exec_events e
left join foundation.case_audit_layer188_exec_reconciliations r on r.layer188_event_id=e.event_id
where e.event_type='executed';
revoke all on foundation.case_audit_layer189_coverage_rows_v1 from public,anon,authenticated;
grant select on foundation.case_audit_layer189_coverage_rows_v1 to service_role;

create or replace function foundation.get_case_audit_layer189_reconciliation_coverage_v1(
 p_environment text default 'production',p_as_of timestamptz default now(),p_reconciliation_grace_seconds int default 300
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare total int;receipts int;healthy int;pending int;overdue int;invalid int;missing int;mismatch int;admission int;policy int;integrity int;state_drift int;binding int;semantic int;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' or p_as_of is null or p_reconciliation_grace_seconds not between 60 and 3600
 then raise exception 'case-audit-layer189-coverage-input-invalid';end if;
 select count(*)::int,count(*) filter(where reconciliation_id is not null)::int,count(*) filter(where receipt_state='reconciled')::int,
 count(*) filter(where receipt_state='missing' and extract(epoch from(p_as_of-requested_at))<=p_reconciliation_grace_seconds)::int,
 count(*) filter(where receipt_state='missing' and extract(epoch from(p_as_of-requested_at))>p_reconciliation_grace_seconds)::int,
 count(*) filter(where receipt_state='invalid-reconciliation')::int,count(*) filter(where receipt_state='missing-layer183-receipt')::int,
 count(*) filter(where receipt_state='execution-receipt-mismatch')::int,count(*) filter(where receipt_state='admission-validation-drift')::int,
 count(*) filter(where receipt_state='policy-drift')::int,count(*) filter(where receipt_state='incident-integrity-drift')::int,
 count(*) filter(where receipt_state='incident-state-drift')::int,count(*) filter(where receipt_state='incident-binding-drift')::int,
 count(*) filter(where receipt_state='semantic-currentness-drift')::int
 into total,receipts,healthy,pending,overdue,invalid,missing,mismatch,admission,policy,integrity,state_drift,binding,semantic
 from foundation.case_audit_layer189_coverage_rows_v1 where environment=p_environment and requested_at<=p_as_of;
 return jsonb_build_object('foundationCaseAuditLayer189ReconciliationCoverage','shine-foundation/case-audit-layer189-reconciliation-coverage-v1',
 'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
 'state',case when total=0 then 'idle' when invalid>0 then 'invalid'
 when overdue+missing+mismatch+admission+policy+integrity+state_drift+binding+semantic>0 then 'gap' when pending>0 then 'pending' else 'normal' end,
 'successfulLayer188ExecutionCount',total,'layer189ReconciliationRequiredCount',total,'layer189ReconciliationReceiptCount',receipts,
 'reconciledCount',healthy,'pendingCount',pending,'overdueCount',overdue,'invalidLayer189ReconciliationCount',invalid,
 'missingLayer183ReceiptCount',missing,'executionReceiptMismatchCount',mismatch,'admissionValidationDriftCount',admission,
 'policyDriftCount',policy,'incidentIntegrityDriftCount',integrity,'incidentStateDriftCount',state_drift,
 'incidentBindingDriftCount',binding,'semanticCurrentnessDriftCount',semantic,
 'problemCount',overdue+invalid+missing+mismatch+admission+policy+integrity+state_drift+binding+semantic,
 'layer189ReconciliationCoveragePercent',case when total=0 then 100.00 else round((100.0*receipts/total)::numeric,2) end,
 'healthyLayer189ReconciliationPercent',case when total=0 then 100.00 else round((100.0*healthy/total)::numeric,2) end,'mutationPerformed',false);
end $$;
revoke execute on function foundation.get_case_audit_layer189_reconciliation_coverage_v1(text,timestamptz,int) from public,anon,authenticated;
grant execute on function foundation.get_case_audit_layer189_reconciliation_coverage_v1(text,timestamptz,int) to service_role;
