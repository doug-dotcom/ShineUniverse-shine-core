
create or replace function foundation.get_case_audit_layer183_coverage_incident_cause_v1(
 p_environment text default 'production',p_as_of timestamptz default now(),p_reconciliation_grace_seconds int default 300
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare c jsonb;i foundation.case_audit_layer183_coverage_incident_events%rowtype;cf text;inf text;integrity boolean:=true;current_ev boolean:=false;
 istate text:='normal';cause text;next_action text;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' or p_as_of is null or p_reconciliation_grace_seconds not between 60 and 3600
 then raise exception 'case-audit-layer183-response-cause-input-invalid'; end if;
 c:=foundation.get_case_audit_layer183_reconciliation_coverage_v1(p_environment,p_as_of,p_reconciliation_grace_seconds);
 cf:=foundation.get_case_audit_layer183_coverage_semantic_fingerprint_v1(c);
 select x.* into i from foundation.case_audit_layer183_coverage_incident_events x
 where x.incident_key=p_environment||':case_audit_layer183_reconciliation_coverage' and x.occurred_at<=p_as_of
 order by x.occurred_at desc,x.event_sequence desc limit 1;
 istate:=case when i.event_id is null then 'normal' when i.event_type='detected' then 'watching' when i.event_type in('opened','changed') then 'critical' else 'normal' end;
 if i.event_id is not null then inf:=foundation.get_case_audit_layer183_coverage_semantic_fingerprint_v1(i.snapshot);integrity:=i.evidence_fingerprint is not distinct from inf; end if;
 current_ev:=i.event_id is not null and integrity and i.event_type in('detected','opened','changed') and i.source_state in('gap','invalid')
 and i.source_state is not distinct from c->>'state' and inf is not distinct from cf;
 if i.event_id is not null and not integrity then cause:='layer185-incident-receipt-integrity';next_action:='inspect-layer185-incident-receipt';
 elsif istate in('watching','critical') and not current_ev then cause:='layer185-current-incident-evidence-stale';next_action:='refresh-layer185-incident-evidence';
 elsif c->>'state' in('idle','normal','pending') then cause:='none';next_action:='none';
 elsif coalesce((c->>'invalidLayer183ReconciliationCount')::int,0)>0 or c->>'state'='invalid' then cause:='layer183-receipt-integrity';next_action:='inspect-layer183-reconciliation-receipt';
 elsif coalesce((c->>'missingLayer177ReceiptCount')::int,0)>0 then cause:='layer177-receipt-missing';next_action:='inspect-layer177-reconciliation-receipt';
 elsif coalesce((c->>'executionReceiptMismatchCount')::int,0)>0 then cause:='layer182-execution-receipt-mismatch';next_action:='inspect-layer182-execution-receipt';
 elsif coalesce((c->>'admissionValidationDriftCount')::int,0)>0 then cause:='layer182-admission-validation-drift';next_action:='inspect-layer182-admission-validation';
 elsif coalesce((c->>'policyDriftCount')::int,0)>0 then cause:='layer182-policy-drift';next_action:='inspect-layer182-policy-binding';
 elsif coalesce((c->>'incidentIntegrityDriftCount')::int,0)>0 then cause:='layer182-incident-integrity-drift';next_action:='inspect-layer182-incident-integrity';
 elsif coalesce((c->>'incidentStateDriftCount')::int,0)>0 then cause:='layer182-incident-state-drift';next_action:='inspect-layer182-incident-state-binding';
 elsif coalesce((c->>'incidentBindingDriftCount')::int,0)>0 then cause:='layer182-incident-binding-drift';next_action:='inspect-layer182-incident-binding';
 elsif coalesce((c->>'semanticCurrentnessDriftCount')::int,0)>0 then cause:='layer182-semantic-currentness-drift';next_action:='inspect-layer182-semantic-admission-evidence';
 elsif coalesce((c->>'overdueCount')::int,0)>0 then cause:='layer183-reconciliation-omission';next_action:='run-independent-layer183-reconciliation';
 else cause:='layer183-reconciliation-coverage-gap';next_action:='inspect-layer184-coverage'; end if;
 return jsonb_build_object('foundationCaseAuditLayer183CoverageIncidentCause','shine-foundation/case-audit-layer183-reconciliation-coverage-incident-cause-v1',
 'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,'incidentState',istate,'currentIncidentEventId',i.event_id,
 'currentIncidentEventType',i.event_type,'incidentEvidenceIntegrity',integrity,'incidentEvidenceCurrent',current_ev,
 'currentIncidentSemanticFingerprint',inf,'coverageSemanticFingerprint',cf,'coverageState',c->>'state','causeClass',cause,
 'nextEvidenceAction',next_action,'coverage',c,'authorityExpansion',false,'automaticRepairAllowed',false,'historyRewriteAllowed',false);
end $$;

create or replace function foundation.evaluate_case_audit_layer183_coverage_incident_response_v1(
 p_action_key text,p_environment text default 'production',p_as_of timestamptz default now(),p_reconciliation_grace_seconds int default 300
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare c jsonb;cc text;ist text;decision text:='deny';control text:='prohibited';reason text:='case-audit-layer183-response-action-not-registered';
begin
 if p_action_key is null or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then raise exception 'case-audit-layer183-response-action-invalid'; end if;
 c:=foundation.get_case_audit_layer183_coverage_incident_cause_v1(p_environment,p_as_of,p_reconciliation_grace_seconds);
 cc:=coalesce(c->>'causeClass','unknown');ist:=coalesce(c->>'incidentState','normal');
 if p_action_key in('inspect-layer184-coverage','inspect-layer185-incident-state') then decision:='admit';control:='read-only';reason:='case-audit-layer183-response-observe';
 elsif p_action_key='inspect-layer185-incident-receipt' and cc='layer185-incident-receipt-integrity' then decision:='admit';control:='read-only';reason:='case-audit-layer183-response-inspect-incident-receipt';
 elsif p_action_key='refresh-layer185-incident-evidence' and cc='layer185-current-incident-evidence-stale' then decision:='admit';control:='read-only-sentinel-refresh';reason:='case-audit-layer183-response-refresh-incident-evidence';
 elsif p_action_key='inspect-layer183-reconciliation-receipt' and cc='layer183-receipt-integrity' then decision:='admit';control:='read-only';reason:='case-audit-layer183-response-inspect-receipt';
 elsif p_action_key='run-independent-layer183-reconciliation' and cc='layer183-reconciliation-omission' and ist in('watching','critical')
 and coalesce((c->>'incidentEvidenceIntegrity')::boolean,false) and coalesce((c->>'incidentEvidenceCurrent')::boolean,false)
 then decision:='admit';control:='layer-183-bounded-reconciler';reason:='case-audit-layer183-response-run-bounded-reconciliation'; end if;
 return jsonb_build_object('foundationCaseAuditLayer183CoverageIncidentResponseDecision','shine-foundation/case-audit-layer183-reconciliation-coverage-incident-response-decision-v1',
 'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,'incidentState',ist,'actionKey',p_action_key,
 'causeClass',cc,'decision',decision,'requiredControl',control,'reasonCode',reason,'incidentEvidenceIntegrity',c->'incidentEvidenceIntegrity',
 'incidentEvidenceCurrent',c->'incidentEvidenceCurrent','authorityExpansion',false,'automaticRepairAllowed',false,'historyRewriteAllowed',false,
 'executesAction',false,'cause',c);
end $$;
revoke execute on function foundation.get_case_audit_layer183_coverage_incident_cause_v1(text,timestamptz,int) from public,anon,authenticated;
grant execute on function foundation.get_case_audit_layer183_coverage_incident_cause_v1(text,timestamptz,int) to service_role;
revoke execute on function foundation.evaluate_case_audit_layer183_coverage_incident_response_v1(text,text,timestamptz,int) from public,anon,authenticated;
grant execute on function foundation.evaluate_case_audit_layer183_coverage_incident_response_v1(text,text,timestamptz,int) to service_role;
