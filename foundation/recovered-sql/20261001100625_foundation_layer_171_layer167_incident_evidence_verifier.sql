
create or replace function foundation.verify_case_audit_layer167_incident_evidence_v1(
  p_environment text,
  p_incident_event_id uuid,
  p_coverage jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_incident foundation.case_audit_layer167_coverage_incident_events%rowtype;
  v_coverage_fp text;
  v_incident_fp text;
  v_integrity boolean := false;
  v_current boolean := false;
begin
  if p_environment is null
     or p_incident_event_id is null
     or p_coverage is null
     or jsonb_typeof(p_coverage)<>'object' then
    return jsonb_build_object(
      'verified',false,
      'integrity',false,
      'current',false
    );
  end if;

  select x.* into v_incident
  from foundation.case_audit_layer167_coverage_incident_events x
  where x.event_id=p_incident_event_id
    and x.environment=p_environment;

  if v_incident.event_id is null then
    return jsonb_build_object(
      'verified',false,
      'integrity',false,
      'current',false
    );
  end if;

  v_coverage_fp:=
    foundation.get_case_audit_layer167_coverage_semantic_fingerprint_v1(
      p_coverage
    );

  v_incident_fp:=
    foundation.get_case_audit_layer167_coverage_semantic_fingerprint_v1(
      v_incident.snapshot
    );

  v_integrity:=
    v_incident.evidence_fingerprint is not distinct from v_incident_fp;

  v_current:=
    v_integrity
    and v_incident.event_type in('detected','opened','changed')
    and v_incident.source_state in('gap','invalid')
    and v_incident.source_state is not distinct from p_coverage->>'state'
    and v_incident_fp is not distinct from v_coverage_fp;

  return jsonb_build_object(
    'verified',true,
    'integrity',v_integrity,
    'current',v_current,
    'incidentEventId',v_incident.event_id,
    'incidentEventType',v_incident.event_type,
    'incidentSourceState',v_incident.source_state,
    'incidentSemanticFingerprint',v_incident_fp,
    'coverageSemanticFingerprint',v_coverage_fp
  );
end $$;

revoke all on function foundation.verify_case_audit_layer167_incident_evidence_v1(
  text,uuid,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.verify_case_audit_layer167_incident_evidence_v1(
  text,uuid,jsonb
) to service_role;
