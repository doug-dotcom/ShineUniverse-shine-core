
create or replace function foundation.verify_case_audit_layer183_incident_evidence_v1(
 p_environment text,p_incident_event_id uuid,p_coverage jsonb
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare i foundation.case_audit_layer183_coverage_incident_events%rowtype;cf text;inf text;integ boolean:=false;cur boolean:=false;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' or p_coverage is null
 then raise exception 'case-audit-layer183-evidence-input-invalid'; end if;
 cf:=foundation.get_case_audit_layer183_coverage_semantic_fingerprint_v1(p_coverage);
 if p_incident_event_id is not null then select x.* into i from foundation.case_audit_layer183_coverage_incident_events x
  where x.event_id=p_incident_event_id and x.environment=p_environment; end if;
 if i.event_id is not null then inf:=foundation.get_case_audit_layer183_coverage_semantic_fingerprint_v1(i.snapshot);
  integ:=i.evidence_fingerprint is not distinct from inf;
  cur:=integ and i.event_type in('detected','opened','changed') and i.source_state in('gap','invalid')
   and i.source_state is not distinct from p_coverage->>'state' and inf is not distinct from cf; end if;
 return jsonb_build_object('verified',i.event_id is not null,'integrity',integ,'current',cur,'incidentEventId',i.event_id,
 'incidentSemanticFingerprint',inf,'coverageSemanticFingerprint',cf);
end $$;

create or replace function foundation.validate_case_audit_layer183_reconciliation_admission_v1(
 p_environment text default 'production',p_as_of timestamptz default now(),p_reconciliation_grace_seconds int default 300
) returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare d jsonb;c jsonb;v jsonb;i uuid;admitted boolean:=false;
begin
 d:=foundation.evaluate_case_audit_layer183_coverage_incident_response_v1('run-independent-layer183-reconciliation',p_environment,p_as_of,p_reconciliation_grace_seconds);
 c:=foundation.get_case_audit_layer183_reconciliation_coverage_v1(p_environment,p_as_of,p_reconciliation_grace_seconds);
 begin i:=nullif(d#>>'{cause,currentIncidentEventId}','')::uuid;exception when invalid_text_representation then i:=null;end;
 v:=foundation.verify_case_audit_layer183_incident_evidence_v1(p_environment,i,c);
 admitted:=d->>'decision'='admit' and d->>'requiredControl'='layer-183-bounded-reconciler'
 and d->>'causeClass'='layer183-reconciliation-omission' and d->>'incidentState' in('watching','critical')
 and coalesce((v->>'verified')::boolean,false) and coalesce((v->>'integrity')::boolean,false) and coalesce((v->>'current')::boolean,false);
 return jsonb_build_object('foundationCaseAuditLayer183ReconciliationAdmissionValidation',
 'shine-foundation/case-audit-layer183-reconciliation-admission-validation-v1','schemaVersion','1.0.0',
 'environment',p_environment,'validatedAt',p_as_of,'admitted',admitted,'incidentEventId',i,'incidentState',d->>'incidentState',
 'incidentEvidenceIntegrity',v->'integrity','incidentEvidenceCurrent',v->'current',
 'incidentSemanticFingerprint',v->>'incidentSemanticFingerprint','coverageSemanticFingerprint',v->>'coverageSemanticFingerprint',
 'causeClass',d->>'causeClass','decision',d);
end $$;
revoke execute on function foundation.verify_case_audit_layer183_incident_evidence_v1(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function foundation.verify_case_audit_layer183_incident_evidence_v1(text,uuid,jsonb) to service_role;
revoke execute on function foundation.validate_case_audit_layer183_reconciliation_admission_v1(text,timestamptz,int) from public,anon,authenticated;
grant execute on function foundation.validate_case_audit_layer183_reconciliation_admission_v1(text,timestamptz,int) to service_role;
