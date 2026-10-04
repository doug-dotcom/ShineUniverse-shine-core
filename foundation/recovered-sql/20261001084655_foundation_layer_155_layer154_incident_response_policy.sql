
create or replace function foundation.get_case_audit_layer152_coverage_incident_cause_v1(
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
  v_current foundation.case_audit_layer152_coverage_incident_events%rowtype;
  v_incident_state text := 'normal';
  v_coverage_fingerprint text;
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
    raise exception 'case-audit-layer152-response-cause-input-invalid';
  end if;

  v_coverage:=foundation.get_case_audit_layer152_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage_fingerprint:=encode(
    extensions.digest(convert_to(v_coverage::text,'UTF8'),'sha256'),
    'hex'
  );

  select x.* into v_current
  from foundation.case_audit_layer152_coverage_incident_events x
  where x.incident_key=p_environment||':case_audit_layer152_reconciliation_coverage'
    and x.occurred_at<=p_as_of
  order by x.occurred_at desc,x.event_sequence desc
  limit 1;

  v_incident_state:=case
    when v_current.event_id is null then 'normal'
    when v_current.event_type='detected' then 'watching'
    when v_current.event_type in('opened','changed') then 'critical'
    else 'normal'
  end;

  v_incident_current:=
    v_current.event_id is not null
    and v_current.evidence_fingerprint is not distinct from v_coverage_fingerprint
    and v_current.source_state is not distinct from v_coverage->>'state';

  if v_coverage->>'state' in('idle','normal','pending') then
    v_cause:='none';
    v_next:='none';

  elsif coalesce((v_coverage->>'invalidLayer152ReconciliationCount')::integer,0)>0
        or v_coverage->>'state'='invalid' then
    v_cause:='layer152-receipt-integrity';
    v_next:='inspect-layer152-reconciliation-receipt';

  elsif coalesce((v_coverage->>'missingLayer147ReceiptCount')::integer,0)>0 then
    v_cause:='layer147-receipt-missing';
    v_next:='inspect-layer147-reconciliation-receipt';

  elsif coalesce((v_coverage->>'executionReceiptMismatchCount')::integer,0)>0 then
    v_cause:='layer151-execution-receipt-mismatch';
    v_next:='inspect-layer151-execution-receipt';

  elsif coalesce((v_coverage->>'policyDriftCount')::integer,0)>0 then
    v_cause:='layer150-policy-drift';
    v_next:='inspect-layer150-policy-binding';

  elsif coalesce((v_coverage->>'incidentStateDriftCount')::integer,0)>0 then
    v_cause:='layer151-incident-state-drift';
    v_next:='inspect-layer151-incident-state-binding';

  elsif coalesce((v_coverage->>'incidentBindingDriftCount')::integer,0)>0 then
    v_cause:='layer151-incident-binding-drift';
    v_next:='inspect-layer151-incident-binding';

  elsif v_incident_state in('watching','critical')
        and not v_incident_current then
    v_cause:='layer154-incident-evidence-stale';
    v_next:='refresh-layer154-incident-evidence';

  elsif coalesce((v_coverage->>'overdueCount')::integer,0)>0 then
    v_cause:='layer152-reconciliation-omission';
    v_next:='run-independent-layer152-reconciliation';

  else
    v_cause:='layer152-reconciliation-coverage-gap';
    v_next:='inspect-layer153-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer152CoverageIncidentCause',
      'shine-foundation/case-audit-layer152-reconciliation-coverage-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'currentIncidentEventId',v_current.event_id,
    'currentIncidentEventType',v_current.event_type,
    'currentIncidentSourceState',v_current.source_state,
    'incidentEvidenceFingerprint',v_current.evidence_fingerprint,
    'coverageEvidenceFingerprint',v_coverage_fingerprint,
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

revoke all on function foundation.get_case_audit_layer152_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer152_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer152_coverage_incident_response_v1(
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
  v_reason text:='case-audit-layer152-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer152-response-action-invalid';
  end if;

  v_cause:=foundation.get_case_audit_layer152_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_cause_class:=coalesce(v_cause->>'causeClass','unknown');
  v_incident_state:=coalesce(v_cause->>'incidentState','normal');

  if p_action_key in(
    'inspect-layer153-coverage',
    'inspect-layer154-incident-state'
  ) then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer152-response-observe';

  elsif p_action_key='inspect-layer152-reconciliation-receipt'
        and v_cause_class='layer152-receipt-integrity' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer152-response-inspect-layer152-receipt';

  elsif p_action_key='inspect-layer147-reconciliation-receipt'
        and v_cause_class='layer147-receipt-missing' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer152-response-inspect-layer147-receipt';

  elsif p_action_key='inspect-layer151-execution-receipt'
        and v_cause_class='layer151-execution-receipt-mismatch' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer152-response-inspect-layer151-receipt';

  elsif p_action_key='inspect-layer150-policy-binding'
        and v_cause_class='layer150-policy-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer152-response-inspect-layer150-policy';

  elsif p_action_key='inspect-layer151-incident-state-binding'
        and v_cause_class='layer151-incident-state-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer152-response-inspect-incident-state-binding';

  elsif p_action_key='inspect-layer151-incident-binding'
        and v_cause_class='layer151-incident-binding-drift' then
    v_decision:='admit';
    v_control:='read-only';
    v_reason:='case-audit-layer152-response-inspect-incident-binding';

  elsif p_action_key='refresh-layer154-incident-evidence'
        and v_cause_class='layer154-incident-evidence-stale' then
    v_decision:='admit';
    v_control:='read-only-sentinel-refresh';
    v_reason:='case-audit-layer152-response-refresh-incident-evidence';

  elsif p_action_key='run-independent-layer152-reconciliation'
        and v_cause_class='layer152-reconciliation-omission'
        and v_incident_state in('watching','critical')
        and coalesce((v_cause->>'incidentEvidenceCurrent')::boolean,false) then
    v_decision:='admit';
    v_control:='layer-152-bounded-reconciler';
    v_reason:='case-audit-layer152-response-run-bounded-reconciliation';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer152CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer152-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'incidentEvidenceCurrent',v_cause->'incidentEvidenceCurrent',
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

revoke all on function foundation.evaluate_case_audit_layer152_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.evaluate_case_audit_layer152_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;
