
create table foundation.case_audit_layer111_exec_reconciliations(
 reconciliation_sequence bigint generated always as identity primary key,
 reconciliation_id uuid not null unique default gen_random_uuid(),
 layer111_event_id uuid not null unique references foundation.case_audit_layer107_reconcile_exec_events(event_id),
 environment text not null check(environment ~ '^[a-z0-9][a-z0-9._-]*$'),
 target_layer106_event_id uuid not null references foundation.case_audit_layer102_reconcile_exec_events(event_id),
 reconciliation_state text not null check(reconciliation_state in ('reconciled','source-not-executed','policy-drift','incident-drift')),
 reason_code text not null check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
 reconciliation_proof jsonb not null check(jsonb_typeof(reconciliation_proof)='object'),
 reconciliation_proof_sha256 text not null check(reconciliation_proof_sha256 ~ '^[a-f0-9]{64}$'),
 reconciled_at timestamptz not null, recorded_at timestamptz not null default now()
);
alter table foundation.case_audit_layer111_exec_reconciliations enable row level security;
create policy foundation_runtime_layer111_reconcile_select on foundation.case_audit_layer111_exec_reconciliations for select to foundation_runtime using(true);
create policy client_access_explicit_deny on foundation.case_audit_layer111_exec_reconciliations as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on foundation.case_audit_layer111_exec_reconciliations from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime,service_role;
grant select on foundation.case_audit_layer111_exec_reconciliations to foundation_runtime,service_role;
create index case_audit_layer111_reconcile_target_idx on foundation.case_audit_layer111_exec_reconciliations(target_layer106_event_id,reconciled_at desc,reconciliation_sequence desc);
create index case_audit_layer111_reconcile_state_idx on foundation.case_audit_layer111_exec_reconciliations(reconciliation_state,reconciled_at desc,reconciliation_sequence desc);
create trigger case_audit_layer111_reconcile_append_only before update or delete on foundation.case_audit_layer111_exec_reconciliations for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.run_case_audit_layer111_execution_reconciliation_v1(p_layer111_event_id uuid,p_reconciled_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path='' as $$
declare e foundation.case_audit_layer107_reconcile_exec_events%rowtype; old foundation.case_audit_layer111_exec_reconciliations%rowtype; rid uuid; st text; rs text; proof jsonb; h text;
begin
 if p_layer111_event_id is null then raise exception 'case-audit-layer111-reconciliation-event-id-required'; end if;
 select * into e from foundation.case_audit_layer107_reconcile_exec_events where event_id=p_layer111_event_id;
 if e.event_id is null then return jsonb_build_object('status','not-applicable','reasonCode','case-audit-layer111-event-not-found','mutationPerformed',false); end if;
 select * into old from foundation.case_audit_layer111_exec_reconciliations where layer111_event_id=e.event_id;
 if old.reconciliation_id is not null then return jsonb_build_object('status','existing','reconciliationId',old.reconciliation_id,'reconciliationState',old.reconciliation_state,'mutationPerformed',false); end if;
 if e.event_type='executed' then st:='reconciled';rs:='case-audit-layer111-complete'; else st:='source-not-executed';rs:='case-audit-layer111-source-not-executed'; end if;
 rid:=gen_random_uuid();
 proof:=jsonb_build_object('foundationCaseAuditLayer111ExecutionReconciliationProof','shine-foundation/case-audit-layer111-execution-reconciliation-proof-v1','schemaVersion','1.0.0','reconciliationId',rid,'layer111EventId',e.event_id,'environment',e.environment,'targetLayer106EventId',e.target_layer106_event_id,'sourceEventType',e.event_type,'reconciliationState',st,'reasonCode',rs,'authorityExpansion',false,'upstreamRerunPerformed',false,'mutationPerformed',false,'reconciledAt',p_reconciled_at);
 h:=encode(extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),'hex');
 insert into foundation.case_audit_layer111_exec_reconciliations(reconciliation_id,layer111_event_id,environment,target_layer106_event_id,reconciliation_state,reason_code,reconciliation_proof,reconciliation_proof_sha256,reconciled_at)
 values(rid,e.event_id,e.environment,e.target_layer106_event_id,st,rs,proof,h,p_reconciled_at);
 return jsonb_build_object('foundationCaseAuditLayer111ExecutionReconciliation','shine-foundation/case-audit-layer111-execution-reconciliation-v1','schemaVersion','1.0.0','status','recorded','reconciliationId',rid,'layer111EventId',e.event_id,'reconciliationState',st,'reasonCode',rs,'reconciliationProofSha256',h,'mutationPerformed',false);
end $$;
revoke all on function foundation.run_case_audit_layer111_execution_reconciliation_v1(uuid,timestamptz) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_case_audit_layer111_execution_reconciliation_v1(uuid,timestamptz) to service_role;
