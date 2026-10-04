
create or replace function foundation.get_case_audit_layer107_coverage_incident_cause_v1(
 p_environment text default 'production', p_as_of timestamptz default now(),
 p_reconciliation_grace_seconds integer default 300)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare i jsonb; c jsonb; s text; cs text; cause text; nxt text;
begin
 i:=foundation.get_case_audit_layer107_coverage_incident_summary_v1(p_environment,p_as_of,p_reconciliation_grace_seconds);
 c:=foundation.get_case_audit_layer107_reconciliation_coverage_v1(p_environment,p_as_of,p_reconciliation_grace_seconds,100);
 s:=coalesce(i->>'state','normal'); cs:=coalesce(c->>'state','invalid');
 if s='normal' and cs in ('idle','normal','pending') then cause:='none'; nxt:='none';
 elsif coalesce((c->>'invalidLayer107ReconciliationCount')::int,0)>0 or cs='invalid' then cause:='layer107-receipt-integrity'; nxt:='inspect-layer107-reconciliation-receipt';
 elsif coalesce((c->>'missingLayer102ReceiptCount')::int,0)>0 then cause:='layer102-receipt-missing'; nxt:='inspect-layer102-reconciliation-receipt';
 elsif coalesce((c->>'overdueCount')::int,0)>0 then cause:='layer107-reconciliation-omission'; nxt:='run-independent-layer107-reconciliation';
 elsif cs='gap' then cause:='layer107-reconciliation-coverage-gap'; nxt:='inspect-layer108-coverage';
 else cause:='unknown'; nxt:='inspect-layer108-coverage'; end if;
 return jsonb_build_object('foundationCaseAuditLayer107CoverageIncidentCause','shine-foundation/case-audit-layer107-reconciliation-coverage-incident-cause-v1','schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,'incidentState',s,'coverageState',cs,'causeClass',cause,'nextEvidenceAction',nxt,'incidentSummary',i,'coverage',c,'authorityExpansion',false,'automaticReconciliationAllowed',false,'automaticRepairAllowed',false,'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false);
end $$;
revoke all on function foundation.get_case_audit_layer107_coverage_incident_cause_v1(text,timestamptz,integer) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer107_coverage_incident_cause_v1(text,timestamptz,integer) to foundation_runtime,service_role;

create or replace function foundation.evaluate_case_audit_layer107_coverage_incident_response_v1(
 p_action_key text,p_environment text default 'production',p_as_of timestamptz default now(),
 p_reconciliation_grace_seconds integer default 300)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c jsonb; cause text; decision text:='deny'; control text:='prohibited'; reason text:='case-audit-layer107-response-action-not-registered';
begin
 if p_action_key is null or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then raise exception 'case-audit-layer107-response-action-invalid'; end if;
 c:=foundation.get_case_audit_layer107_coverage_incident_cause_v1(p_environment,p_as_of,p_reconciliation_grace_seconds); cause:=coalesce(c->>'causeClass','unknown');
 if p_action_key in ('inspect-layer108-coverage','inspect-layer109-incident-state') then decision:='admit';control:='read-only';reason:='case-audit-layer107-response-observe';
 elsif p_action_key='inspect-layer107-reconciliation-receipt' and cause='layer107-receipt-integrity' then decision:='admit';control:='read-only';reason:='case-audit-layer107-response-inspect-layer107-receipt';
 elsif p_action_key='inspect-layer102-reconciliation-receipt' and cause='layer102-receipt-missing' then decision:='admit';control:='read-only';reason:='case-audit-layer107-response-inspect-layer102-receipt';
 elsif p_action_key='run-independent-layer107-reconciliation' and cause='layer107-reconciliation-omission' then decision:='admit';control:='layer-107-bounded-reconciler';reason:='case-audit-layer107-response-run-bounded-reconciliation';
 end if;
 return jsonb_build_object('foundationCaseAuditLayer107CoverageIncidentResponseDecision','shine-foundation/case-audit-layer107-reconciliation-coverage-incident-response-decision-v1','schemaVersion','1.0.0','environment',p_environment,'actionKey',p_action_key,'causeClass',cause,'decision',decision,'requiredControl',control,'reasonCode',reason,'authorityExpansion',false,'automaticReconciliationAllowed',false,'automaticRepairAllowed',false,'executesAction',false,'cause',c);
end $$;
revoke all on function foundation.evaluate_case_audit_layer107_coverage_incident_response_v1(text,text,timestamptz,integer) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer107_coverage_incident_response_v1(text,text,timestamptz,integer) to foundation_runtime,service_role;
