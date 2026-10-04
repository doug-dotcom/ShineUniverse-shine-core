
create table foundation.case_audit_layer161_exec_reconciliations(
  reconciliation_sequence bigint generated always as identity primary key,
  reconciliation_id uuid not null unique default gen_random_uuid(),
  layer161_event_id uuid not null unique
    references foundation.case_audit_layer157_reconcile_exec_events(event_id),
  environment text not null check(environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_layer156_event_id uuid not null
    references foundation.case_audit_layer152_reconcile_exec_events(event_id),
  coverage_incident_event_id uuid
    references foundation.case_audit_layer157_coverage_incident_events(event_id),
  layer157_reconciliation_id uuid
    references foundation.case_audit_layer156_exec_reconciliations(reconciliation_id),
  semantic_admission_validation_sha256 text not null
    check(semantic_admission_validation_sha256 ~ '^[a-f0-9]{64}$'),
  coverage_semantic_fingerprint text,
  incident_semantic_fingerprint text,
  reconciliation_state text not null check(
    reconciliation_state in(
      'reconciled',
      'missing-layer157-receipt',
      'execution-receipt-mismatch',
      'admission-validation-drift',
      'policy-drift',
      'incident-state-drift',
      'incident-binding-drift',
      'semantic-freshness-drift'
    )
  ),
  reason_code text not null check(reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  reconciliation_proof jsonb not null check(jsonb_typeof(reconciliation_proof)='object'),
  reconciliation_proof_sha256 text not null check(reconciliation_proof_sha256 ~ '^[a-f0-9]{64}$'),
  reconciled_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_layer161_exec_reconciliations enable row level security;

create policy foundation_runtime_layer161_reconcile_select
on foundation.case_audit_layer161_exec_reconciliations
for select to foundation_runtime using(true);

create policy client_access_explicit_deny
on foundation.case_audit_layer161_exec_reconciliations
as restrictive for all to anon,authenticated
using(false) with check(false);

revoke all on foundation.case_audit_layer161_exec_reconciliations
from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
     shine_defence_runtime,service_role;

grant select on foundation.case_audit_layer161_exec_reconciliations
to foundation_runtime,service_role;

create index case_audit_layer161_reconcile_target_idx
on foundation.case_audit_layer161_exec_reconciliations(
  target_layer156_event_id,reconciled_at desc,reconciliation_sequence desc
);

create index case_audit_layer161_reconcile_incident_idx
on foundation.case_audit_layer161_exec_reconciliations(
  coverage_incident_event_id,reconciled_at desc,reconciliation_sequence desc
);

create index case_audit_layer161_reconcile_state_idx
on foundation.case_audit_layer161_exec_reconciliations(
  reconciliation_state,reconciled_at desc,reconciliation_sequence desc
);

create trigger case_audit_layer161_reconcile_append_only
before update or delete
on foundation.case_audit_layer161_exec_reconciliations
for each row execute function foundation.reject_append_only_mutation();
