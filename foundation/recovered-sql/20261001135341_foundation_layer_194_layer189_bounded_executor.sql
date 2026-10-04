
create table foundation.case_audit_layer189_reconcile_exec_events(
 event_sequence bigint generated always as identity primary key,event_id uuid not null default gen_random_uuid() unique,
 environment text not null,target_layer188_event_id uuid not null,coverage_incident_event_id uuid,action_key text not null,cause_class text not null,
 event_type text not null check(event_type in('denied','executed','failed')),reason_code text not null,decision_snapshot jsonb not null,
 action_result jsonb,requested_at timestamptz not null,recorded_at timestamptz not null default now());
alter table foundation.case_audit_layer189_reconcile_exec_events enable row level security;
create policy "service_role_only_layer189_exec" on foundation.case_audit_layer189_reconcile_exec_events for all to service_role using(true) with check(true);
revoke all on foundation.case_audit_layer189_reconcile_exec_events from public,anon,authenticated;
grant select,insert on foundation.case_audit_layer189_reconcile_exec_events to service_role;
create unique index case_audit_layer189_exec_target_executed_uq on foundation.case_audit_layer189_reconcile_exec_events(target_layer188_event_id) where event_type='executed';
create index case_audit_layer189_exec_incident_idx on foundation.case_audit_layer189_reconcile_exec_events(coverage_incident_event_id,requested_at desc);

create or replace function foundation.execute_case_audit_overdue_layer189_reconciliation_v1(
 p_layer188_event_id uuid,p_environment text default 'production',p_requested_at timestamptz default now(),p_reconciliation_grace_seconds int default 300)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare gate jsonb;target foundation.case_audit_layer183_reconcile_exec_events%rowtype;prior uuid;
 recon foundation.case_audit_layer188_exec_reconciliations%rowtype;result jsonb;eid uuid;iid uuid;etype text;reason text;age_ok boolean;
begin
 if p_layer188_event_id is null or p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
 or p_requested_at is null or p_requested_at<now()-interval '5 minutes' or p_requested_at>now()+interval '5 minutes'
 or p_reconciliation_grace_seconds not between 60 and 3600 then raise exception 'case-audit-layer189-executor-input-invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_layer188_event_id::text,193));
 select x.* into target from foundation.case_audit_layer183_reconcile_exec_events x where x.event_id=p_layer188_event_id and x.environment=p_environment;
 if target.event_id is null then return jsonb_build_object('status','not-applicable','reasonCode','case-audit-layer189-target-not-found','boundedLayer189ReconcilerOnly',true);end if;
 select x.event_id into prior from foundation.case_audit_layer189_reconcile_exec_events x where x.target_layer188_event_id=p_layer188_event_id and x.event_type='executed' limit 1;
 if prior is not null then return jsonb_build_object('status','existing','eventId',prior,'boundedLayer189ReconcilerOnly',true);end if;
 select x.* into recon from foundation.case_audit_layer188_exec_reconciliations x where x.layer188_event_id=p_layer188_event_id;
 age_ok:=extract(epoch from(p_requested_at-target.requested_at))>p_reconciliation_grace_seconds;
 gate:=foundation.validate_case_audit_layer189_reconciliation_admission_v1(p_environment,p_requested_at,p_reconciliation_grace_seconds);
 begin iid:=nullif(gate->>'incidentEventId','')::uuid;exception when invalid_text_representation then iid:=null;end;
 if target.event_type<>'executed' or recon.reconciliation_id is not null or not age_ok or coalesce((gate->>'admitted')::boolean,false)=false
 or coalesce((gate->>'incidentEvidenceIntegrity')::boolean,false)=false or coalesce((gate->>'incidentEvidenceCurrent')::boolean,false)=false or iid is null
 then etype:='denied';reason:='case-audit-layer189-executor-not-admitted';
 else result:=foundation.run_case_audit_layer188_execution_reconciliation_v1(p_layer188_event_id,p_requested_at);
  if result->>'status' in('recorded','existing') then etype:='executed';reason:='case-audit-layer189-reconciliation-ran';
  else etype:='failed';reason:='case-audit-layer189-reconciliation-failed';result:=null;end if;end if;
 eid:=gen_random_uuid();
 insert into foundation.case_audit_layer189_reconcile_exec_events(event_id,environment,target_layer188_event_id,coverage_incident_event_id,
 action_key,cause_class,event_type,reason_code,decision_snapshot,action_result,requested_at)
 values(eid,p_environment,p_layer188_event_id,iid,'run-independent-layer189-reconciliation',coalesce(gate->>'causeClass','unknown'),etype,reason,gate,result,p_requested_at);
 return jsonb_build_object('foundationCaseAuditOverdueLayer189ReconciliationExecution',
 'shine-foundation/case-audit-overdue-layer189-reconciliation-execution-v1','schemaVersion','1.0.0','status',etype,'eventId',eid,
 'layer188EventId',p_layer188_event_id,'coverageIncidentEventId',iid,'incidentEvidenceIntegrity',gate->'incidentEvidenceIntegrity',
 'incidentEvidenceCurrent',gate->'incidentEvidenceCurrent','reasonCode',reason,'actionResult',result,'boundedLayer189ReconcilerOnly',true,'authorityExpansion',false);
end $$;
revoke execute on function foundation.execute_case_audit_overdue_layer189_reconciliation_v1(uuid,text,timestamptz,int) from public,anon,authenticated;
grant execute on function foundation.execute_case_audit_overdue_layer189_reconciliation_v1(uuid,text,timestamptz,int) to service_role;
