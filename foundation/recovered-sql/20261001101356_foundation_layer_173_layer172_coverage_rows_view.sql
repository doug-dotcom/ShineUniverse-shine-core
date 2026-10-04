
create view foundation.case_audit_layer172_coverage_rows_v1
with (security_invoker=true)
as
select
  e.event_sequence,
  e.event_id as layer171_event_id,
  e.environment,
  e.target_layer166_event_id,
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
    when encode(
      extensions.digest(convert_to(r.reconciliation_proof::text,'UTF8'),'sha256'),
      'hex'
    ) is distinct from r.reconciliation_proof_sha256 then 'invalid-reconciliation'
    else r.reconciliation_state
  end as receipt_state
from foundation.case_audit_layer167_reconcile_exec_events e
left join foundation.case_audit_layer171_exec_reconciliations r
  on r.layer171_event_id=e.event_id
where e.event_type='executed';
