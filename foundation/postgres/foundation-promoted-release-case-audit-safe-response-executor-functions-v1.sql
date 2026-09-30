-- Foundation Layer 76 stored-function identifier convergence.
-- After renaming an already-live ledger, refresh PL/pgSQL bodies so their SQL text
-- resolves the canonical short table identifier. Fresh databases safely reapply
-- the same definitions as a no-op replacement.

create or replace function foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_requested_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer76_execute$
declare
  v_decision jsonb;
  v_incident jsonb;
  v_before_audit jsonb;
  v_before_incident jsonb;
  v_after_audit jsonb;
  v_after_incident jsonb;
  v_incident_event_id uuid;
  v_current_event foundation.foundation_promoted_release_case_audit_incident_events%rowtype;
  v_policy_fingerprint text;
  v_existing foundation.case_audit_safe_response_exec_events%rowtype;
  v_action_result jsonb;
  v_event_id uuid;
  v_reason text;
  v_required_control text;
  v_error text;
begin
  if p_action_key not in (
    'record-fresh-promotion-case-audit-observation',
    'materialise-current-owner-handoff'
  ) then
    raise exception 'promotion-case-audit-safe-response-action-not-supported';
  end if;

  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_requested_at is null
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes' then
    raise exception 'promotion-case-audit-safe-response-input-invalid';
  end if;

  v_decision :=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      p_action_key,p_environment,p_requested_at,600
    );

  v_incident :=
    foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
      p_environment,p_requested_at,600
    );

  begin
    v_incident_event_id :=
      nullif(v_incident#>>'{currentEvent,eventId}','')::uuid;
  exception when invalid_text_representation then
    v_incident_event_id := null;
  end;

  if v_incident_event_id is null then
    raise exception 'promotion-case-audit-safe-response-current-incident-required';
  end if;

  select * into v_current_event
  from foundation.foundation_promoted_release_case_audit_incident_events
  where event_id=v_incident_event_id
    and environment=p_environment
    and event_type in ('detected','opened','changed');

  if v_current_event.event_id is null then
    raise exception 'promotion-case-audit-safe-response-current-incident-invalid';
  end if;

  if v_incident#>>'{currentEvent,evidenceFingerprint}'
       is distinct from v_current_event.evidence_fingerprint
     or v_incident#>>'{currentEvent,sourceState}'
       is distinct from v_current_event.source_state then
    raise exception 'promotion-case-audit-safe-response-incident-evidence-mismatch';
  end if;

  v_policy_fingerprint :=
    foundation.foundation_promoted_release_case_audit_response_policy_fingerprint_v1(
      v_decision,v_incident
    );

  select * into v_existing
  from foundation.case_audit_safe_response_exec_events
  where incident_event_id=v_incident_event_id
    and action_key=p_action_key
    and policy_fingerprint=v_policy_fingerprint;

  if v_existing.event_id is not null then
    return jsonb_build_object(
      'foundationPromotedReleaseCaseAuditSafeResponseExecution',
        'shine-foundation/promoted-release-case-audit-safe-response-execution-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'eventId',v_existing.event_id,
      'environment',v_existing.environment,
      'incidentEventId',v_existing.incident_event_id,
      'actionKey',v_existing.action_key,
      'eventType',v_existing.event_type,
      'reasonCode',v_existing.reason_code,
      'policyFingerprint',v_existing.policy_fingerprint,
      'actionResult',v_existing.action_result,
      'executesOnlyBoundedSafeAction',true,
      'arbitrarySqlExecution',false,
      'historyRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  v_before_audit :=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      p_environment,p_requested_at,600
    );

  v_before_incident := v_incident;

  v_required_control := coalesce(v_decision->>'requiredControl','prohibited');

  if v_decision->>'decision'<>'admit'
     or coalesce(v_decision->>'authorityExpansion','true')<>'false'
     or coalesce(v_decision->>'automaticRepairAllowed','true')<>'false'
     or coalesce(v_decision->>'historyRewriteAllowed','true')<>'false'
     or coalesce(v_decision->>'mutatesAuthoritativeTruth','true')<>'false'
     or coalesce(v_decision->>'mutatesIncidentHistory','true')<>'false'
     or coalesce(v_decision->>'executesAction','true')<>'false'
     or (
       p_action_key='record-fresh-promotion-case-audit-observation'
       and v_required_control<>'evidence-only'
     )
     or (
       p_action_key='materialise-current-owner-handoff'
       and v_required_control<>'layer-67-bounded-generator'
     ) then

    v_event_id := gen_random_uuid();
    v_reason := 'promotion-case-audit-safe-response-policy-not-admitted';

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,requested_at
    )
    values(
      v_event_id,p_environment,v_incident_event_id,p_action_key,
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'denied',v_reason,v_decision,v_incident,
      jsonb_build_object(
        'caseAudit',v_before_audit,
        'caseAuditIncident',v_before_incident
      ),
      p_requested_at
    );

    return jsonb_build_object(
      'foundationPromotedReleaseCaseAuditSafeResponseExecution',
        'shine-foundation/promoted-release-case-audit-safe-response-execution-v1',
      'schemaVersion','1.0.0',
      'status','denied',
      'eventId',v_event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'actionKey',p_action_key,
      'reasonCode',v_reason,
      'policyFingerprint',v_policy_fingerprint,
      'executesOnlyBoundedSafeAction',true,
      'arbitrarySqlExecution',false,
      'historyRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end if;

  begin
    if p_action_key='record-fresh-promotion-case-audit-observation' then
      v_action_result :=
        foundation.record_foundation_promoted_release_case_audit_observation_v1(
          p_environment,p_requested_at
        );
      v_reason := 'promotion-case-audit-safe-response-observation-recorded';

    elsif p_action_key='materialise-current-owner-handoff' then
      v_action_result :=
        foundation.generate_foundation_promoted_release_owner_handoff_v1(
          p_environment,p_requested_at
        );
      v_reason := 'promotion-case-audit-safe-response-handoff-materialiser-ran';
    end if;

    v_after_audit :=
      foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
        p_environment,p_requested_at,600
      );

    v_after_incident :=
      foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
        p_environment,p_requested_at,600
      );

    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,action_result,after_snapshot,requested_at
    )
    values(
      v_event_id,p_environment,v_incident_event_id,p_action_key,
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'executed',v_reason,v_decision,v_incident,
      jsonb_build_object(
        'caseAudit',v_before_audit,
        'caseAuditIncident',v_before_incident
      ),
      v_action_result,
      jsonb_build_object(
        'caseAudit',v_after_audit,
        'caseAuditIncident',v_after_incident
      ),
      p_requested_at
    );

    return jsonb_build_object(
      'foundationPromotedReleaseCaseAuditSafeResponseExecution',
        'shine-foundation/promoted-release-case-audit-safe-response-execution-v1',
      'schemaVersion','1.0.0',
      'status','executed',
      'eventId',v_event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'actionKey',p_action_key,
      'reasonCode',v_reason,
      'policyFingerprint',v_policy_fingerprint,
      'actionResult',v_action_result,
      'executesOnlyBoundedSafeAction',true,
      'arbitrarySqlExecution',false,
      'historyRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );

  exception when others then
    v_error := sqlerrm;
    v_event_id := gen_random_uuid();

    insert into foundation.case_audit_safe_response_exec_events(
      event_id,environment,incident_event_id,action_key,cause_class,
      policy_fingerprint,event_type,reason_code,decision_snapshot,
      incident_snapshot,before_snapshot,error_detail,requested_at
    )
    values(
      v_event_id,p_environment,v_incident_event_id,p_action_key,
      coalesce(v_decision->>'causeClass','unknown'),
      v_policy_fingerprint,'failed',
      'promotion-case-audit-safe-response-target-failed',
      v_decision,v_incident,
      jsonb_build_object(
        'caseAudit',v_before_audit,
        'caseAuditIncident',v_before_incident
      ),
      v_error,p_requested_at
    );

    return jsonb_build_object(
      'foundationPromotedReleaseCaseAuditSafeResponseExecution',
        'shine-foundation/promoted-release-case-audit-safe-response-execution-v1',
      'schemaVersion','1.0.0',
      'status','failed',
      'eventId',v_event_id,
      'environment',p_environment,
      'incidentEventId',v_incident_event_id,
      'actionKey',p_action_key,
      'reasonCode','promotion-case-audit-safe-response-target-failed',
      'errorDetail',v_error,
      'policyFingerprint',v_policy_fingerprint,
      'executesOnlyBoundedSafeAction',true,
      'arbitrarySqlExecution',false,
      'historyRewritePerformed',false,
      'releaseTruthMutationPerformed',false,
      'incidentHistoryMutationPerformed',false
    );
  end;
end;
$layer76_execute$;

revoke all on function foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
  text,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
  text,text,timestamptz
) to service_role;


