
create or replace function foundation.get_case_audit_layer147_coverage_incident_cause_v1(
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
  current_incident foundation.case_audit_layer147_coverage_incident_events%rowtype;
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
    raise exception 'case-audit-layer147-response-cause-input-invalid';
  end if;

  c:=foundation.get_case_audit_layer147_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  select * into current_incident
  from foundation.case_audit_layer147_coverage_incident_events
  where incident_key=p_environment||':case_audit_layer147_reconciliation_coverage'
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

  elsif coalesce((c->>'invalidLayer147ReconciliationCount')::int,0)>0
        or c->>'state'='invalid' then
    cause:='layer147-receipt-integrity';
    nxt:='inspect-layer147-reconciliation-receipt';

  elsif coalesce((c->>'missingLayer142ReceiptCount')::int,0)>0 then
    cause:='layer142-receipt-missing';
    nxt:='inspect-layer142-reconciliation-receipt';

  elsif coalesce((c->>'executionReceiptMismatchCount')::int,0)>0 then
    cause:='layer146-execution-receipt-mismatch';
    nxt:='inspect-layer146-execution-receipt';

  elsif coalesce((c->>'policyDriftCount')::int,0)>0 then
    cause:='layer145-policy-drift';
    nxt:='inspect-layer145-policy-binding';

  elsif coalesce((c->>'incidentStateDriftCount')::int,0)>0 then
    cause:='layer146-incident-state-drift';
    nxt:='inspect-layer146-incident-state-binding';

  elsif coalesce((c->>'incidentBindingDriftCount')::int,0)>0 then
    cause:='layer146-incident-binding-drift';
    nxt:='inspect-layer146-incident-binding';

  elsif coalesce((c->>'overdueCount')::int,0)>0 then
    cause:='layer147-reconciliation-omission';
    nxt:='run-independent-layer147-reconciliation';

  else
    cause:='layer147-reconciliation-coverage-gap';
    nxt:='inspect-layer148-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer147CoverageIncidentCause',
      'shine-foundation/case-audit-layer147-reconciliation-coverage-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',incident_state,
    'currentIncidentEventId',current_incident.event_id,
    'currentIncidentEventType',current_incident.event_type,
    'coverageState',c->>'state',
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

revoke all on function foundation.get_case_audit_layer147_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer147_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer147_coverage_incident_response_v1(
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
  reason text:='case-audit-layer147-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer147-response-action-invalid';
  end if;

  c:=foundation.get_case_audit_layer147_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  cause:=coalesce(c->>'causeClass','unknown');
  incident_state:=coalesce(c->>'incidentState','normal');

  if p_action_key in(
    'inspect-layer148-coverage',
    'inspect-layer149-incident-state'
  ) then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer147-response-observe';

  elsif p_action_key='inspect-layer147-reconciliation-receipt'
        and cause='layer147-receipt-integrity' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer147-response-inspect-layer147-receipt';

  elsif p_action_key='inspect-layer142-reconciliation-receipt'
        and cause='layer142-receipt-missing' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer147-response-inspect-layer142-receipt';

  elsif p_action_key='inspect-layer146-execution-receipt'
        and cause='layer146-execution-receipt-mismatch' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer147-response-inspect-layer146-receipt';

  elsif p_action_key='inspect-layer145-policy-binding'
        and cause='layer145-policy-drift' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer147-response-inspect-layer145-policy';

  elsif p_action_key='inspect-layer146-incident-state-binding'
        and cause='layer146-incident-state-drift' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer147-response-inspect-incident-state-binding';

  elsif p_action_key='inspect-layer146-incident-binding'
        and cause='layer146-incident-binding-drift' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer147-response-inspect-incident-binding';

  elsif p_action_key='run-independent-layer147-reconciliation'
        and cause='layer147-reconciliation-omission'
        and incident_state in('watching','critical') then
    decision:='admit';
    control:='layer-147-bounded-reconciler';
    reason:='case-audit-layer147-response-run-bounded-reconciliation';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer147CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer147-reconciliation-coverage-incident-response-decision-v1',
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

revoke all on function foundation.evaluate_case_audit_layer147_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.evaluate_case_audit_layer147_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;
