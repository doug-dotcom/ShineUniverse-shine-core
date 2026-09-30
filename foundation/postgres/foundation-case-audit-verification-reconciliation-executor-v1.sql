-- Foundation Layer 86: bounded executor for overdue reconciliation.
-- Layer 85 may admit exactly one executable action: run-independent-reconciliation.
-- Layer 86 binds that policy decision to one specific successful Layer-81 event,
-- requires the event to be overdue and still unreconciled, then calls the existing
-- Layer-82 reconciler. It also removes direct service_role access to Layer 82 so
-- this executor becomes the only service-role reconciliation entrypoint.

create or replace function foundation.case_audit_verify_reconcile_exec_policy_fp_v1(
  p_decision jsonb,
  p_incident jsonb,
  p_target jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer86_policy_fp$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'targetExecutorEventId',p_target->>'executorEventId',
          'targetExecutionEventId',p_target->>'targetExecutionEventId',
          'targetVerificationIncidentEventId',
            p_target->>'verificationIncidentEventId',
          'targetActionKey',p_target->>'actionKey',
          'targetCauseClass',p_target->>'causeClass',
          'targetPolicyFingerprint',p_target->>'policyFingerprint',
          'targetEventType',p_target->>'eventType',
          'targetReasonCode',p_target->>'reasonCode',
          'targetRequestedAt',p_target->'requestedAt',
          'reconciliationGraceSeconds',p_target->'reconciliationGraceSeconds',
          'verificationGraceSeconds',p_target->'verificationGraceSeconds',
          'targetReconciliationId',p_target->>'reconciliationId',
          'targetReconciliationState',p_target->>'reconciliationState',
          'reconciliationAbsent',p_target->'reconciliationAbsent',
          'incidentState',p_decision->>'incidentState',
          'causeClass',p_decision->>'causeClass',
          'actionKey',p_decision->>'actionKey',
          'actionClass',p_decision->>'actionClass',
          'decision',p_decision->>'decision',
          'requiredControl',p_decision->>'requiredControl',
          'reasonCode',p_decision->>'reasonCode',
          'authorityExpansion',p_decision->'authorityExpansion',
          'automaticReconciliationAllowed',
            p_decision->'automaticReconciliationAllowed',
          'automaticVerificationAllowed',
            p_decision->'automaticVerificationAllowed',
          'automaticRepairAllowed',p_decision->'automaticRepairAllowed',
          'reconciliationReceiptRewriteAllowed',
            p_decision->'reconciliationReceiptRewriteAllowed',
          'verificationProofRewriteAllowed',
            p_decision->'verificationProofRewriteAllowed',
          'historyRewriteAllowed',p_decision->'historyRewriteAllowed',
          'layer81RerunAllowed',p_decision->'layer81RerunAllowed',
          'verificationRerunAllowed',p_decision->'verificationRerunAllowed',
          'executesAction',p_decision->'executesAction',
          'incidentEventId',p_incident#>>'{currentEvent,eventId}',
          'incidentEventType',p_incident#>>'{currentEvent,eventType}',
          'incidentSourceState',p_incident#>>'{currentEvent,sourceState}',
          'incidentEvidenceFingerprint',
            p_incident#>>'{currentEvent,evidenceFingerprint}'
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer86_policy_fp$;

revoke all on function foundation.case_audit_verify_reconcile_exec_policy_fp_v1(
  jsonb,jsonb,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create table foundation.case_audit_verify_reconcile_exec_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_executor_event_id uuid not null
    references foundation.case_audit_verify_exec_events(event_id),
  reconciliation_incident_event_id uuid
    references foundation.case_audit_verify_reconcile_incident_events(event_id),
  action_key text not null
    check (action_key='run-independent-reconciliation'),
  cause_class text not null
    check (cause_class ~ '^[a-z0-9][a-z0-9._-]*$'),
  policy_fingerprint text not null
    check (policy_fingerprint ~ '^[a-f0-9]{64}$'),
  event_type text not null
    check (event_type in ('executed','denied','failed')),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  decision_snapshot jsonb not null
    check (jsonb_typeof(decision_snapshot)='object'),
  incident_snapshot jsonb not null
    check (jsonb_typeof(incident_snapshot)='object'),
  target_snapshot jsonb not null
    check (jsonb_typeof(target_snapshot)='object'),
  before_coverage jsonb not null
    check (jsonb_typeof(before_coverage)='object'),
  action_result jsonb
    check (action_result is null or jsonb_typeof(action_result)='object'),
  after_coverage jsonb
    check (after_coverage is null or jsonb_typeof(after_coverage)='object'),
  error_detail text,
  requested_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (
    (event_type='executed' and action_result is not null and error_detail is null)
    or (event_type='denied' and action_result is null and error_detail is null)
    or (event_type='failed' and action_result is null and error_detail is not null)
  )
);

alter table foundation.case_audit_verify_reconcile_exec_events
  enable row level security;

create policy foundation_runtime_case_audit_verify_reconcile_exec_select
on foundation.case_audit_verify_reconcile_exec_events
for select
to foundation_runtime
using (true);

revoke all on foundation.case_audit_verify_reconcile_exec_events
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_verify_reconcile_exec_events
  to foundation_runtime,service_role;

create index case_audit_verify_reconcile_exec_target_idx
  on foundation.case_audit_verify_reconcile_exec_events(
    target_executor_event_id,requested_at desc,event_sequence desc
  );

create index case_audit_verify_reconcile_exec_incident_idx
  on foundation.case_audit_verify_reconcile_exec_events(
    reconciliation_incident_event_id,requested_at desc,event_sequence desc
  );

create unique index case_audit_verify_reconcile_exec_target_once_idx
  on foundation.case_audit_verify_reconcile_exec_events(target_executor_event_id)
  where event_type='executed';

create trigger case_audit_verify_reconcile_exec_append_only
before update or delete on foundation.case_audit_verify_reconcile_exec_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.execute_case_audit_overdue_reconciliation_v1(
  p_executor_event_id uuid,
  p_environment text default 'production',
  p_requested_at timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300,
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer86_execute$
declare
  v_target foundation.case_audit_verify_exec_events%rowtype;
  v_existing_exec foundation.case_audit_verify_reconcile_exec_events%rowtype;
  v_existing_reconciliation foundation.case_audit_verify_exec_reconciliations%rowtype;
  v_decision jsonb;
  v_incident jsonb;
  v_before_coverage jsonb;
  v_after_coverage jsonb;
  v_target_snapshot jsonb;
  v_policy_fingerprint text;
  v_incident_event_id uuid;
  v_age_seconds integer;
  v_result jsonb;
  v_event_id uuid;
  v_reason text;
  v_error text;
begin
  if p_executor_event_id is null then
    raise exception 'case-audit-overdue-reconciliation-executor-id-required';
  end if;

  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_requested_at is null
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes'
     or p_reconciliation_grace_seconds is null
     or p_reconciliation_grace_seconds<60
     or p_reconciliation_grace_seconds>3600
     or p_verification_grace_seconds is null
     or p_verification_grace_seconds<60
     or p_verification_grace_seconds>3600 then
    raise exception 'case-audit-overdue-reconciliation-input-invalid';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_executor_event_id::text,86)
  );

  select * into v_target
  from foundation.case_audit_verify_exec_events
  where event_id=p_executor_event_id
    and environment=p_environment;

  if v_target.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditOverdueReconciliationExecution',
        'shine-foundation/case-audit-overdue-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executorEventId',p_executor_event_id,
      'environment',p_environment,
      'reasonCode','case-audit-overdue-reconciliation-target-not-found',
      'boundedLayer82ReconcilerOnly',true,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  select * into v_existing_exec
  from foundation.case_audit_verify_reconcile_exec_events
  where target_executor_event_id=v_target.event_id
    and event_type='executed'
  order by event_sequence desc
  limit 1;

  if v_existing_exec.event_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditOverdueReconciliationExecution',
        'shine-foundation/case-audit-overdue-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'eventId',v_existing_exec.event_id,
      'executorEventId',v_existing_exec.target_executor_event_id,
      'environment',v_existing_exec.environment,
      'incidentEventId',v_existing_exec.reconciliation_incident_event_id,
      'eventType',v_existing_exec.event_type,
      'reasonCode',v_existing_exec.reason_code,
      'policyFingerprint',v_existing_exec.policy_fingerprint,
      'actionResult',v_existing_exec.action_result,
      'boundedLayer82ReconcilerOnly',true,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  v_age_seconds := greatest(
    0,
    floor(extract(epoch from (p_requested_at-v_target.requested_at)))::integer
  );

  select * into v_existing_reconciliation
  from foundation.case_audit_verify_exec_reconciliations
  where executor_event_id=v_target.event_id;

  v_incident :=
    foundation.get_case_audit_verify_reconcile_incident_summary_v1(
      p_environment,p_requested_at,p_reconciliation_grace_seconds
    );

  v_decision :=
    foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
      'run-independent-reconciliation',
      p_environment,
      p_requested_at,
      p_reconciliation_grace_seconds
    );

  v_before_coverage :=
    foundation.get_case_audit_verify_reconcile_coverage_v1(
      p_environment,p_requested_at,p_reconciliation_grace_seconds,100
    );

  begin
    v_incident_event_id :=
      nullif(v_incident#>>'{currentEvent,eventId}','')::uuid;
  exception when invalid_text_representation then
    v_incident_event_id := null;
  end;

  v_target_snapshot := jsonb_build_object(
    'executorEventId',v_target.event_id,
    'targetExecutionEventId',v_target.target_execution_event_id,
    'verificationIncidentEventId',v_target.verification_incident_event_id,
    'actionKey',v_target.action_key,
    'causeClass',v_target.cause_class,
    'policyFingerprint',v_target.policy_fingerprint,
    'eventType',v_target.event_type,
    'reasonCode',v_target.reason_code,
    'requestedAt',v_target.requested_at,
    'ageSeconds',v_age_seconds,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'verificationGraceSeconds',p_verification_grace_seconds,
    'reconciliationId',v_existing_reconciliation.reconciliation_id,
    'reconciliationState',v_existing_reconciliation.reconciliation_state,
    'reconciliationAbsent',
      v_existing_reconciliation.reconciliation_id is null
  );

  v_policy_fingerprint :=
    foundation.case_audit_verify_reconcile_exec_policy_fp_v1(
      v_decision,v_incident,v_target_snapshot
    );

  if v_target.event_type<>'executed'
     or v_age_seconds<=p_reconciliation_grace_seconds
     or v_existing_reconciliation.reconciliation_id is not null
     or v_incident->>'state' not in ('watching','critical')
     or v_incident_event_id is null
     or v_decision->>'decision'<>'admit'
     or v_decision->>'requiredControl'<>'layer-82-bounded-reconciler'
     or v_decision->>'causeClass'<>'reconciliation-omission'
     or coalesce(v_decision->>'authorityExpansion','true')<>'false'
     or coalesce(v_decision->>'automaticReconciliationAllowed','true')<>'false'
     or coalesce(v_decision->>'automaticVerificationAllowed','true')<>'false'
     or coalesce(v_decision->>'automaticRepairAllowed','true')<>'false'
     or coalesce(v_decision->>'reconciliationReceiptRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'verificationProofRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'historyRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'layer81RerunAllowed','true')<>'false'
     or coalesce(v_decision->>'verificationRerunAllowed','true')<>'false'
     or coalesce(v_decision->>'executesAction','true')<>'false'
     or coalesce(v_decision->>'rerunsLayer81','true')<>'false'
     or coalesce(v_decision->>'rerunsVerification','true')<>'false'
     or coalesce(v_decision->>'mutatesReconciliationReceipt','true')<>'false'
     or coalesce(v_decision->>'mutatesVerificationProof','true')<>'false'
     or coalesce(v_decision->>'mutatesAuthoritativeTruth','true')<>'false'
     or coalesce(v_decision->>'mutatesIncidentHistory','true')<>'false' then

    v_event_id := gen_random_uuid();

    v_reason := case
      when v_target.event_type<>'executed'
        then 'case-audit-overdue-reconciliation-target-not-successful'
      when v_age_seconds<=p_reconciliation_grace_seconds
        then 'case-audit-overdue-reconciliation-within-grace'
      when v_existing_reconciliation.reconciliation_id is not null
        then 'case-audit-overdue-reconciliation-already-reconciled'
      when v_incident->>'state' not in ('watching','critical')
        then 'case-audit-overdue-reconciliation-incident-not-active'
      else 'case-audit-overdue-reconciliation-policy-not-admitted'
    end;

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,
      reconciliation_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-reconciliation',
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'denied',v_reason,v_decision,v_incident,
      v_target_snapshot,v_before_coverage,p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueReconciliationExecution',
        'shine-foundation/case-audit-overdue-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','denied',
      'eventId',v_event_id,
      'executorEventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode',v_reason,
      'policyFingerprint',v_policy_fingerprint,
      'boundedLayer82ReconcilerOnly',true,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  begin
    v_result :=
      foundation.run_case_audit_verify_exec_reconciliation_v1(
        v_target.event_id,p_requested_at,p_verification_grace_seconds
      );

    if v_result->>'status' not in ('recorded','existing')
       or v_result->>'reconciliationState' not in (
         'reconciled','missing-proof','receipt-mismatch',
         'invalid-proof','evidence-drift','coverage-drift'
       ) then
      raise exception 'case-audit-overdue-reconciliation-layer82-result-invalid';
    end if;

    v_after_coverage :=
      foundation.get_case_audit_verify_reconcile_coverage_v1(
        p_environment,p_requested_at,p_reconciliation_grace_seconds,100
      );

    v_event_id := gen_random_uuid();
    v_reason := 'case-audit-overdue-reconciliation-layer82-ran';

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,
      reconciliation_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-reconciliation',
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'executed',v_reason,v_decision,v_incident,
      v_target_snapshot,v_before_coverage,v_result,v_after_coverage,
      p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueReconciliationExecution',
        'shine-foundation/case-audit-overdue-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','executed',
      'eventId',v_event_id,
      'executorEventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode',v_reason,
      'policyFingerprint',v_policy_fingerprint,
      'actionResult',v_result,
      'afterCoverageState',v_after_coverage->>'state',
      'boundedLayer82ReconcilerOnly',true,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );

  exception when others then
    v_error := sqlerrm;
    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_verify_reconcile_exec_events(
      event_id,environment,target_executor_event_id,
      reconciliation_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,error_detail,
      requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-reconciliation',
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'failed',
      'case-audit-overdue-reconciliation-layer82-failed',
      v_decision,v_incident,v_target_snapshot,v_before_coverage,
      v_error,p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueReconciliationExecution',
        'shine-foundation/case-audit-overdue-reconciliation-execution-v1',
      'schemaVersion','1.0.0',
      'status','failed',
      'eventId',v_event_id,
      'executorEventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode','case-audit-overdue-reconciliation-layer82-failed',
      'errorDetail',v_error,
      'policyFingerprint',v_policy_fingerprint,
      'boundedLayer82ReconcilerOnly',true,
      'layer81RerunPerformed',false,
      'verificationRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'reconciliationReceiptRewritePerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end;
end;
$layer86_execute$;

revoke all on function foundation.execute_case_audit_overdue_reconciliation_v1(
  uuid,text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.execute_case_audit_overdue_reconciliation_v1(
  uuid,text,timestamptz,integer,integer
) to service_role;

revoke execute on function foundation.run_case_audit_verify_exec_reconciliation_v1(
  uuid,timestamptz,integer
) from service_role;


create or replace function foundation.get_case_audit_verify_reconcile_exec_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer86_summary$
declare
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_executed integer := 0;
  v_denied integer := 0;
  v_failed integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_limit is null
     or p_limit<1
     or p_limit>100 then
    raise exception 'case-audit-verify-reconcile-exec-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter (where event_type='executed'),
    count(*) filter (where event_type='denied'),
    count(*) filter (where event_type='failed')
  into v_total,v_executed,v_denied,v_failed
  from foundation.case_audit_verify_reconcile_exec_events
  where environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'eventId',x.event_id,
        'targetExecutorEventId',x.target_executor_event_id,
        'reconciliationIncidentEventId',x.reconciliation_incident_event_id,
        'actionKey',x.action_key,
        'causeClass',x.cause_class,
        'eventType',x.event_type,
        'reasonCode',x.reason_code,
        'policyFingerprint',x.policy_fingerprint,
        'actionResult',x.action_result,
        'requestedAt',x.requested_at
      )
      order by x.event_sequence desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select *
    from foundation.case_audit_verify_reconcile_exec_events
    where environment=p_environment
    order by event_sequence desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutorSummary',
      'shine-foundation/case-audit-reconciliation-executor-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'totalCount',v_total,
    'executedCount',v_executed,
    'deniedCount',v_denied,
    'failedCount',v_failed,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'directLayer82ServiceRoleBypassAllowed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'reconciliationReceiptRewritePerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false
  );
end;
$layer86_summary$;

revoke all on function foundation.get_case_audit_verify_reconcile_exec_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_reconcile_exec_summary_v1(
  text,integer
) to foundation_runtime,service_role;
