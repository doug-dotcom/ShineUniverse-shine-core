-- Foundation Layer 76: bounded execution path for Layer-75 safe case-audit responses.
-- Only two pre-existing bounded actions are dispatchable:
--   1) record fresh Layer-73 case-audit evidence;
--   2) re-run the idempotent Layer-67 current-owner-handoff materialiser.
-- No arbitrary payload, SQL, history rewrite or release-truth mutation is accepted.

create or replace function foundation.foundation_promoted_release_case_audit_response_policy_fingerprint_v1(
  p_decision jsonb,
  p_incident jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer76_policy_fingerprint$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'incidentEventId',p_incident#>>'{currentEvent,eventId}',
          'incidentEventType',p_incident#>>'{currentEvent,eventType}',
          'incidentSourceState',p_incident#>>'{currentEvent,sourceState}',
          'incidentSeverity',p_incident#>>'{currentEvent,severity}',
          'incidentEvidenceFingerprint',
            p_incident#>>'{currentEvent,evidenceFingerprint}',
          'incidentState',p_decision->>'incidentState',
          'causeClass',p_decision->>'causeClass',
          'actionKey',p_decision->>'actionKey',
          'actionClass',p_decision->>'actionClass',
          'decision',p_decision->>'decision',
          'requiredControl',p_decision->>'requiredControl',
          'reasonCode',p_decision->>'reasonCode',
          'authorityExpansion',p_decision->'authorityExpansion',
          'automaticRepairAllowed',p_decision->'automaticRepairAllowed',
          'historyRewriteAllowed',p_decision->'historyRewriteAllowed',
          'mutatesAuthoritativeTruth',
            p_decision->'mutatesAuthoritativeTruth',
          'mutatesIncidentHistory',
            p_decision->'mutatesIncidentHistory',
          'executesAction',p_decision->'executesAction'
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer76_policy_fingerprint$;

revoke all on function foundation.foundation_promoted_release_case_audit_response_policy_fingerprint_v1(
  jsonb,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create table foundation.foundation_promoted_release_case_audit_response_execution_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  incident_event_id uuid not null
    references foundation.foundation_promoted_release_case_audit_incident_events(event_id),
  action_key text not null
    check (
      action_key in (
        'record-fresh-promotion-case-audit-observation',
        'materialise-current-owner-handoff'
      )
    ),
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
  before_snapshot jsonb not null
    check (jsonb_typeof(before_snapshot)='object'),
  action_result jsonb,
  after_snapshot jsonb,
  error_detail text,
  requested_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (action_result is null or jsonb_typeof(action_result)='object'),
  check (after_snapshot is null or jsonb_typeof(after_snapshot)='object'),
  check (
    (event_type='executed' and action_result is not null and error_detail is null)
    or (event_type='denied' and action_result is null and error_detail is null)
    or (event_type='failed' and action_result is null and error_detail is not null)
  ),
  unique(incident_event_id,action_key,policy_fingerprint)
);

alter table foundation.foundation_promoted_release_case_audit_response_execution_events
  enable row level security;

create policy foundation_runtime_case_audit_response_execution_select
on foundation.foundation_promoted_release_case_audit_response_execution_events
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_promoted_release_case_audit_response_execution_events
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.foundation_promoted_release_case_audit_response_execution_events
  to foundation_runtime,service_role;

create index foundation_promoted_release_case_audit_response_execution_incident_idx
  on foundation.foundation_promoted_release_case_audit_response_execution_events(
    incident_event_id,requested_at desc,event_sequence desc
  );

create index foundation_promoted_release_case_audit_response_execution_action_idx
  on foundation.foundation_promoted_release_case_audit_response_execution_events(
    action_key,requested_at desc,event_sequence desc
  );

create trigger foundation_promoted_release_case_audit_response_execution_append_only
before update or delete
on foundation.foundation_promoted_release_case_audit_response_execution_events
for each row execute function foundation.reject_append_only_mutation();


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
  v_existing foundation.foundation_promoted_release_case_audit_response_execution_events%rowtype;
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
  from foundation.foundation_promoted_release_case_audit_response_execution_events
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

    insert into foundation.foundation_promoted_release_case_audit_response_execution_events(
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

    insert into foundation.foundation_promoted_release_case_audit_response_execution_events(
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

    insert into foundation.foundation_promoted_release_case_audit_response_execution_events(
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
  from foundation.foundation_promoted_release_case_audit_response_execution_events
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
    from foundation.foundation_promoted_release_case_audit_response_execution_events
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
