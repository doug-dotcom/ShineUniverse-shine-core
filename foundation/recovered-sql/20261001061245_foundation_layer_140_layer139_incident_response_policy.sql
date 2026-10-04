
create or replace function foundation.get_case_audit_layer137_coverage_incident_cause_v1(
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
  c jsonb;
  current_incident foundation.case_audit_layer137_coverage_incident_events%rowtype;
  incident_state text := 'normal';
  cause text;
  nxt text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600 then
    raise exception 'case-audit-layer137-response-cause-input-invalid';
  end if;

  c:=foundation.get_case_audit_layer137_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds,100
  );

  select * into current_incident
  from foundation.case_audit_layer137_coverage_incident_events
  where incident_key=p_environment||':case_audit_layer137_reconciliation_coverage'
    and occurred_at<=p_as_of
  order by occurred_at desc,event_sequence desc
  limit 1;

  incident_state:=case
    when current_incident.event_id is null then 'normal'
    when current_incident.event_type='detected' then 'watching'
    when current_incident.event_type in('opened','changed') then 'critical'
    else 'normal'
  end;

  if c->>'state' in('idle','normal','pending') then
    cause:='none';
    nxt:='none';
  elsif coalesce((c->>'invalidLayer137ReconciliationCount')::int,0)>0
        or c->>'state'='invalid' then
    cause:='layer137-receipt-integrity';
    nxt:='inspect-layer137-reconciliation-receipt';
  elsif coalesce((c->>'missingLayer132ReceiptCount')::int,0)>0 then
    cause:='layer132-receipt-missing';
    nxt:='inspect-layer132-reconciliation-receipt';
  elsif coalesce((c->>'executionReceiptMismatchCount')::int,0)>0 then
    cause:='layer136-execution-receipt-mismatch';
    nxt:='inspect-layer136-execution-receipt';
  elsif coalesce((c->>'policyDriftCount')::int,0)>0 then
    cause:='layer135-policy-drift';
    nxt:='inspect-layer135-policy-binding';
  elsif coalesce((c->>'overdueCount')::int,0)>0 then
    cause:='layer137-reconciliation-omission';
    nxt:='run-independent-layer137-reconciliation';
  else
    cause:='layer137-reconciliation-coverage-gap';
    nxt:='inspect-layer138-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer137CoverageIncidentCause',
      'shine-foundation/case-audit-layer137-reconciliation-coverage-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',incident_state,
    'currentIncidentEventId',current_incident.event_id,
    'currentIncidentEventType',current_incident.event_type,
    'currentIncidentSourceState',current_incident.source_state,
    'coverageState',c->>'state',
    'coverageReasonCode',c->>'reasonCode',
    'causeClass',cause,
    'nextEvidenceAction',nxt,
    'coverage',c,
    'authorityExpansion',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'upstreamRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end $$;

revoke all on function foundation.get_case_audit_layer137_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer137_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer137_coverage_incident_response_v1(
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
  c jsonb;
  cause text;
  incident_state text;
  decision text:='deny';
  control text:='prohibited';
  reason text:='case-audit-layer137-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer137-response-action-invalid';
  end if;

  c:=foundation.get_case_audit_layer137_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  cause:=coalesce(c->>'causeClass','unknown');
  incident_state:=coalesce(c->>'incidentState','normal');

  if p_action_key in(
    'inspect-layer138-coverage',
    'inspect-layer139-incident-state'
  ) then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer137-response-observe';

  elsif p_action_key='inspect-layer137-reconciliation-receipt'
        and cause='layer137-receipt-integrity' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer137-response-inspect-layer137-receipt';

  elsif p_action_key='inspect-layer132-reconciliation-receipt'
        and cause='layer132-receipt-missing' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer137-response-inspect-layer132-receipt';

  elsif p_action_key='inspect-layer136-execution-receipt'
        and cause='layer136-execution-receipt-mismatch' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer137-response-inspect-layer136-receipt';

  elsif p_action_key='inspect-layer135-policy-binding'
        and cause='layer135-policy-drift' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer137-response-inspect-layer135-policy';

  elsif p_action_key='run-independent-layer137-reconciliation'
        and cause='layer137-reconciliation-omission'
        and incident_state in('watching','critical') then
    decision:='admit';
    control:='layer-137-bounded-reconciler';
    reason:='case-audit-layer137-response-run-bounded-reconciliation';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer137CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer137-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',incident_state,
    'actionKey',p_action_key,
    'causeClass',cause,
    'decision',decision,
    'requiredControl',control,
    'reasonCode',reason,
    'authorityExpansion',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'upstreamRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'executesAction',false,
    'cause',c
  );
end $$;

revoke all on function foundation.evaluate_case_audit_layer137_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;

grant execute on function foundation.evaluate_case_audit_layer137_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;
