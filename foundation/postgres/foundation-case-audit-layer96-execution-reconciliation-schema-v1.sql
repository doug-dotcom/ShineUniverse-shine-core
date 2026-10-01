-- Foundation Layer 97: immutable reconciliation ledger for Layer-96 execution receipts.

create table foundation.case_audit_layer96_exec_reconciliations (
  reconciliation_sequence bigint generated always as identity primary key,
  reconciliation_id uuid not null unique default gen_random_uuid(),
  layer96_event_id uuid not null unique
    references foundation.case_audit_layer92_reconcile_exec_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_layer91_event_id uuid not null
    references foundation.case_audit_reconcile_exec_reconcile_exec_events(event_id),
  layer92_reconciliation_id uuid
    references foundation.case_audit_reconcile_exec_reconcile_exec_reconciliations(reconciliation_id),
  reconciliation_state text not null
    check (
      reconciliation_state in (
        'reconciled',
        'missing-layer92-receipt',
        'invalid-layer92-receipt',
        'execution-receipt-mismatch',
        'policy-drift',
        'incident-drift',
        'coverage-drift'
      )
    ),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  policy_integrity_valid boolean not null,
  incident_binding_valid boolean not null,
  layer92_proof_integrity_valid boolean,
  execution_receipt_matches boolean,
  before_coverage_valid boolean not null,
  after_coverage_valid boolean not null,
  layer96_snapshot jsonb not null
    check (jsonb_typeof(layer96_snapshot)='object'),
  layer92_snapshot jsonb
    check (layer92_snapshot is null or jsonb_typeof(layer92_snapshot)='object'),
  reconciliation_proof jsonb not null
    check (jsonb_typeof(reconciliation_proof)='object'),
  reconciliation_proof_sha256 text not null
    check (reconciliation_proof_sha256 ~ '^[a-f0-9]{64}$'),
  reconciled_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_layer96_exec_reconciliations
  enable row level security;

create policy foundation_runtime_case_audit_layer96_reconcile_select
on foundation.case_audit_layer96_exec_reconciliations
for select to foundation_runtime using (true);

create policy client_access_explicit_deny
on foundation.case_audit_layer96_exec_reconciliations
as restrictive
for all
to anon,authenticated
using (false)
with check (false);

revoke all on foundation.case_audit_layer96_exec_reconciliations
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_layer96_exec_reconciliations
  to foundation_runtime,service_role;

create index case_audit_layer96_reconcile_target_idx
  on foundation.case_audit_layer96_exec_reconciliations(
    target_layer91_event_id,reconciled_at desc,reconciliation_sequence desc
  );

create index case_audit_layer96_reconcile_state_idx
  on foundation.case_audit_layer96_exec_reconciliations(
    reconciliation_state,reconciled_at desc,reconciliation_sequence desc
  );

create index case_audit_layer96_reconcile_layer92_idx
  on foundation.case_audit_layer96_exec_reconciliations(
    layer92_reconciliation_id
  );

create trigger case_audit_layer96_reconcile_append_only
before update or delete on foundation.case_audit_layer96_exec_reconciliations
for each row execute function foundation.reject_append_only_mutation();
