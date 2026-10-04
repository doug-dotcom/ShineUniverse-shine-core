
create table foundation.case_audit_layer132_reconcile_exec_events(
 event_sequence bigint generated always as identity primary key,
 event_id uuid not null unique default gen_random_uuid(),
 environment text not null check(environment ~ '^[a-z0-9][a-z0-9._-]*$'),
 target_layer131_event_id uuid not null references foundation.case_audit_layer127_reconcile_exec_events(event_id),
 action_key text not null check(action_key='run-independent-layer132-reconciliation'),
 cause_class text not null check(cause_class ~ '^[a-z0-9][a-z0-9._-]*$'),
 event_type text not null check(event_type in('executed','denied','failed')),
 reason_code text not null check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
 decision_snapshot jsonb not null check(jsonb_typeof(decision_snapshot)='object'),
 action_result jsonb check(action_result is null or jsonb_typeof(action_result)='object'),
 requested_at timestamptz not null,
 recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_layer132_reconcile_exec_events enable row level security;

create policy foundation_runtime_layer132_exec_select
on foundation.case_audit_layer132_reconcile_exec_events
for select to foundation_runtime using(true);

create policy client_access_explicit_deny
on foundation.case_audit_layer132_reconcile_exec_events
as restrictive for all to anon,authenticated
using(false) with check(false);

revoke all on foundation.case_audit_layer132_reconcile_exec_events
from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime,service_role;

grant select on foundation.case_audit_layer132_reconcile_exec_events
to foundation_runtime,service_role;

create index case_audit_layer132_exec_target_idx
on foundation.case_audit_layer132_reconcile_exec_events(
  target_layer131_event_id,requested_at desc,event_sequence desc
);

create unique index case_audit_layer132_exec_target_once_idx
on foundation.case_audit_layer132_reconcile_exec_events(target_layer131_event_id)
where event_type='executed';

create trigger case_audit_layer132_exec_append_only
before update or delete on foundation.case_audit_layer132_reconcile_exec_events
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.execute_case_audit_overdue_layer132_reconciliation_v1(
 p_layer131_event_id uuid,
 p_environment text default 'production',
 p_requested_at timestamptz default now(),
 p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 e foundation.case_audit_layer127_reconcile_exec_events%rowtype;
 r foundation.case_audit_layer131_exec_reconciliations%rowtype;
 prior foundation.case_audit_layer132_reconcile_exec_events%rowtype;
 d jsonb;
 res jsonb;
 id uuid;
 et text;
 reason text;
begin
 if p_layer131_event_id is null then
   raise exception 'case-audit-layer132-executor-target-required';
 end if;

 if p_environment is null
    or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
    or p_requested_at is null
    or p_reconciliation_grace_seconds is null
    or p_reconciliation_grace_seconds<60
    or p_reconciliation_grace_seconds>3600 then
   raise exception 'case-audit-layer132-executor-input-invalid';
 end if;

 perform pg_catalog.pg_advisory_xact_lock(
   pg_catalog.hashtextextended(p_layer131_event_id::text,136)
 );

 select * into e
 from foundation.case_audit_layer127_reconcile_exec_events
 where event_id=p_layer131_event_id
   and environment=p_environment;

 if e.event_id is null then
   return jsonb_build_object(
     'status','not-applicable',
     'reasonCode','case-audit-layer132-target-not-found',
     'boundedLayer132ReconcilerOnly',true,
     'upstreamRerunPerformed',false,
     'evidenceMutationPerformed',false
   );
 end if;

 select * into prior
 from foundation.case_audit_layer132_reconcile_exec_events
 where target_layer131_event_id=e.event_id
   and event_type='executed'
 order by event_sequence desc
 limit 1;

 if prior.event_id is not null then
   return jsonb_build_object(
     'status','existing',
     'eventId',prior.event_id,
     'actionResult',prior.action_result,
     'boundedLayer132ReconcilerOnly',true,
     'upstreamRerunPerformed',false,
     'evidenceMutationPerformed',false
   );
 end if;

 select * into r
 from foundation.case_audit_layer131_exec_reconciliations
 where layer131_event_id=e.event_id;

 d:=foundation.evaluate_case_audit_layer132_coverage_incident_response_v1(
   'run-independent-layer132-reconciliation',
   p_environment,p_requested_at,p_reconciliation_grace_seconds
 );

 if e.event_type<>'executed'
    or r.reconciliation_id is not null
    or p_requested_at-e.requested_at<=make_interval(secs=>p_reconciliation_grace_seconds)
    or d->>'decision'<>'admit'
    or d->>'requiredControl'<>'layer-132-bounded-reconciler' then
   et:='denied';
   reason:='case-audit-layer132-executor-not-admitted';
   res:=null;
 else
   res:=foundation.run_case_audit_layer131_execution_reconciliation_v1(
     e.event_id,p_requested_at
   );

   if res->>'status' in('recorded','existing') then
     et:='executed';
     reason:='case-audit-layer132-reconciliation-ran';
   else
     et:='failed';
     reason:='case-audit-layer132-reconciliation-failed';
     res:=null;
   end if;
 end if;

 id:=gen_random_uuid();

 insert into foundation.case_audit_layer132_reconcile_exec_events(
   event_id,environment,target_layer131_event_id,action_key,cause_class,
   event_type,reason_code,decision_snapshot,action_result,requested_at
 )
 values(
   id,p_environment,e.event_id,'run-independent-layer132-reconciliation',
   coalesce(d->>'causeClass','unknown'),et,reason,d,res,p_requested_at
 );

 return jsonb_build_object(
   'foundationCaseAuditOverdueLayer132ReconciliationExecution',
     'shine-foundation/case-audit-overdue-layer132-reconciliation-execution-v1',
   'schemaVersion','1.0.0',
   'status',et,
   'eventId',id,
   'layer131EventId',e.event_id,
   'reasonCode',reason,
   'actionResult',res,
   'boundedLayer132ReconcilerOnly',true,
   'authorityExpansion',false,
   'upstreamRerunPerformed',false,
   'evidenceMutationPerformed',false,
   'releaseTruthMutationPerformed',false,
   'incidentHistoryMutationPerformed',false
 );
end $$;

revoke all on function foundation.execute_case_audit_overdue_layer132_reconciliation_v1(
  uuid,text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;

grant execute on function foundation.execute_case_audit_overdue_layer132_reconciliation_v1(
  uuid,text,timestamptz,integer
) to service_role;
