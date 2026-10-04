
create table foundation.case_audit_layer182_exec_reconciliations(
 reconciliation_sequence bigint generated always as identity primary key,
 reconciliation_id uuid not null default gen_random_uuid() unique,
 layer182_event_id uuid not null unique,
 environment text not null,
 target_layer176_event_id uuid not null,
 coverage_incident_event_id uuid,
 layer177_reconciliation_id uuid,
 admission_validation_sha256 text not null check(admission_validation_sha256 ~ '^[0-9a-f]{64}$'),
 reconciliation_state text not null check(reconciliation_state in(
  'reconciled','missing-layer177-receipt','execution-receipt-mismatch','admission-validation-drift',
  'policy-drift','incident-integrity-drift','incident-state-drift','incident-binding-drift','semantic-currentness-drift')),
 reason_code text not null,
 reconciliation_proof jsonb not null,
 reconciliation_proof_sha256 text not null check(reconciliation_proof_sha256 ~ '^[0-9a-f]{64}$'),
 reconciled_at timestamptz not null,
 recorded_at timestamptz not null default now()
);
alter table foundation.case_audit_layer182_exec_reconciliations enable row level security;
create policy "service_role_only_layer182_reconciliations" on foundation.case_audit_layer182_exec_reconciliations
 for all to service_role using(true) with check(true);
revoke all on foundation.case_audit_layer182_exec_reconciliations from public,anon,authenticated;
grant select,insert on foundation.case_audit_layer182_exec_reconciliations to service_role;
create index case_audit_layer182_reconcile_target_idx on foundation.case_audit_layer182_exec_reconciliations(target_layer176_event_id);
create index case_audit_layer182_reconcile_incident_idx on foundation.case_audit_layer182_exec_reconciliations(coverage_incident_event_id);

