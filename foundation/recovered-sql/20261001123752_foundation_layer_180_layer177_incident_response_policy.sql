
create or replace function foundation.get_case_audit_layer177_coverage_incident_cause_v1(
 p_environment text default 'production', p_as_of timestamptz default now(),
 p_reconciliation_grace_seconds integer default 300
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare
 c jsonb; i foundation.case_audit_layer177_coverage_incident_events%rowtype;
 cf text; inf text; integrity boolean:=true; current_evidence boolean:=false;
 istate text:='normal'; cause text; next_action text;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
 or p_as_of is null or p_reconciliation_grace_seconds not between 60 and 3600 then
  raise exception 'case-audit-layer177-response-cause-input-invalid';
 end if;
 c:=foundation.get_case_audit_layer177_reconciliation_coverage_v1(p_environment,p_as_of,p_reconciliation_grace_seconds);
 cf:=foundation.get_case_audit_layer177_coverage_semantic_fingerprint_v1(c);
 select x.* into i from foundation.case_audit_layer177_coverage_incident_events x
 where x.incident_key=p_environment||':case_audit_layer177_reconciliation_coverage'
 and x.occurred_at<=p_as_of order by x.occurred_at desc,x.event_sequence desc limit 1;
 istate:=case when i.event_id is null then 'normal' when i.event_type='detected' then 'watching'
              when i.event_type in('opened','changed') then 'critical' else 'normal' end;
 if i.event_id is not null then
  inf:=foundation.get_case_audit_layer177_coverage_semantic_fingerprint_v1(i.snapshot);
  integrity:=i.evidence_fingerprint is not distinct from inf;
 end if;
 current_evidence:=i.event_id is not null and integrity
  and i.event_type in('detected','opened','changed') and i.source_state in('gap','invalid')
  and i.source_state is not distinct from c->>'state' and inf is not distinct from cf;

 if i.event_id is not null and not integrity then cause:='layer179-incident-receipt-integrity'; next_action:='inspect-layer179-incident-receipt';
 elsif istate in('watching','critical') and not current_evidence then cause:='layer179-current-incident-evidence-stale'; next_action:='refresh-layer179-incident-evidence';
 elsif c->>'state' in('idle','normal','pending') then cause:='none'; next_action:='none';
 elsif coalesce((c->>'invalidLayer177ReconciliationCount')::int,0)>0 or c->>'state'='invalid' then cause:='layer177-receipt-integrity'; next_action:='inspect-layer177-reconciliation-receipt';
 elsif coalesce((c->>'missingLayer172ReceiptCount')::int,0)>0 then cause:='layer172-receipt-missing'; next_action:='inspect-layer172-reconciliation-receipt';
 elsif coalesce((c->>'executionReceiptMismatchCount')::int,0)>0 then cause:='layer176-execution-receipt-mismatch'; next_action:='inspect-layer176-execution-receipt';
 elsif coalesce((c->>'admissionValidationDriftCount')::int,0)>0 then cause:='layer176-admission-validation-drift'; next_action:='inspect-layer176-admission-validation';
 elsif coalesce((c->>'policyDriftCount')::int,0)>0 then cause:='layer176-policy-drift'; next_action:='inspect-layer176-policy-binding';
 elsif coalesce((c->>'incidentIntegrityDriftCount')::int,0)>0 then cause:='layer176-incident-integrity-drift'; next_action:='inspect-layer176-incident-integrity';
 elsif coalesce((c->>'incidentStateDriftCount')::int,0)>0 then cause:='layer176-incident-state-drift'; next_action:='inspect-layer176-incident-state-binding';
 elsif coalesce((c->>'incidentBindingDriftCount')::int,0)>0 then cause:='layer176-incident-binding-drift'; next_action:='inspect-layer176-incident-binding';
 elsif coalesce((c->>'semanticCurrentnessDriftCount')::int,0)>0 then cause:='layer176-semantic-currentness-drift'; next_action:='inspect-layer176-semantic-admission-evidence';
 elsif coalesce((c->>'overdueCount')::int,0)>0 then cause:='layer177-reconciliation-omission'; next_action:='run-independent-layer177-reconciliation';
 else cause:='layer177-reconciliation-coverage-gap'; next_action:='inspect-layer178-coverage';
 end if;
 return jsonb_build_object(
  'foundationCaseAuditLayer177CoverageIncidentCause','shine-foundation/case-audit-layer177-reconciliation-coverage-incident-cause-v1',
  'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,'incidentState',istate,
  'currentIncidentEventId',i.event_id,'currentIncidentEventType',i.event_type,'incidentEvidenceIntegrity',integrity,
  'incidentEvidenceCurrent',current_evidence,'currentIncidentSemanticFingerprint',inf,'coverageSemanticFingerprint',cf,
  'coverageState',c->>'state','causeClass',cause,'nextEvidenceAction',next_action,'coverage',c,
  'authorityExpansion',false,'automaticRepairAllowed',false,'historyRewriteAllowed',false,'mutatesAuthoritativeTruth',false);
end $$;

create or replace function foundation.evaluate_case_audit_layer177_coverage_incident_response_v1(
 p_action_key text,p_environment text default 'production',p_as_of timestamptz default now(),
 p_reconciliation_grace_seconds integer default 300
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare c jsonb; cc text; istate text; decision text:='deny'; control text:='prohibited';
 reason text:='case-audit-layer177-response-action-not-registered';
begin
 if p_action_key is null or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then raise exception 'case-audit-layer177-response-action-invalid'; end if;
 c:=foundation.get_case_audit_layer177_coverage_incident_cause_v1(p_environment,p_as_of,p_reconciliation_grace_seconds);
 cc:=coalesce(c->>'causeClass','unknown'); istate:=coalesce(c->>'incidentState','normal');
 if p_action_key in('inspect-layer178-coverage','inspect-layer179-incident-state') then decision:='admit';control:='read-only';reason:='case-audit-layer177-response-observe';
 elsif p_action_key='inspect-layer179-incident-receipt' and cc='layer179-incident-receipt-integrity' then decision:='admit';control:='read-only';reason:='case-audit-layer177-response-inspect-incident-receipt';
 elsif p_action_key='refresh-layer179-incident-evidence' and cc='layer179-current-incident-evidence-stale' then decision:='admit';control:='read-only-sentinel-refresh';reason:='case-audit-layer177-response-refresh-incident-evidence';
 elsif p_action_key='inspect-layer177-reconciliation-receipt' and cc='layer177-receipt-integrity' then decision:='admit';control:='read-only';reason:='case-audit-layer177-response-inspect-receipt';
 elsif p_action_key='run-independent-layer177-reconciliation' and cc='layer177-reconciliation-omission'
   and istate in('watching','critical') and coalesce((c->>'incidentEvidenceIntegrity')::boolean,false)
   and coalesce((c->>'incidentEvidenceCurrent')::boolean,false) then
   decision:='admit';control:='layer-177-bounded-reconciler';reason:='case-audit-layer177-response-run-bounded-reconciliation';
 end if;
 return jsonb_build_object(
  'foundationCaseAuditLayer177CoverageIncidentResponseDecision','shine-foundation/case-audit-layer177-reconciliation-coverage-incident-response-decision-v1',
  'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,'incidentState',istate,
  'actionKey',p_action_key,'causeClass',cc,'decision',decision,'requiredControl',control,'reasonCode',reason,
  'incidentEvidenceIntegrity',c->'incidentEvidenceIntegrity','incidentEvidenceCurrent',c->'incidentEvidenceCurrent',
  'authorityExpansion',false,'automaticRepairAllowed',false,'historyRewriteAllowed',false,
  'mutatesAuthoritativeTruth',false,'executesAction',false,'cause',c);
end $$;

revoke execute on function foundation.get_case_audit_layer177_coverage_incident_cause_v1(text,timestamptz,integer) from public,anon,authenticated;
grant execute on function foundation.get_case_audit_layer177_coverage_incident_cause_v1(text,timestamptz,integer) to service_role;
revoke execute on function foundation.evaluate_case_audit_layer177_coverage_incident_response_v1(text,text,timestamptz,integer) from public,anon,authenticated;
grant execute on function foundation.evaluate_case_audit_layer177_coverage_incident_response_v1(text,text,timestamptz,integer) to service_role;
