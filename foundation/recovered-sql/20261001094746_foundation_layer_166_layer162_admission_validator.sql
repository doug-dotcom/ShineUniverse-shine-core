
create or replace function foundation.validate_case_audit_layer162_reconciliation_admission_v1(
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
  v_decision jsonb;
  v_coverage jsonb;
  v_verify jsonb;
  v_incident_id uuid;
  v_admitted boolean := false;
begin
  v_decision:=foundation.evaluate_case_audit_layer162_coverage_incident_response_v1(
    'run-independent-layer162-reconciliation',
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage:=foundation.get_case_audit_layer162_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  begin
    v_incident_id:=nullif(v_decision#>>'{cause,currentIncidentEventId}','')::uuid;
  exception when invalid_text_representation then
    v_incident_id:=null;
  end;

  v_verify:=foundation.verify_case_audit_layer162_incident_evidence_v1(
    p_environment,v_incident_id,v_coverage
  );

  v_admitted:=
    v_decision->>'decision'='admit'
    and v_decision->>'requiredControl'='layer-162-bounded-reconciler'
    and v_decision->>'causeClass'='layer162-reconciliation-omission'
    and v_decision->>'incidentState' in('watching','critical')
    and coalesce((v_verify->>'verified')::boolean,false)
    and coalesce((v_verify->>'integrity')::boolean,false)
    and coalesce((v_verify->>'current')::boolean,false);

  return jsonb_build_object(
    'foundationCaseAuditLayer162ReconciliationAdmissionValidation',
      'shine-foundation/case-audit-layer162-reconciliation-admission-validation-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'validatedAt',p_as_of,
    'admitted',v_admitted,
    'incidentEventId',v_incident_id,
    'incidentState',v_decision->>'incidentState',
    'incidentEvidenceIntegrity',v_verify->'integrity',
    'incidentEvidenceCurrent',v_verify->'current',
    'incidentSemanticFingerprint',v_verify->>'incidentSemanticFingerprint',
    'coverageSemanticFingerprint',v_verify->>'coverageSemanticFingerprint',
    'causeClass',v_decision->>'causeClass',
    'decision',v_decision
  );
end $$;

revoke all on function foundation.validate_case_audit_layer162_reconciliation_admission_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.validate_case_audit_layer162_reconciliation_admission_v1(
  text,timestamptz,integer
) to service_role;
