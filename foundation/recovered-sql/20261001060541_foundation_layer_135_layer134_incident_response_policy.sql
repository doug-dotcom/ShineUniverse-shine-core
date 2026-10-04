
create or replace function foundation.get_case_audit_layer132_coverage_incident_cause_v1(
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
  nxt text;
begin
  c:=foundation.get_case_audit_layer132_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds,100
  );

  if c->>'state' in ('idle','normal','pending') then
    cause:='none';
    nxt:='none';
  elsif coalesce((c->>'invalidLayer132ReconciliationCount')::int,0)>0
        or c->>'state'='invalid' then
    cause:='layer132-receipt-integrity';
    nxt:='inspect-layer132-reconciliation-receipt';
  elsif coalesce((c->>'missingLayer127ReceiptCount')::int,0)>0 then
    cause:='layer127-receipt-missing';
    nxt:='inspect-layer127-reconciliation-receipt';
  elsif coalesce((c->>'executionReceiptMismatchCount')::int,0)>0 then
    cause:='layer131-execution-receipt-mismatch';
    nxt:='inspect-layer131-execution-receipt';
  elsif coalesce((c->>'policyDriftCount')::int,0)>0 then
    cause:='layer130-policy-drift';
    nxt:='inspect-layer130-policy-binding';
  elsif coalesce((c->>'overdueCount')::int,0)>0 then
    cause:='layer132-reconciliation-omission';
    nxt:='run-independent-layer132-reconciliation';
  else
    cause:='layer132-reconciliation-coverage-gap';
    nxt:='inspect-layer133-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer132CoverageIncidentCause',
      'shine-foundation/case-audit-layer132-reconciliation-coverage-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
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

revoke all on function foundation.get_case_audit_layer132_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.get_case_audit_layer132_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer132_coverage_incident_response_v1(
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
  decision text:='deny';
  control text:='prohibited';
  reason text:='case-audit-layer132-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer132-response-action-invalid';
  end if;

  c:=foundation.get_case_audit_layer132_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );
  cause:=c->>'causeClass';

  if p_action_key in ('inspect-layer133-coverage','inspect-layer134-incident-state') then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer132-response-observe';
  elsif p_action_key='inspect-layer132-reconciliation-receipt'
        and cause='layer132-receipt-integrity' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer132-response-inspect-layer132-receipt';
  elsif p_action_key='inspect-layer127-reconciliation-receipt'
        and cause='layer127-receipt-missing' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer132-response-inspect-layer127-receipt';
  elsif p_action_key='inspect-layer131-execution-receipt'
        and cause='layer131-execution-receipt-mismatch' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer132-response-inspect-layer131-receipt';
  elsif p_action_key='inspect-layer130-policy-binding'
        and cause='layer130-policy-drift' then
    decision:='admit';
    control:='read-only';
    reason:='case-audit-layer132-response-inspect-layer130-policy';
  elsif p_action_key='run-independent-layer132-reconciliation'
        and cause='layer132-reconciliation-omission' then
    decision:='admit';
    control:='layer-132-bounded-reconciler';
    reason:='case-audit-layer132-response-run-bounded-reconciliation';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer132CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer132-reconciliation-coverage-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
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

revoke all on function foundation.evaluate_case_audit_layer132_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.evaluate_case_audit_layer132_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;
