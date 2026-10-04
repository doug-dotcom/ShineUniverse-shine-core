
create or replace function foundation.get_case_audit_layer157_coverage_incident_cause_v1(
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
  v_coverage jsonb;
  v_current foundation.case_audit_layer157_coverage_incident_events%rowtype;
  v_incident_state text := 'normal';
  v_current_semantic_fingerprint text;
  v_incident_semantic_fingerprint text;
  v_incident_current boolean := false;
  v_cause text;
  v_next text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600 then
    raise exception 'case-audit-layer157-response-cause-input-invalid';
  end if;

  v_coverage:=foundation.get_case_audit_layer157_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_current_semantic_fingerprint:=
    foundation.get_case_audit_layer157_coverage_semantic_fingerprint_v1(v_coverage);

  select x.* into v_current
  from foundation.case_audit_layer157_coverage_incident_events x
  where x.incident_key=p_environment||':case_audit_layer157_reconciliation_coverage'
    and x.occurred_at<=p_as_of
  order by x.occurred_at desc,x.event_sequence desc
  limit 1;

  v_incident_state:=case
    when v_current.event_id is null then 'normal'
    when v_current.event_type='detected' then 'watching'
    when v_current.event_type in('opened','changed') then 'critical'
    else 'normal'
  end;

  if v_current.event_id is not null then
    v_incident_semantic_fingerprint:=
      foundation.get_case_audit_layer157_coverage_semantic_fingerprint_v1(
        v_current.snapshot
      );
  end if;

  v_incident_current:=
    v_current.event_id is not null
    and v_current.source_state is not distinct from v_coverage->>'state'
    and v_incident_semantic_fingerprint is not distinct from v_current_semantic_fingerprint;

  if v_coverage->>'state' in('idle','normal','pending') then
    v_cause:='none';
    v_next:='none';

  elsif coalesce((v_coverage->>'invalidLayer157ReconciliationCount')::integer,0)>0
        or v_coverage->>'state'='invalid' then
    v_cause:='layer157-receipt-integrity';
    v_next:='inspect-layer157-reconciliation-receipt';

  elsif coalesce((v_coverage->>'missingLayer152ReceiptCount')::integer,0)>0 then
    v_cause:='layer152-receipt-missing';
    v_next:='inspect-layer152-reconciliation-receipt';

  elsif coalesce((v_coverage->>'executionReceiptMismatchCount')::integer,0)>0 then
    v_cause:='layer156-execution-receipt-mismatch';
    v_next:='inspect-layer156-execution-receipt';

  elsif coalesce((v_coverage->>'admissionValidationDriftCount')::integer,0)>0 then
    v_cause:='layer156-admission-validation-drift';
    v_next:='inspect-layer156-admission-validation';

  elsif coalesce((v_coverage->>'policyDriftCount')::integer,0)>0 then
    v_cause:='layer155-policy-drift';
    v_next:='inspect-layer155-policy-binding';

  elsif coalesce((v_coverage->>'incidentStateDriftCount')::integer,0)>0 then
    v_cause:='layer156-incident-state-drift';
    v_next:='inspect-layer156-incident-state-binding';

  elsif coalesce((v_coverage->>'incidentBindingDriftCount')::integer,0)>0 then
    v_cause:='layer156-incident-binding-drift';
    v_next:='inspect-layer156-incident-binding';

  elsif coalesce((v_coverage->>'incidentEvidenceStaleCount')::integer,0)>0 then
    v_cause:='layer156-execution-incident-evidence-stale';
    v_next:='inspect-layer156-admission-evidence';

  elsif v_incident_state in('watching','critical')
        and not v_incident_current then
    v_cause:='layer159-current-incident-evidence-stale';
    v_next:='refresh-layer159-incident-evidence';

  elsif coalesce((v_coverage->>'overdueCount')::integer,0)>0 then
    v_cause:='layer157-reconciliation-omission';
    v_next:='run-independent-layer157-reconciliation';

  else
    v_cause:='layer157-reconciliation-coverage-gap';
    v_next:='inspect-layer158-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer157CoverageIncidentCause',
      'shine-foundation/case-audit-layer157-reconciliation-coverage-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'currentIncidentEventId',v_current.event_id,
    'currentIncidentEventType',v_current.event_type,
    'currentIncidentSourceState',v_current.source_state,
    'currentIncidentSemanticFingerprint',v_incident_semantic_fingerprint,
    'coverageSemanticFingerprint',v_current_semantic_fingerprint,
    'incidentEvidenceCurrent',v_incident_current,
    'coverageState',v_coverage->>'state',
    'causeClass',v_cause,
    'nextEvidenceAction',v_next,
    'coverage',v_coverage,
    'authorityExpansion',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'upstreamRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end $$;

revoke all on function foundation.get_case_audit_layer157_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer157_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