create or replace function foundation.run_case_audit_layer182_execution_reconciliation_v1(
 p_layer182_event_id uuid,p_reconciled_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare e foundation.case_audit_layer177_reconcile_exec_events%rowtype;
 existing foundation.case_audit_layer182_exec_reconciliations%rowtype;
 r176 foundation.case_audit_layer176_exec_reconciliations%rowtype;
 inc foundation.case_audit_layer177_coverage_incident_events%rowtype;
 rid uuid; layer177rid uuid; gatehash text; state text; reason text; proof jsonb; phash text;
begin
 if p_layer182_event_id is null then raise exception 'case-audit-layer182-reconciliation-event-id-required'; end if;
 if p_reconciled_at is null or p_reconciled_at<now()-interval '5 minutes' or p_reconciled_at>now()+interval '5 minutes'
 then raise exception 'case-audit-layer182-reconciliation-time-invalid'; end if;
 select x.* into e from foundation.case_audit_layer177_reconcile_exec_events x where x.event_id=p_layer182_event_id;
 if e.event_id is null then return jsonb_build_object('status','not-applicable','reasonCode','case-audit-layer182-event-not-found','mutationPerformed',false); end if;
 if e.event_type<>'executed' then return jsonb_build_object('status','not-applicable','reasonCode','case-audit-layer182-source-not-executed','mutationPerformed',false); end if;
 select x.* into existing from foundation.case_audit_layer182_exec_reconciliations x where x.layer182_event_id=e.event_id;
 if existing.reconciliation_id is not null then return jsonb_build_object('status','existing','reconciliationId',existing.reconciliation_id,'reconciliationState',existing.reconciliation_state,'mutationPerformed',false); end if;
 select x.* into r176 from foundation.case_audit_layer176_exec_reconciliations x where x.layer176_event_id=e.target_layer176_event_id;
 if e.coverage_incident_event_id is not null then select x.* into inc from foundation.case_audit_layer177_coverage_incident_events x where x.event_id=e.coverage_incident_event_id and x.environment=e.environment; end if;
 gatehash:=encode(extensions.digest(convert_to(e.decision_snapshot::text,'UTF8'),'sha256'),'hex');
 begin layer177rid:=nullif(e.action_result->>'reconciliationId','')::uuid; exception when invalid_text_representation then layer177rid:=null; end;
 if r176.reconciliation_id is null then state:='missing-layer177-receipt';reason:='case-audit-layer182-layer177-receipt-missing';
 elsif layer177rid is distinct from r176.reconciliation_id then state:='execution-receipt-mismatch';reason:='case-audit-layer182-receipt-mismatch';
 elsif e.decision_snapshot->>'foundationCaseAuditLayer177ReconciliationAdmissionValidation'
   is distinct from 'shine-foundation/case-audit-layer177-reconciliation-admission-validation-v1'
   or coalesce((e.decision_snapshot->>'admitted')::boolean,false)<>true
   or e.decision_snapshot->>'causeClass'<>'layer177-reconciliation-omission'
 then state:='admission-validation-drift';reason:='case-audit-layer182-admission-validation-drift';
 elsif e.decision_snapshot#>>'{decision,decision}'<>'admit'
   or e.decision_snapshot#>>'{decision,requiredControl}'<>'layer-177-bounded-reconciler'
 then state:='policy-drift';reason:='case-audit-layer182-policy-drift';
 elsif coalesce((e.decision_snapshot->>'incidentEvidenceIntegrity')::boolean,false)<>true
 then state:='incident-integrity-drift';reason:='case-audit-layer182-incident-integrity-drift';
 elsif e.decision_snapshot->>'incidentState' not in('watching','critical')
 then state:='incident-state-drift';reason:='case-audit-layer182-incident-state-drift';
 elsif inc.event_id is null or inc.event_id is distinct from e.coverage_incident_event_id
 then state:='incident-binding-drift';reason:='case-audit-layer182-incident-binding-drift';
 elsif coalesce((e.decision_snapshot->>'incidentEvidenceCurrent')::boolean,false)<>true
 then state:='semantic-currentness-drift';reason:='case-audit-layer182-semantic-currentness-drift';
 else state:='reconciled';reason:='case-audit-layer182-complete'; end if;
 rid:=gen_random_uuid();
 proof:=jsonb_build_object('foundationCaseAuditLayer182ExecutionReconciliationProof',
 'shine-foundation/case-audit-layer182-execution-reconciliation-proof-v1','schemaVersion','1.0.0',
 'reconciliationId',rid,'layer182EventId',e.event_id,'environment',e.environment,
 'targetLayer176EventId',e.target_layer176_event_id,'coverageIncidentEventId',e.coverage_incident_event_id,
 'layer177ReconciliationId',layer177rid,'admissionValidationSha256',gatehash,
 'reconciliationState',state,'reasonCode',reason,'authorityExpansion',false,'mutationPerformed',false,'reconciledAt',p_reconciled_at);
 phash:=encode(extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),'hex');
 insert into foundation.case_audit_layer182_exec_reconciliations(reconciliation_id,layer182_event_id,environment,
 target_layer176_event_id,coverage_incident_event_id,layer177_reconciliation_id,admission_validation_sha256,
 reconciliation_state,reason_code,reconciliation_proof,reconciliation_proof_sha256,reconciled_at)
 values(rid,e.event_id,e.environment,e.target_layer176_event_id,e.coverage_incident_event_id,layer177rid,gatehash,
 state,reason,proof,phash,p_reconciled_at);
 return jsonb_build_object('foundationCaseAuditLayer182ExecutionReconciliation',
 'shine-foundation/case-audit-layer182-execution-reconciliation-v1','schemaVersion','1.0.0','status','recorded',
 'reconciliationId',rid,'layer182EventId',e.event_id,'reconciliationState',state,'reasonCode',reason,
 'reconciliationProofSha256',phash,'mutationPerformed',false);
end $$;
revoke execute on function foundation.run_case_audit_layer182_execution_reconciliation_v1(uuid,timestamptz) from public,anon,authenticated;
grant execute on function foundation.run_case_audit_layer182_execution_reconciliation_v1(uuid,timestamptz) to service_role;
