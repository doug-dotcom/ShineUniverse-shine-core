
create or replace view foundation.case_audit_layer177_coverage_rows_v1
with (security_invoker=true) as
select
 e.event_sequence,
 e.event_id as layer176_event_id,
 e.environment,
 e.target_layer171_event_id,
 e.coverage_incident_event_id,
 e.requested_at,
 r.reconciliation_id,
 r.reconciliation_state,
 r.reason_code,
 r.admission_validation_sha256,
 r.incident_evidence_integrity,
 r.incident_evidence_current,
 r.coverage_semantic_fingerprint,
 r.incident_semantic_fingerprint,
 r.reconciliation_proof,
 r.reconciliation_proof_sha256,
 r.reconciled_at,
 case
   when r.reconciliation_id is null then 'missing'
   when encode(extensions.digest(convert_to(r.reconciliation_proof::text,'UTF8'),'sha256'),'hex')
        is distinct from r.reconciliation_proof_sha256 then 'invalid-reconciliation'
   else r.reconciliation_state
 end as receipt_state
from foundation.case_audit_layer172_reconcile_exec_events e
left join foundation.case_audit_layer176_exec_reconciliations r
  on r.layer176_event_id=e.event_id
where e.event_type='executed';

revoke all on foundation.case_audit_layer177_coverage_rows_v1 from public, anon, authenticated;
grant select on foundation.case_audit_layer177_coverage_rows_v1 to service_role;

create or replace function foundation.get_case_audit_layer177_reconciliation_coverage_v1(
 p_environment text default 'production',
 p_as_of timestamptz default now(),
 p_reconciliation_grace_seconds integer default 300
) returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare
 v_total integer; v_receipts integer; v_healthy integer; v_pending integer;
 v_overdue integer; v_invalid integer; v_missing172 integer; v_mismatch integer;
 v_admission integer; v_policy integer; v_integrity integer; v_state integer;
 v_binding integer; v_semantic integer;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
 or p_as_of is null or p_reconciliation_grace_seconds is null
 or p_reconciliation_grace_seconds<60 or p_reconciliation_grace_seconds>3600 then
   raise exception 'case-audit-layer177-coverage-input-invalid';
 end if;

 select count(*)::int,
 count(*) filter(where reconciliation_id is not null)::int,
 count(*) filter(where receipt_state='reconciled')::int,
 count(*) filter(where receipt_state='missing' and extract(epoch from(p_as_of-requested_at))<=p_reconciliation_grace_seconds)::int,
 count(*) filter(where receipt_state='missing' and extract(epoch from(p_as_of-requested_at))>p_reconciliation_grace_seconds)::int,
 count(*) filter(where receipt_state='invalid-reconciliation')::int,
 count(*) filter(where receipt_state='missing-layer172-receipt')::int,
 count(*) filter(where receipt_state='execution-receipt-mismatch')::int,
 count(*) filter(where receipt_state='admission-validation-drift')::int,
 count(*) filter(where receipt_state='policy-drift')::int,
 count(*) filter(where receipt_state='incident-integrity-drift')::int,
 count(*) filter(where receipt_state='incident-state-drift')::int,
 count(*) filter(where receipt_state='incident-binding-drift')::int,
 count(*) filter(where receipt_state='semantic-currentness-drift')::int
 into v_total,v_receipts,v_healthy,v_pending,v_overdue,v_invalid,v_missing172,
      v_mismatch,v_admission,v_policy,v_integrity,v_state,v_binding,v_semantic
 from foundation.case_audit_layer177_coverage_rows_v1
 where environment=p_environment and requested_at<=p_as_of;

 return jsonb_build_object(
  'foundationCaseAuditLayer177ReconciliationCoverage','shine-foundation/case-audit-layer177-reconciliation-coverage-v1',
  'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
  'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
  'state',case when v_total=0 then 'idle' when v_invalid>0 then 'invalid'
    when v_overdue+v_missing172+v_mismatch+v_admission+v_policy+v_integrity+v_state+v_binding+v_semantic>0 then 'gap'
    when v_pending>0 then 'pending' else 'normal' end,
  'successfulLayer176ExecutionCount',v_total,
  'layer177ReconciliationRequiredCount',v_total,
  'layer177ReconciliationReceiptCount',v_receipts,
  'reconciledCount',v_healthy,'pendingCount',v_pending,'overdueCount',v_overdue,
  'invalidLayer177ReconciliationCount',v_invalid,'missingLayer172ReceiptCount',v_missing172,
  'executionReceiptMismatchCount',v_mismatch,'admissionValidationDriftCount',v_admission,
  'policyDriftCount',v_policy,'incidentIntegrityDriftCount',v_integrity,
  'incidentStateDriftCount',v_state,'incidentBindingDriftCount',v_binding,
  'semanticCurrentnessDriftCount',v_semantic,
  'problemCount',v_overdue+v_invalid+v_missing172+v_mismatch+v_admission+v_policy+v_integrity+v_state+v_binding+v_semantic,
  'layer177ReconciliationCoveragePercent',case when v_total=0 then 100.00 else round((100.0*v_receipts/v_total)::numeric,2) end,
  'healthyLayer177ReconciliationPercent',case when v_total=0 then 100.00 else round((100.0*v_healthy/v_total)::numeric,2) end,
  'mutationPerformed',false
 );
end $$;
revoke all on function foundation.get_case_audit_layer177_reconciliation_coverage_v1(text,timestamptz,integer) from public, anon, authenticated;
grant execute on function foundation.get_case_audit_layer177_reconciliation_coverage_v1(text,timestamptz,integer) to service_role;
