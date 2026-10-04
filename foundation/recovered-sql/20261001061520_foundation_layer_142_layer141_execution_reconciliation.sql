
create table foundation.case_audit_layer141_exec_reconciliations(
 reconciliation_sequence bigint generated always as identity primary key,
 reconciliation_id uuid not null unique default gen_random_uuid(),
 layer141_event_id uuid not null unique references foundation.case_audit_layer137_reconcile_exec_events(event_id),
 environment text not null check(environment ~ '^[a-z0-9][a-z0-9._-]*$'),
 target_layer136_event_id uuid not null references foundation.case_audit_layer132_reconcile_exec_events(event_id),
 layer137_reconciliation_id uuid references foundation.case_audit_layer136_exec_reconciliations(reconciliation_id),
 reconciliation_state text not null check(reconciliation_state in(
   'reconciled','missing-layer137-receipt','execution-receipt-mismatch','policy-drift','incident-state-drift'
 )),
 reason_code text not null check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
 reconciliation_proof jsonb not null check(jsonb_typeof(reconciliation_proof)='object'),
 reconciliation_proof_sha256 text not null check(reconciliation_proof_sha256 ~ '^[a-f0-9]{64}$'),
 reconciled_at timestamptz not null,
 recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_layer141_exec_reconciliations enable row level security;

create policy foundation_runtime_layer141_reconcile_select
on foundation.case_audit_layer141_exec_reconciliations
for select to foundation_runtime using(true);

create policy client_access_explicit_deny
on foundation.case_audit_layer141_exec_reconciliations
as restrictive for all to anon,authenticated using(false) with check(false);

revoke all on foundation.case_audit_layer141_exec_reconciliations
from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime,service_role;

grant select on foundation.case_audit_layer141_exec_reconciliations
to foundation_runtime,service_role;

create index case_audit_layer141_reconcile_target_idx
on foundation.case_audit_layer141_exec_reconciliations(
 target_layer136_event_id,reconciled_at desc,reconciliation_sequence desc
);

create index case_audit_layer141_reconcile_state_idx
on foundation.case_audit_layer141_exec_reconciliations(
 reconciliation_state,reconciled_at desc,reconciliation_sequence desc
);

create trigger case_audit_layer141_reconcile_append_only
before update or delete on foundation.case_audit_layer141_exec_reconciliations
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.run_case_audit_layer141_execution_reconciliation_v1(
 p_layer141_event_id uuid,
 p_reconciled_at timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 e foundation.case_audit_layer137_reconcile_exec_events%rowtype;
 r foundation.case_audit_layer136_exec_reconciliations%rowtype;
 old foundation.case_audit_layer141_exec_reconciliations%rowtype;
 rid uuid; st text; rs text; proof jsonb; h text;
begin
 if p_layer141_event_id is null then raise exception 'case-audit-layer141-reconciliation-event-id-required'; end if;
 if p_reconciled_at is null or p_reconciled_at<now()-interval '5 minutes' or p_reconciled_at>now()+interval '5 minutes'
 then raise exception 'case-audit-layer141-reconciliation-time-invalid'; end if;

 select * into e from foundation.case_audit_layer137_reconcile_exec_events where event_id=p_layer141_event_id;
 if e.event_id is null then return jsonb_build_object('status','not-applicable','reasonCode','case-audit-layer141-event-not-found','mutationPerformed',false); end if;
 if e.event_type<>'executed' then return jsonb_build_object('status','not-applicable','reasonCode','case-audit-layer141-source-not-executed','mutationPerformed',false); end if;

 select * into old from foundation.case_audit_layer141_exec_reconciliations where layer141_event_id=e.event_id;
 if old.reconciliation_id is not null then
   return jsonb_build_object('status','existing','reconciliationId',old.reconciliation_id,'reconciliationState',old.reconciliation_state,'mutationPerformed',false);
 end if;

 select * into r from foundation.case_audit_layer136_exec_reconciliations where layer136_event_id=e.target_layer136_event_id;

 if r.reconciliation_id is null then
   st:='missing-layer137-receipt'; rs:='case-audit-layer141-layer137-receipt-missing';
 elsif e.action_result->>'reconciliationId' is distinct from r.reconciliation_id::text then
   st:='execution-receipt-mismatch'; rs:='case-audit-layer141-receipt-mismatch';
 elsif e.decision_snapshot->>'decision'<>'admit'
    or e.decision_snapshot->>'requiredControl'<>'layer-137-bounded-reconciler'
    or e.decision_snapshot->>'causeClass'<>'layer137-reconciliation-omission' then
   st:='policy-drift'; rs:='case-audit-layer141-policy-drift';
 elsif e.decision_snapshot->>'incidentState' not in('watching','critical') then
   st:='incident-state-drift'; rs:='case-audit-layer141-incident-state-drift';
 else
   st:='reconciled'; rs:='case-audit-layer141-complete';
 end if;

 rid:=gen_random_uuid();
 proof:=jsonb_build_object(
   'foundationCaseAuditLayer141ExecutionReconciliationProof','shine-foundation/case-audit-layer141-execution-reconciliation-proof-v1',
   'schemaVersion','1.0.0','reconciliationId',rid,'layer141EventId',e.event_id,'environment',e.environment,
   'targetLayer136EventId',e.target_layer136_event_id,'layer137ReconciliationId',r.reconciliation_id,
   'incidentState',e.decision_snapshot->>'incidentState','reconciliationState',st,'reasonCode',rs,
   'authorityExpansion',false,'upstreamRerunPerformed',false,'evidenceMutationPerformed',false,
   'releaseTruthMutationPerformed',false,'incidentHistoryMutationPerformed',false,'mutationPerformed',false,
   'reconciledAt',p_reconciled_at
 );
 h:=encode(extensions.digest(convert_to(proof::text,'UTF8'),'sha256'),'hex');

 insert into foundation.case_audit_layer141_exec_reconciliations(
   reconciliation_id,layer141_event_id,environment,target_layer136_event_id,layer137_reconciliation_id,
   reconciliation_state,reason_code,reconciliation_proof,reconciliation_proof_sha256,reconciled_at
 ) values(rid,e.event_id,e.environment,e.target_layer136_event_id,r.reconciliation_id,st,rs,proof,h,p_reconciled_at);

 return jsonb_build_object(
   'foundationCaseAuditLayer141ExecutionReconciliation','shine-foundation/case-audit-layer141-execution-reconciliation-v1',
   'schemaVersion','1.0.0','status','recorded','reconciliationId',rid,'layer141EventId',e.event_id,
   'layer137ReconciliationId',r.reconciliation_id,'incidentState',e.decision_snapshot->>'incidentState',
   'reconciliationState',st,'reasonCode',rs,'reconciliationProofSha256',h,
   'authorityExpansion',false,'upstreamRerunPerformed',false,'evidenceMutationPerformed',false,'mutationPerformed',false
 );
end $$;

revoke all on function foundation.run_case_audit_layer141_execution_reconciliation_v1(uuid,timestamptz)
from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.run_case_audit_layer141_execution_reconciliation_v1(uuid,timestamptz)
to service_role;
