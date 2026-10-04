
create or replace function foundation.get_case_audit_layer162_coverage_incident_cause_v1(
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
  v_current foundation.case_audit_layer162_coverage_incident_events%rowtype;
  v_incident_state text := 'normal';
  v_coverage_semantic_fingerprint text;
  v_incident_semantic_fingerprint text;
  v_incident_integrity boolean := true;
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
    raise exception 'case-audit-layer162-response-cause-input-invalid';
  end if;

  v_coverage:=foundation.get_case_audit_layer162_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage_semantic_fingerprint:=
    foundation.get_case_audit_layer162_coverage_semantic_fingerprint_v1(
      v_coverage
    );

  select x.* into v_current
  from foundation.case_audit_layer162_coverage_incident_events x
  where x.incident_key=p_environment||':case_audit_layer162_reconciliation_coverage'
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
      foundation.get_case_audit_layer162_coverage_semantic_fingerprint_v1(
        v_current.snapshot
      );

    v_incident_integrity:=
      v_current.evidence_fingerprint
        is not distinct from v_incident_semantic_fingerprint;
  end if;

  v_incident_current:=
    v_current.event_id is not null
    and v_incident_integrity
    and v_current.source_state is not distinct from v_coverage->>'state'
    and v_incident_semantic_fingerprint
          is not distinct from v_coverage_semantic_fingerprint;

  if v_current.event_id is not null
     and not v_incident_integrity then
    v_cause:='layer164-incident-receipt-integrity';
    v_next:='inspect-layer164-incident-receipt';

  elsif v_incident_state in('watching','critical')
        and not v_incident_current then
    v_cause:='layer164-current-incident-evidence-stale';
    v_next:='refresh-layer164-incident-evidence';

  elsif v_coverage->>'state' in('idle','normal','pending') then
    v_cause:='none';
    v_next:='none';

  elsif coalesce((v_coverage->>'invalidLayer162ReconciliationCount')::integer,0)>0
        or v_coverage->>'state'='invalid' then
    v_cause:='layer162-receipt-integrity';
    v_next:='inspect-layer162-reconciliation-receipt';

  elsif coalesce((v_coverage->>'missingLayer157ReceiptCount')::integer,0)>0 then
    v_cause:='layer157-receipt-missing';
    v_next:='inspect-layer157-reconciliation-receipt';

  elsif coalesce((v_coverage->>'executionReceiptMismatchCount')::integer,0)>0 then
    v_cause:='layer161-execution-receipt-mismatch';
    v_next:='inspect-layer161-execution-receipt';

  elsif coalesce((v_coverage->>'admissionValidationDriftCount')::integer,0)>0 then
    v_cause:='layer161-admission-validation-drift';
    v_next:='inspect-layer161-admission-validation';

  elsif coalesce((v_coverage->>'policyDriftCount')::integer,0)>0 then
    v_cause:='layer160-policy-drift';
    v_next:='inspect-layer160-policy-binding';

  elsif coalesce((v_coverage->>'incidentStateDriftCount')::integer,0)>0 then
    v_cause:='layer161-incident-state-drift';
    v_next:='inspect-layer161-incident-state-binding';

  elsif coalesce((v_coverage->>'incidentBindingDriftCount')::integer,0)>0 then
    v_cause:='layer161-incident-binding-drift';
    v_next:='inspect-layer161-incident-binding';

  elsif coalesce((v_coverage->>'semanticFreshnessDriftCount')::integer,0)>0 then
    v_cause:='layer161-semantic-freshness-drift';
    v_next:='inspect-layer161-semantic-admission-evidence';

  elsif coalesce((v_coverage->>'overdueCount')::integer,0)>0 then
    v_cause:='layer162-reconciliation-omission';
    v_next:='run-independent-layer162-reconciliation';

  else
    v_cause:='layer162-reconciliation-coverage-gap';
    v_next:='inspect-layer163-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer162CoverageIncidentCause',
      'shine-foundation/case-audit-layer162-reconciliation-coverage-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'currentIncidentEventId',v_current.event_id,
    'currentIncidentEventType',v_current.event_type,
    'currentIncidentSourceState',v_current.source_state,
    'incidentEvidenceIntegrity',v_incident_integrity,
    'incidentEvidenceCurrent',v_incident_current,
    'currentIncidentSemanticFingerprint',v_incident_semantic_fingerprint,
    'coverageSemanticFingerprint',v_coverage_semantic_fingerprint,
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

revoke all on function foundation.get_case_audit_layer162_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer162_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer162_coverage_incident_response_v1(
  p_action_key text,
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
  v_cause jsonb;
  v_cause_class text;
  v_incident_state text;
  v_decision text:='deny';
  v_control text:='prohibited';
  v_reason text:='case-audit-layer162-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer162-response-action-invalid';
  end if;

  v_cause:=foundation.get_case_audit_layer162_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_cause_class:=coalesce(v_cause->>'causeClass','unknown');
  v_incident_state:=coalesce(v_cause->>'incidentState','normal');

  if p_action_key in(
    'inspect-layer163-coverage',
    'inspect-layer164-incident-state'
  ) then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-observe';

  elsif p_action_key='inspect-layer164-incident-receipt'
        and v_cause_class='layer164-incident-receipt-integrity' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-layer164-incident-receipt';

  elsif p_action_key='refresh-layer164-incident-evidence'
        and v_cause_class='layer164-current-incident-evidence-stale' then
    v_decision:='admit';
    v_control:='read-only-sentinel-refresh';
    v_reason:='case-audit-layer162-response-refresh-current-incident-evidence';

  elsif p_action_key='inspect-layer162-reconciliation-receipt'
        and v_cause_class='layer162-receipt-integrity' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-layer162-receipt';

  elsif p_action_key='inspect-layer157-reconciliation-receipt'
        and v_cause_class='layer157-receipt-missing' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-layer157-receipt';

  elsif p_action_key='inspect-layer161-execution-receipt'
        and v_cause_class='layer161-execution-receipt-mismatch' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-layer161-receipt';

  elsif p_action_key='inspect-layer161-admission-validation'
        and v_cause_class='layer161-admission-validation-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-admission-validation';

  elsif p_action_key='inspect-layer160-policy-binding'
        and v_cause_class='layer160-policy-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-layer160-policy';

  elsif p_action_key='inspect-layer161-incident-state-binding'
        and v_cause_class='layer161-incident-state-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-incident-state-binding';

  elsif p_action_key='inspect-layer161-incident-binding'
        and v_cause_class='layer161-incident-binding-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-incident-binding';

  elsif p_action_key='inspect-layer161-semantic-admission-evidence'
        and v_cause_class='layer161-semantic-freshness-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer162-response-inspect-semantic-freshness';

  elsif p_action_key='run-independent-layer162-reconciliation'
        and v_cause_class='layer162-reconciliation-omission'
        and v_incident_state in('watching','critical')
        and coalesce((v_cause->>'incidentEvidenceIntegrity')::boolean,false)
        and coalesce((v_cause->>'incidentEvidenceCurrent')::boolean,false) then
    v_decision:='admit';
    v_control:='layer-162-bounded-reconciler';
    v_reason:='case-audit-layer162-response-run-bounded-reconciliation';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer162CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer162-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'incidentEvidenceIntegrity',v_cause->'incidentEvidenceIntegrity',
    'incidentEvidenceCurrent',v_cause->'incidentEvidenceCurrent',
    'currentIncidentSemanticFingerprint',v_cause->>'currentIncidentSemanticFingerprint',
    'coverageSemanticFingerprint',v_cause->>'coverageSemanticFingerprint',
    'actionKey',p_action_key,
    'causeClass',v_cause_class,
    'decision',v_decision,
    'requiredControl',v_control,
    'reasonCode',v_reason,
    'authorityExpansion',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'upstreamRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'executesAction',false,
    'cause',v_cause
  );
end $$;

revoke all on function foundation.evaluate_case_audit_layer162_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.evaluate_case_audit_layer162_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;
