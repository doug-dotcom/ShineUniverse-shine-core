-- Foundation Layer 81: bounded executor for overdue independent verification.
-- Layer 80 may admit exactly one executable action: run-independent-verification.
-- Layer 81 binds that policy decision to one specific successful Layer-76 receipt,
-- requires that receipt to be overdue and still unverified, then calls the existing
-- Layer-77 verifier. It also removes direct service_role access to Layer 77 so this
-- executor becomes the only service-role verification entrypoint.

create or replace function foundation.case_audit_verify_exec_policy_fp_v1(
  p_decision jsonb,
  p_incident jsonb,
  p_target jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer81_policy_fp$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'targetExecutionEventId',p_target->>'executionEventId',
          'targetIncidentEventId',p_target->>'incidentEventId',
          'targetActionKey',p_target->>'actionKey',
          'targetExecutionPolicyFingerprint',
            p_target->>'executionPolicyFingerprint',
          'targetRequestedAt',p_target->'executionRequestedAt',
          'verificationGraceSeconds',p_target->'verificationGraceSeconds',
          'targetVerificationState',p_target->>'verificationState',
          'incidentState',p_decision->>'incidentState',
          'causeClass',p_decision->>'causeClass',
          'actionKey',p_decision->>'actionKey',
          'actionClass',p_decision->>'actionClass',
          'decision',p_decision->>'decision',
          'requiredControl',p_decision->>'requiredControl',
          'reasonCode',p_decision->>'reasonCode',
          'authorityExpansion',p_decision->'authorityExpansion',
          'automaticVerificationAllowed',
            p_decision->'automaticVerificationAllowed',
          'automaticRepairAllowed',p_decision->'automaticRepairAllowed',
          'verificationProofRewriteAllowed',
            p_decision->'verificationProofRewriteAllowed',
          'historyRewriteAllowed',p_decision->'historyRewriteAllowed',
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
$layer81_policy_fp$;

revoke all on function foundation.case_audit_verify_exec_policy_fp_v1(
  jsonb,jsonb,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create table foundation.case_audit_verify_exec_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_execution_event_id uuid not null
    references foundation.case_audit_safe_response_exec_events(event_id),
  verification_incident_event_id uuid
    references foundation.case_audit_verify_incident_events(event_id),
  action_key text not null
    check (action_key='run-independent-verification'),
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

alter table foundation.case_audit_verify_exec_events
  enable row level security;

create policy foundation_runtime_case_audit_verify_exec_select
on foundation.case_audit_verify_exec_events
for select
to foundation_runtime
using (true);

revoke all on foundation.case_audit_verify_exec_events
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_verify_exec_events
  to foundation_runtime,service_role;

create index case_audit_verify_exec_target_idx
  on foundation.case_audit_verify_exec_events(
    target_execution_event_id,requested_at desc,event_sequence desc
  );

create index case_audit_verify_exec_incident_idx
  on foundation.case_audit_verify_exec_events(
    verification_incident_event_id,requested_at desc,event_sequence desc
  );

create unique index case_audit_verify_exec_target_once_idx
  on foundation.case_audit_verify_exec_events(target_execution_event_id)
  where event_type='executed';

create trigger case_audit_verify_exec_append_only
before update or delete on foundation.case_audit_verify_exec_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.execute_case_audit_overdue_verification_v1(
  p_execution_event_id uuid,
  p_environment text default 'production',
  p_requested_at timestamptz default now(),
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer81_execute$
declare
  v_target foundation.case_audit_safe_response_exec_events%rowtype;
  v_existing_exec foundation.case_audit_verify_exec_events%rowtype;
  v_existing_verification foundation.case_audit_safe_response_verifications%rowtype;
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
  if p_execution_event_id is null then
    raise exception 'case-audit-overdue-verification-execution-id-required';
  end if;

  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_requested_at is null
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes'
     or p_verification_grace_seconds<60
     or p_verification_grace_seconds>3600 then
    raise exception 'case-audit-overdue-verification-input-invalid';
  end if;

  -- Serialise executor calls for the same target receipt.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_execution_event_id::text,81)
  );

  select * into v_target
  from foundation.case_audit_safe_response_exec_events
  where event_id=p_execution_event_id
    and environment=p_environment;

  if v_target.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditOverdueVerificationExecution',
        'shine-foundation/case-audit-overdue-verification-execution-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executionEventId',p_execution_event_id,
      'environment',p_environment,
      'reasonCode','case-audit-overdue-verification-target-not-found',
      'boundedLayer77VerifierOnly',true,
      'safeResponseRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  select * into v_existing_exec
  from foundation.case_audit_verify_exec_events
  where target_execution_event_id=v_target.event_id
    and event_type='executed'
  order by event_sequence desc
  limit 1;

  if v_existing_exec.event_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditOverdueVerificationExecution',
        'shine-foundation/case-audit-overdue-verification-execution-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'eventId',v_existing_exec.event_id,
      'executionEventId',v_existing_exec.target_execution_event_id,
      'environment',v_existing_exec.environment,
      'incidentEventId',v_existing_exec.verification_incident_event_id,
      'eventType',v_existing_exec.event_type,
      'reasonCode',v_existing_exec.reason_code,
      'policyFingerprint',v_existing_exec.policy_fingerprint,
      'actionResult',v_existing_exec.action_result,
      'boundedLayer77VerifierOnly',true,
      'safeResponseRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  v_age_seconds := greatest(
    0,
    floor(extract(epoch from (p_requested_at-v_target.requested_at)))::integer
  );

  select * into v_existing_verification
  from foundation.case_audit_safe_response_verifications
  where execution_event_id=v_target.event_id;

  v_incident :=
    foundation.get_case_audit_verify_incident_summary_v1(
      p_environment,p_requested_at,p_verification_grace_seconds
    );

  v_decision :=
    foundation.evaluate_case_audit_verify_incident_response_v1(
      'run-independent-verification',
      p_environment,
      p_requested_at,
      p_verification_grace_seconds
    );

  v_before_coverage :=
    foundation.get_case_audit_safe_response_verification_coverage_v1(
      p_environment,p_requested_at,p_verification_grace_seconds,100
    );

  begin
    v_incident_event_id :=
      nullif(v_incident#>>'{currentEvent,eventId}','')::uuid;
  exception when invalid_text_representation then
    v_incident_event_id := null;
  end;

  v_target_snapshot := jsonb_build_object(
    'executionEventId',v_target.event_id,
    'incidentEventId',v_target.incident_event_id,
    'actionKey',v_target.action_key,
    'executionPolicyFingerprint',v_target.policy_fingerprint,
    'executionEventType',v_target.event_type,
    'executionRequestedAt',v_target.requested_at,
    'executionAgeSeconds',v_age_seconds,
    'verificationGraceSeconds',p_verification_grace_seconds,
    'verificationId',v_existing_verification.verification_id,
    'verificationState',v_existing_verification.verification_state,
    'verificationAbsent',v_existing_verification.verification_id is null
  );

  v_policy_fingerprint :=
    foundation.case_audit_verify_exec_policy_fp_v1(
      v_decision,v_incident,v_target_snapshot
    );

  if v_target.event_type<>'executed'
     or v_age_seconds<=p_verification_grace_seconds
     or v_existing_verification.verification_id is not null
     or v_incident->>'state' not in ('watching','critical')
     or v_incident_event_id is null
     or v_decision->>'decision'<>'admit'
     or v_decision->>'requiredControl'<>'layer-77-bounded-verifier'
     or v_decision->>'causeClass'<>'verification-omission'
     or coalesce(v_decision->>'authorityExpansion','true')<>'false'
     or coalesce(v_decision->>'automaticVerificationAllowed','true')<>'false'
     or coalesce(v_decision->>'automaticRepairAllowed','true')<>'false'
     or coalesce(v_decision->>'verificationProofRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'historyRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'executesAction','true')<>'false'
     or coalesce(v_decision->>'rerunsSafeResponse','true')<>'false'
     or coalesce(v_decision->>'mutatesVerificationProof','true')<>'false'
     or coalesce(v_decision->>'mutatesAuthoritativeTruth','true')<>'false'
     or coalesce(v_decision->>'mutatesIncidentHistory','true')<>'false' then

    v_event_id := gen_random_uuid();

    v_reason := case
      when v_target.event_type<>'executed'
        then 'case-audit-overdue-verification-target-not-successful'
      when v_age_seconds<=p_verification_grace_seconds
        then 'case-audit-overdue-verification-within-grace'
      when v_existing_verification.verification_id is not null
        then 'case-audit-overdue-verification-already-verified'
      when v_incident->>'state' not in ('watching','critical')
        then 'case-audit-overdue-verification-incident-not-active'
      else 'case-audit-overdue-verification-policy-not-admitted'
    end;

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-verification',
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'denied',v_reason,v_decision,v_incident,
      v_target_snapshot,v_before_coverage,p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueVerificationExecution',
        'shine-foundation/case-audit-overdue-verification-execution-v1',
      'schemaVersion','1.0.0',
      'status','denied',
      'eventId',v_event_id,
      'executionEventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode',v_reason,
      'policyFingerprint',v_policy_fingerprint,
      'boundedLayer77VerifierOnly',true,
      'safeResponseRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  begin
    v_result :=
      foundation.run_case_audit_safe_response_verification_v1(
        v_target.event_id,p_requested_at
      );

    if v_result->>'status' not in ('recorded','existing')
       or v_result->>'verificationState'
            not in ('verified','missing','mismatch') then
      raise exception 'case-audit-overdue-verification-layer77-result-invalid';
    end if;

    v_after_coverage :=
      foundation.get_case_audit_safe_response_verification_coverage_v1(
        p_environment,p_requested_at,p_verification_grace_seconds,100
      );

    v_event_id := gen_random_uuid();
    v_reason := 'case-audit-overdue-verification-layer77-ran';

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,action_result,
      after_coverage,requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-verification',
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'executed',v_reason,v_decision,v_incident,
      v_target_snapshot,v_before_coverage,v_result,v_after_coverage,
      p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueVerificationExecution',
        'shine-foundation/case-audit-overdue-verification-execution-v1',
      'schemaVersion','1.0.0',
      'status','executed',
      'eventId',v_event_id,
      'executionEventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode',v_reason,
      'policyFingerprint',v_policy_fingerprint,
      'actionResult',v_result,
      'afterCoverageState',v_after_coverage->>'state',
      'boundedLayer77VerifierOnly',true,
      'safeResponseRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );

  exception when others then
    v_error := sqlerrm;
    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_verify_exec_events(
      event_id,environment,target_execution_event_id,
      verification_incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,target_snapshot,before_coverage,error_detail,
      requested_at
    )
    values(
      v_event_id,p_environment,v_target.event_id,v_incident_event_id,
      'run-independent-verification',
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'failed',
      'case-audit-overdue-verification-layer77-failed',
      v_decision,v_incident,v_target_snapshot,v_before_coverage,
      v_error,p_requested_at
    );

    return jsonb_build_object(
      'foundationCaseAuditOverdueVerificationExecution',
        'shine-foundation/case-audit-overdue-verification-execution-v1',
      'schemaVersion','1.0.0',
      'status','failed',
      'eventId',v_event_id,
      'executionEventId',v_target.event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'reasonCode','case-audit-overdue-verification-layer77-failed',
      'errorDetail',v_error,
      'policyFingerprint',v_policy_fingerprint,
      'boundedLayer77VerifierOnly',true,
      'safeResponseRerunPerformed',false,
      'evidenceMutationPerformed',false,
      'verificationProofRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end;
end;
$layer81_execute$;

revoke all on function foundation.execute_case_audit_overdue_verification_v1(
  uuid,text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.execute_case_audit_overdue_verification_v1(
  uuid,text,timestamptz,integer
) to service_role;


-- Seal the underlying Layer-77 writer behind Layer 81. The SECURITY DEFINER
-- Layer-81 function can still invoke it as its owner; service_role cannot bypass
-- the Layer-80 policy/target eligibility checks anymore.
revoke execute on function foundation.run_case_audit_safe_response_verification_v1(
  uuid,timestamptz
) from service_role;


create or replace function foundation.get_case_audit_verify_exec_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer81_summary$
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
    raise exception 'case-audit-verify-exec-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter (where event_type='executed'),
    count(*) filter (where event_type='denied'),
    count(*) filter (where event_type='failed')
  into v_total,v_executed,v_denied,v_failed
  from foundation.case_audit_verify_exec_events
  where environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'eventId',x.event_id,
        'targetExecutionEventId',x.target_execution_event_id,
        'verificationIncidentEventId',x.verification_incident_event_id,
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
    from foundation.case_audit_verify_exec_events
    where environment=p_environment
    order by event_sequence desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditVerificationExecutorSummary',
      'shine-foundation/case-audit-verification-executor-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'totalCount',v_total,
    'executedCount',v_executed,
    'deniedCount',v_denied,
    'failedCount',v_failed,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'directLayer77ServiceRoleBypassAllowed',false,
    'safeResponseRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false
  );
end;
$layer81_summary$;

revoke all on function foundation.get_case_audit_verify_exec_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_exec_summary_v1(
  text,integer
) to foundation_runtime,service_role;
