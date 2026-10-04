
create or replace function foundation.get_case_audit_layer127_coverage_incident_cause_v1(
 p_environment text default 'production',p_as_of timestamptz default now(),p_reconciliation_grace_seconds integer default 300)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb;cause text;nxt text;
begin
 c:=foundation.get_case_audit_layer127_reconciliation_coverage_v1(p_environment,p_as_of,p_reconciliation_grace_seconds,100);
 if c->>'state' in('idle','normal','pending') then cause:='none';nxt:='none';
 elsif coalesce((c->>'invalidLayer127ReconciliationCount')::int,0)>0 or c->>'state'='invalid' then cause:='layer127-receipt-integrity';nxt:='inspect-layer127-reconciliation-receipt';
 elsif coalesce((c->>'missingLayer122ReceiptCount')::int,0)>0 then cause:='layer122-receipt-missing';nxt:='inspect-layer122-reconciliation-receipt';
 elsif coalesce((c->>'executionReceiptMismatchCount')::int,0)>0 then cause:='layer126-execution-receipt-mismatch';nxt:='inspect-layer126-execution-receipt';
 elsif coalesce((c->>'policyDriftCount')::int,0)>0 then cause:='layer125-policy-drift';nxt:='inspect-layer125-policy-binding';
 elsif coalesce((c->>'overdueCount')::int,0)>0 then cause:='layer127-reconciliation-omission';nxt:='run-independent-layer127-reconciliation';
 else cause:='layer127-reconciliation-coverage-gap';nxt:='inspect-layer128-coverage';end if;
 return jsonb_build_object('foundationCaseAuditLayer127CoverageIncidentCause','shine-foundation/case-audit-layer127-reconciliation-coverage-incident-cause-v1','schemaVersion','1.0.0','environment',p_environment,'coverageState',c->>'state','causeClass',cause,'nextEvidenceAction',nxt,'coverage',c,'authorityExpansion',false,'automaticReconciliationAllowed',false,'automaticRepairAllowed',false,'historyRewriteAllowed',false,'upstreamRerunAllowed',false,'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false);
end $$;
revoke all on function foundation.get_case_audit_layer127_coverage_incident_cause_v1(text,timestamptz,integer) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer127_coverage_incident_cause_v1(text,timestamptz,integer) to foundation_runtime,service_role;

create or replace function foundation.evaluate_case_audit_layer127_coverage_incident_response_v1(
 p_action_key text,p_environment text default 'production',p_as_of timestamptz default now(),p_reconciliation_grace_seconds integer default 300)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb;cause text;decision text:='deny';control text:='prohibited';reason text:='case-audit-layer127-response-action-not-registered';
begin
 if p_action_key is null or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then raise exception 'case-audit-layer127-response-action-invalid';end if;
 c:=foundation.get_case_audit_layer127_coverage_incident_cause_v1(p_environment,p_as_of,p_reconciliation_grace_seconds);cause:=c->>'causeClass';
 if p_action_key in('inspect-layer128-coverage','inspect-layer129-incident-state') then decision:='admit';control:='read-only';reason:='case-audit-layer127-response-observe';
 elsif p_action_key='inspect-layer127-reconciliation-receipt' and cause='layer127-receipt-integrity' then decision:='admit';control:='read-only';reason:='case-audit-layer127-response-inspect-layer127-receipt';
 elsif p_action_key='inspect-layer122-reconciliation-receipt' and cause='layer122-receipt-missing' then decision:='admit';control:='read-only';reason:='case-audit-layer127-response-inspect-layer122-receipt';
 elsif p_action_key='inspect-layer126-execution-receipt' and cause='layer126-execution-receipt-mismatch' then decision:='admit';control:='read-only';reason:='case-audit-layer127-response-inspect-layer126-receipt';
 elsif p_action_key='inspect-layer125-policy-binding' and cause='layer125-policy-drift' then decision:='admit';control:='read-only';reason:='case-audit-layer127-response-inspect-layer125-policy';
 elsif p_action_key='run-independent-layer127-reconciliation' and cause='layer127-reconciliation-omission' then decision:='admit';control:='layer-127-bounded-reconciler';reason:='case-audit-layer127-response-run-bounded-reconciliation';
 end if;
 return jsonb_build_object('foundationCaseAuditLayer127CoverageIncidentResponseDecision','shine-foundation/case-audit-layer127-reconciliation-coverage-incident-response-decision-v1','schemaVersion','1.0.0','environment',p_environment,'actionKey',p_action_key,'causeClass',cause,'decision',decision,'requiredControl',control,'reasonCode',reason,'authorityExpansion',false,'automaticReconciliationAllowed',false,'automaticRepairAllowed',false,'historyRewriteAllowed',false,'upstreamRerunAllowed',false,'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false,'executesAction',false,'cause',c);
end $$;
revoke all on function foundation.evaluate_case_audit_layer127_coverage_incident_response_v1(text,text,timestamptz,integer) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer127_coverage_incident_response_v1(text,text,timestamptz,integer) to foundation_runtime,service_role;
