
create view foundation.case_audit_layer162_coverage_rows_v1
with (security_invoker=true)
as
select
  e.event_sequence,
  e.event_id as layer161_event_id,
  e.environment,
  e.target_layer156_event_id,
  e.coverage_incident_event_id,
  e.requested_at,
  r.reconciliation_id,
  r.reconciliation_state,
  r.reason_code,
  r.semantic_admission_validation_sha256,
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
from foundation.case_audit_layer157_reconcile_exec_events e
left join foundation.case_audit_layer161_exec_reconciliations r
  on r.layer161_event_id=e.event_id
where e.event_type='executed';

revoke all on foundation.case_audit_layer162_coverage_rows_v1
from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant select on foundation.case_audit_layer162_coverage_rows_v1
to foundation_runtime,service_role;
