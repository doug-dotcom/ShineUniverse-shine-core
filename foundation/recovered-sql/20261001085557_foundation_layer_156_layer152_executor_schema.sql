
create table foundation.case_audit_layer152_reconcile_exec_events(
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  environment text not null check(environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_layer151_event_id uuid not null
    references foundation.case_audit_layer147_reconcile_exec_events(event_id),
  coverage_incident_event_id uuid
    references foundation.case_audit_layer152_coverage_incident_events(event_id),
  action_key text not null check(action_key='run-independent-layer152-reconciliation'),
  cause_class text not null check(cause_class ~ '^[a-z0-9][a-z0-9._-]*$'),
  event_type text not null check(event_type in('executed','denied','failed')),
  reason_code text not null check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  decision_snapshot jsonb not null check(jsonb_typeof(decision_snapshot)='object'),
  action_result jsonb check(action_result is null or jsonb_typeof(action_result)='object'),
  requested_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_layer152_reconcile_exec_events enable row level security;

create policy foundation_runtime_layer152_exec_select
on foundation.case_audit_layer152_reconcile_exec_events
for select to foundation_runtime using(true);

create policy client_access_explicit_deny
on foundation.case_audit_layer152_reconcile_exec_events
as restrictive for all to anon,authenticated
using(false) with check(false);

revoke all on foundation.case_audit_layer152_reconcile_exec_events
from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
     shine_defence_runtime,service_role;

grant select on foundation.case_audit_layer152_reconcile_exec_events
to foundation_runtime,service_role;

create index case_audit_layer152_exec_target_idx
on foundation.case_audit_layer152_reconcile_exec_events(
  target_layer151_event_id,requested_at desc,event_sequence desc
);

create index case_audit_layer152_exec_incident_idx
on foundation.case_audit_layer152_reconcile_exec_events(
  coverage_incident_event_id,requested_at desc,event_sequence desc
);

create unique index case_audit_layer152_exec_target_once_idx
on foundation.case_audit_layer152_reconcile_exec_events(target_layer151_event_id)
where event_type='executed';

create trigger case_audit_layer152_exec_append_only
before update or delete
on foundation.case_audit_layer152_reconcile_exec_events
for each row execute function foundation.reject_append_only_mutation();