create or replace function foundation.get_foundation_promoted_release_case_audit_safe_response_execution_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer76_summary$
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
    raise exception 'promotion-case-audit-safe-response-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter (where event_type='executed'),
    count(*) filter (where event_type='denied'),
    count(*) filter (where event_type='failed')
  into v_total,v_executed,v_denied,v_failed
  from foundation.case_audit_safe_response_exec_events
  where environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'eventId',x.event_id,
        'incidentEventId',x.incident_event_id,
        'actionKey',x.action_key,
        'causeClass',x.cause_class,
        'eventType',x.event_type,
        'reasonCode',x.reason_code,
        'policyFingerprint',x.policy_fingerprint,
        'actionResult',x.action_result,
        'errorDetail',x.error_detail,
        'requestedAt',x.requested_at
      )
      order by x.event_sequence desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select *
    from foundation.case_audit_safe_response_exec_events
    where environment=p_environment
    order by event_sequence desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditSafeResponseExecutionSummary',
      'shine-foundation/promoted-release-case-audit-safe-response-execution-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'totalCount',v_total,
    'executedCount',v_executed,
    'deniedCount',v_denied,
    'failedCount',v_failed,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'executesOnlyBoundedSafeAction',true,
    'arbitrarySqlExecution',false,
    'historyRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false
  );
end;
$layer76_summary$;

revoke all on function foundation.get_foundation_promoted_release_case_audit_safe_response_execution_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_case_audit_safe_response_execution_summary_v1(
  text,integer
) to foundation_runtime,service_role;
