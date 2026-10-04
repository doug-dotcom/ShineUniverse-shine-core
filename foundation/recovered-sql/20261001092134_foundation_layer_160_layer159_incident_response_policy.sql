
create or replace function foundation.evaluate_case_audit_layer157_coverage_incident_response_v1(
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
  v_reason text:='case-audit-layer157-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer157-response-action-invalid';
  end if;

  v_cause:=foundation.get_case_audit_layer157_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_cause_class:=coalesce(v_cause->>'causeClass','unknown');
  v_incident_state:=coalesce(v_cause->>'incidentState','normal');

  if p_action_key in(
    'inspect-layer158-coverage',
    'inspect-layer159-incident-state'
  ) then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-observe';

  elsif p_action_key='inspect-layer157-reconciliation-receipt'
        and v_cause_class='layer157-receipt-integrity' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-layer157-receipt';

  elsif p_action_key='inspect-layer152-reconciliation-receipt'
        and v_cause_class='layer152-receipt-missing' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-layer152-receipt';

  elsif p_action_key='inspect-layer156-execution-receipt'
        and v_cause_class='layer156-execution-receipt-mismatch' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-layer156-receipt';

  elsif p_action_key='inspect-layer156-admission-validation'
        and v_cause_class='layer156-admission-validation-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-admission-validation';

  elsif p_action_key='inspect-layer155-policy-binding'
        and v_cause_class='layer155-policy-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-layer155-policy';

  elsif p_action_key='inspect-layer156-incident-state-binding'
        and v_cause_class='layer156-incident-state-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-incident-state-binding';

  elsif p_action_key='inspect-layer156-incident-binding'
        and v_cause_class='layer156-incident-binding-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-incident-binding';

  elsif p_action_key='inspect-layer156-admission-evidence'
        and v_cause_class='layer156-execution-incident-evidence-stale' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer157-response-inspect-stale-execution-evidence';

  elsif p_action_key='refresh-layer159-incident-evidence'
        and v_cause_class='layer159-current-incident-evidence-stale' then
    v_decision:='admit';
    v_control:='read-only-sentinel-refresh';
    v_reason:='case-audit-layer157-response-refresh-current-incident-evidence';

  elsif p_action_key='run-independent-layer157-reconciliation'
        and v_cause_class='layer157-reconciliation-omission'
        and v_incident_state in('watching','critical')
        and coalesce((v_cause->>'incidentEvidenceCurrent')::boolean,false) then
    v_decision:='admit';
    v_control:='layer-157-bounded-reconciler';
    v_reason:='case-audit-layer157-response-run-bounded-reconciliation';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer157CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer157-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
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

revoke all on function foundation.evaluate_case_audit_layer157_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.evaluate_case_audit_layer157_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;
