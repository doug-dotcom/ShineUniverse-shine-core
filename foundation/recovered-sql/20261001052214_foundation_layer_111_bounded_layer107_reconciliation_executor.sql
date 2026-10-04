
create table foundation.case_audit_layer107_reconcile_exec_events (
 event_sequence bigint generated always as identity primary key,
 event_id uuid not null unique default gen_random_uuid(),
 environment text not null check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
 target_layer106_event_id uuid not null references foundation.case_audit_layer102_reconcile_exec_events(event_id),
 coverage_incident_event_id uuid references foundation.case_audit_layer107_coverage_incident_events(event_id),
 action_key text not null check (action_key='run-independent-layer107-reconciliation'),
 cause_class text not null check (cause_class ~ '^[a-z0-9][a-z0-9._-]*$'),
 event_type text not null check (event_type in ('executed','denied','failed')),
 reason_code text not null check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
 decision_snapshot jsonb not null check (jsonb_typeof(decision_snapshot)='object'),
 requested_at timestamptz not null,
 recorded_at timestamptz not null default now()
);
alter table foundation.case_audit_layer107_reconcile_exec_events enable row level security;
create policy foundation_runtime_case_audit_layer107_reconcile_exec_select on foundation.case_audit_layer107_reconcile_exec_events for select to foundation_runtime using (true);
create policy client_access_explicit_deny on foundation.case_audit_layer107_reconcile_exec_events as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on foundation.case_audit_layer107_reconcile_exec_events from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime,service_role;
grant select on foundation.case_audit_layer107_reconcile_exec_events to foundation_runtime,service_role;
create index case_audit_layer107_reconcile_exec_target_idx on foundation.case_audit_layer107_reconcile_exec_events(target_layer106_event_id,requested_at desc,event_sequence desc);
create index case_audit_layer107_reconcile_exec_incident_idx on foundation.case_audit_layer107_reconcile_exec_events(coverage_incident_event_id,requested_at desc,event_sequence desc);
create unique index case_audit_layer107_reconcile_exec_target_once_idx on foundation.case_audit_layer107_reconcile_exec_events(target_layer106_event_id) where event_type='executed';
create trigger case_audit_layer107_reconcile_exec_append_only before update or delete on foundation.case_audit_layer107_reconcile_exec_events for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.get_case_audit_layer107_reconcile_exec_summary_v1(p_environment text default 'production',p_limit integer default 25)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare items jsonb; total integer; ex integer; dn integer; fl integer;
begin
 if p_environment is null or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' or p_limit<1 or p_limit>100 then raise exception 'case-audit-layer107-reconcile-exec-summary-input-invalid'; end if;
 select count(*),count(*) filter(where event_type='executed'),count(*) filter(where event_type='denied'),count(*) filter(where event_type='failed') into total,ex,dn,fl from foundation.case_audit_layer107_reconcile_exec_events where environment=p_environment;
 select coalesce(jsonb_agg(jsonb_build_object('eventId',x.event_id,'targetLayer106EventId',x.target_layer106_event_id,'coverageIncidentEventId',x.coverage_incident_event_id,'eventType',x.event_type,'reasonCode',x.reason_code,'requestedAt',x.requested_at) order by x.event_sequence desc),'[]'::jsonb) into items from (select * from foundation.case_audit_layer107_reconcile_exec_events where environment=p_environment order by event_sequence desc limit p_limit)x;
 return jsonb_build_object('foundationCaseAuditLayer107ReconciliationExecutorSummary','shine-foundation/case-audit-layer107-reconciliation-executor-summary-v1','schemaVersion','1.0.0','environment',p_environment,'totalCount',total,'executedCount',ex,'deniedCount',dn,'failedCount',fl,'items',items,'authorityExpansion',false,'automaticRepairAllowed',false,'upstreamRerunPerformed',false,'releaseTruthMutationPerformed',false,'incidentHistoryMutationPerformed',false);
end $$;
revoke all on function foundation.get_case_audit_layer107_reconcile_exec_summary_v1(text,integer) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer107_reconcile_exec_summary_v1(text,integer) to foundation_runtime,service_role;
