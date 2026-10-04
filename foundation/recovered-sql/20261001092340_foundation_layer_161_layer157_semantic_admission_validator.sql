
create or replace function foundation.validate_case_audit_layer157_reconciliation_admission_v1(
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
  v_incident foundation.case_audit_layer157_coverage_incident_events%rowtype;
  v_incident_id uuid;
  v_coverage_semantic_fingerprint text;
  v_incident_semantic_fingerprint text;
  v_admitted boolean := false;
begin
  v_decision:=foundation.evaluate_case_audit_layer157_coverage_incident_response_v1(
    'run-independent-layer157-reconciliation',
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage:=foundation.get_case_audit_layer157_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage_semantic_fingerprint:=
    foundation.get_case_audit_layer157_coverage_semantic_fingerprint_v1(v_coverage);

  begin
    v_incident_id:=nullif(v_decision#>>'{cause,currentIncidentEventId}','')::uuid;
  exception when invalid_text_representation then
    v_incident_id:=null;
  end;

  if v_incident_id is not null then
    select x.* into v_incident
    from foundation.case_audit_layer157_coverage_incident_events x
    where x.event_id=v_incident_id
      and x.environment=p_environment;
  end if;

  if v_incident.event_id is not null then
    v_incident_semantic_fingerprint:=
      foundation.get_case_audit_layer157_coverage_semantic_fingerprint_v1(
        v_incident.snapshot
      );
  end if;

  v_admitted:=
    v_decision->>'decision'='admit'
    and v_decision->>'requiredControl'='layer-157-bounded-reconciler'
    and v_decision->>'causeClass'='layer157-reconciliation-omission'
    and v_decision->>'incidentState' in('watching','critical')
    and coalesce((v_decision->>'incidentEvidenceCurrent')::boolean,false)
    and v_incident.event_id is not null
    and v_incident.event_type in('detected','opened','changed')
    and v_incident.source_state is not distinct from v_coverage->>'state'
    and v_incident_semantic_fingerprint is not distinct from v_coverage_semantic_fingerprint
    and v_decision#>>'{cause,currentIncidentSemanticFingerprint}'
         is not distinct from v_incident_semantic_fingerprint
    and v_decision#>>'{cause,coverageSemanticFingerprint}'
         is not distinct from v_coverage_semantic_fingerprint
    and coalesce(v_decision->>'authorityExpansion','true')='false'
    and coalesce(v_decision->>'automaticReconciliationAllowed','true')='false'
    and coalesce(v_decision->>'automaticRepairAllowed','true')='false'
    and coalesce(v_decision->>'upstreamRerunAllowed','true')='false'
    and coalesce(v_decision->>'executesAction','true')='false';

  return jsonb_build_object(
    'foundationCaseAuditLayer157ReconciliationAdmissionValidation',
      'shine-foundation/case-audit-layer157-reconciliation-admission-validation-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'validatedAt',p_as_of,
    'admitted',v_admitted,
    'incidentEventId',v_incident_id,
    'incidentEventType',v_incident.event_type,
    'incidentState',v_decision->>'incidentState',
    'incidentEvidenceCurrent',v_decision->'incidentEvidenceCurrent',
    'incidentSemanticFingerprint',v_incident_semantic_fingerprint,
    'coverageSemanticFingerprint',v_coverage_semantic_fingerprint,
    'coverageState',v_coverage->>'state',
    'causeClass',v_decision->>'causeClass',
    'decision',v_decision
  );
end $$;

revoke all on function foundation.validate_case_audit_layer157_reconciliation_admission_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.validate_case_audit_layer157_reconciliation_admission_v1(
  text,timestamptz,integer
) to service_role;
