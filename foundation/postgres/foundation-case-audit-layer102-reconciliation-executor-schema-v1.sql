-- Foundation Layer 106: schema and policy fingerprint for the bounded Layer-102 reconciler.

create or replace function foundation.case_audit_layer102_reconcile_exec_policy_fp_v1(
  p_decision jsonb,
  p_incident jsonb,
  p_target jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer106_policy_fp$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'targetLayer101EventId',p_target->>'layer101EventId',
          'targetLayer96EventId',p_target->>'targetLayer96EventId',
          'targetCoverageIncidentEventId',p_target->>'coverageIncidentEventId',
          'targetActionKey',p_target->>'actionKey',
          'targetCauseClass',p_target->>'causeClass',
          'targetPolicyFingerprint',p_target->>'policyFingerprint',
          'targetEventType',p_target->>'eventType',
          'targetReasonCode',p_target->>'reasonCode',
          'targetRequestedAt',p_target->'requestedAt',
          'reconciliationGraceSeconds',p_target->'reconciliationGraceSeconds',
          'targetLayer102ReconciliationId',p_target->>'layer102ReconciliationId',
          'targetLayer102ReconciliationState',p_target->>'layer102ReconciliationState',
          'layer102ReconciliationAbsent',p_target->'layer102ReconciliationAbsent',
          'incidentState',p_decision->>'incidentState',
          'causeClass',p_decision->>'causeClass',
          'actionKey',p_decision->>'actionKey',
          'decision',p_decision->>'decision',
          'requiredControl',p_decision->>'requiredControl',
          'reasonCode',p_decision->>'reasonCode',
          'authorityExpansion',p_decision->'authorityExpansion',
          'automaticLayer102ReconciliationAllowed',p_decision->'automaticLayer102ReconciliationAllowed',
          'automaticReconciliationAllowed',p_decision->'automaticReconciliationAllowed',
          'automaticRepairAllowed',p_decision->'automaticRepairAllowed',
          'layer102ReceiptRewriteAllowed',p_decision->'layer102ReceiptRewriteAllowed',
          'layer101ReceiptRewriteAllowed',p_decision->'layer101ReceiptRewriteAllowed',
          'layer97ReceiptRewriteAllowed',p_decision->'layer97ReceiptRewriteAllowed',
          'historyRewriteAllowed',p_decision->'historyRewriteAllowed',
          'layer101RerunAllowed',p_decision->'layer101RerunAllowed',
          'layer97RerunAllowed',p_decision->'layer97RerunAllowed',
          'layer96RerunAllowed',p_decision->'layer96RerunAllowed',
          'layer92RerunAllowed',p_decision->'layer92RerunAllowed',
          'layer91RerunAllowed',p_decision->'layer91RerunAllowed',
          'layer87RerunAllowed',p_decision->'layer87RerunAllowed',
          'layer86RerunAllowed',p_decision->'layer86RerunAllowed',
          'layer82RerunAllowed',p_decision->'layer82RerunAllowed',
          'layer81RerunAllowed',p_decision->'layer81RerunAllowed',
          'verificationRerunAllowed',p_decision->'verificationRerunAllowed',
          'executesAction',p_decision->'executesAction',
          'incidentEventId',p_incident#>>'{currentEvent,eventId}',
          'incidentEventType',p_incident#>>'{currentEvent,eventType}',
          'incidentSourceState',p_incident#>>'{currentEvent,sourceState}',
          'incidentEvidenceFingerprint',p_incident#>>'{currentEvent,evidenceFingerprint}'
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer106_policy_fp$;

revoke all on function foundation.case_audit_layer102_reconcile_exec_policy_fp_v1(jsonb,jsonb,jsonb)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;

create table foundation.case_audit_layer102_reconcile_exec_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  environment text not null check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_layer101_event_id uuid not null
    references foundation.case_audit_layer97_reconcile_exec_events(event_id),
  coverage_incident_event_id uuid
    references foundation.case_audit_layer102_coverage_incident_events(event_id),
  action_key text not null check (action_key='run-independent-layer102-reconciliation'),
  cause_class text not null check (cause_class ~ '^[a-z0-9][a-z0-9._-]*$'),
  policy_fingerprint text not null check (policy_fingerprint ~ '^[a-f0-9]{64}$'),
  event_type text not null check (event_type in ('executed','denied','failed')),
  reason_code text not null check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  decision_snapshot jsonb not null check (jsonb_typeof(decision_snapshot)='object'),
  incident_snapshot jsonb not null check (jsonb_typeof(incident_snapshot)='object'),
  target_snapshot jsonb not null check (jsonb_typeof(target_snapshot)='object'),
  before_coverage jsonb not null check (jsonb_typeof(before_coverage)='object'),
  action_result jsonb check (action_result is null or jsonb_typeof(action_result)='object'),
  after_coverage jsonb check (after_coverage is null or jsonb_typeof(after_coverage)='object'),
  error_detail text,
  requested_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (
    (event_type='executed' and action_result is not null and error_detail is null)
    or (event_type='denied' and action_result is null and error_detail is null)
    or (event_type='failed' and action_result is null and error_detail is not null)
  )
);

alter table foundation.case_audit_layer102_reconcile_exec_events enable row level security;

create policy foundation_runtime_case_audit_layer102_reconcile_exec_select
on foundation.case_audit_layer102_reconcile_exec_events
for select to foundation_runtime using (true);

create policy client_access_explicit_deny
on foundation.case_audit_layer102_reconcile_exec_events
as restrictive for all to anon,authenticated using (false) with check (false);

revoke all on foundation.case_audit_layer102_reconcile_exec_events
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_layer102_reconcile_exec_events
  to foundation_runtime,service_role;

create index case_audit_layer102_reconcile_exec_target_idx
  on foundation.case_audit_layer102_reconcile_exec_events(
    target_layer101_event_id,requested_at desc,event_sequence desc
  );

create index case_audit_layer102_reconcile_exec_incident_idx
  on foundation.case_audit_layer102_reconcile_exec_events(
    coverage_incident_event_id,requested_at desc,event_sequence desc
  );

create unique index case_audit_layer102_reconcile_exec_target_once_idx
  on foundation.case_audit_layer102_reconcile_exec_events(target_layer101_event_id)
  where event_type='executed';

create trigger case_audit_layer102_reconcile_exec_append_only
before update or delete on foundation.case_audit_layer102_reconcile_exec_events
for each row execute function foundation.reject_append_only_mutation();
