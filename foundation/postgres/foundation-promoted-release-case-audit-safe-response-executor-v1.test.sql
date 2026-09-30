begin;

-- Seed one real Layer-74 incident row. All downstream policy/target functions are
-- transaction-local deterministic stubs so the dispatcher itself can be proven.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '76000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','opened','gap','critical',
  'promotion-case-audit-gap',repeat('a',64),null,
  now()-interval '10 minutes',300,300,'{"test":true}'::jsonb,
  now()-interval '5 minutes','test:layer76:gap'
);

create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_gap_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','critical','activeIncidentCount',1,'watchCount',0,
    'caseAuditState','gap','caseAuditReasonCode','promotion-case-audit-gap',
    'observationFresh',true,'observationMatchesLive',true,
    'currentEvent',jsonb_build_object(
      'eventId','76000000-0000-4000-8000-000000000001',
      'eventType','opened','sourceState','gap','severity','critical',
      'reasonCode','promotion-case-audit-gap',
      'evidenceFingerprint',repeat('a',64)
    )
  );
$l76_gap_incident$;

create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_gap_audit$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','gap','reasonCode','promotion-case-audit-gap',
    'observationFresh',true,'observationMatchesLive',true
  );
$l76_gap_audit$;

create or replace function foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_gap_policy$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentResponseDecision',
      'shine-foundation/promoted-release-case-audit-incident-response-decision-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','critical','causeClass','case-chain-gap',
    'actionKey',p_action_key,
    'actionClass',case
      when p_action_key='materialise-current-owner-handoff'
        then 'work-materialisation'
      else 'unknown'
    end,
    'decision',case
      when p_action_key='materialise-current-owner-handoff'
        then 'admit'
      else 'deny'
    end,
    'requiredControl',case
      when p_action_key='materialise-current-owner-handoff'
        then 'layer-67-bounded-generator'
      else 'prohibited'
    end,
    'reasonCode','test-layer76-gap-policy',
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'executesAction',false
  );
$l76_gap_policy$;

create or replace function foundation.generate_foundation_promoted_release_owner_handoff_v1(
  p_environment text default 'production',
  p_created_at timestamptz default now()
)
returns jsonb language sql security definer set search_path='' as $l76_handoff_target$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffResponse',
      'shine-foundation/promoted-release-owner-handoff-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,
    'status','generated',
    'handoffId','76000000-0000-4000-8000-000000000010',
    'incidentEventId','76000000-0000-4000-8000-000000000099',
    'ownerServiceId','foundation.gateway',
    'ownerComponent','shine-core',
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesAction',false
  );
$l76_handoff_target$;

set local role service_role;

do $l76_gap_execution$
declare
  result jsonb;
  replay jsonb;
  summary jsonb;
begin
  result:=foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
    'materialise-current-owner-handoff','production',now()
  );

  if result->>'status'<>'executed'
     or result->>'actionKey'<>'materialise-current-owner-handoff'
     or result#>>'{actionResult,status}'<>'generated'
     or result->>'executesOnlyBoundedSafeAction'<>'true'
     or result->>'arbitrarySqlExecution'<>'false'
     or result->>'historyRewritePerformed'<>'false'
     or result->>'releaseTruthMutationPerformed'<>'false'
     or result->>'incidentHistoryMutationPerformed'<>'false' then
    raise exception 'Layer 76 bounded GAP execution invalid: %',result;
  end if;

  replay:=foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
    'materialise-current-owner-handoff','production',now()
  );

  if replay->>'status'<>'existing'
     or replay->>'eventId'<>result->>'eventId'
     or replay#>>'{actionResult,status}'<>'generated' then
    raise exception 'Layer 76 semantic replay must reuse execution receipt: %',replay;
  end if;

  summary:=foundation.get_case_audit_safe_response_exec_summary_v1(
    'production',25
  );

  if summary->>'totalCount'<>'1'
     or summary->>'executedCount'<>'1'
     or summary->>'deniedCount'<>'0'
     or summary->>'failedCount'<>'0' then
    raise exception 'Layer 76 execution summary invalid: %',summary;
  end if;
end;
$l76_gap_execution$;

reset role;


-- New observer-freshness incident/evidence permits only the Layer-73 recorder.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '76000000-0000-4000-8000-000000000002'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','changed','unknown','warning',
  'promotion-case-audit-observation-stale',repeat('b',64),null,
  now()-interval '10 minutes',300,600,'{"test":true}'::jsonb,
  now()-interval '1 minute','test:layer76:unknown'
);

create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_unknown_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','warning','activeIncidentCount',1,'watchCount',0,
    'caseAuditState','unknown',
    'caseAuditReasonCode','promotion-case-audit-observation-stale',
    'observationFresh',false,'observationMatchesLive',true,
    'currentEvent',jsonb_build_object(
      'eventId','76000000-0000-4000-8000-000000000002',
      'eventType','changed','sourceState','unknown','severity','warning',
      'reasonCode','promotion-case-audit-observation-stale',
      'evidenceFingerprint',repeat('b',64)
    )
  );
$l76_unknown_incident$;

create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_unknown_audit$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','unknown','reasonCode','promotion-case-audit-observation-stale',
    'observationFresh',false,'observationMatchesLive',true
  );
$l76_unknown_audit$;

create or replace function foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_unknown_policy$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentResponseDecision',
      'shine-foundation/promoted-release-case-audit-incident-response-decision-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','warning','causeClass','observer-freshness',
    'actionKey',p_action_key,
    'actionClass',case
      when p_action_key='record-fresh-promotion-case-audit-observation'
        then 'evidence'
      else 'unknown'
    end,
    'decision',case
      when p_action_key='record-fresh-promotion-case-audit-observation'
        then 'admit'
      else 'deny'
    end,
    'requiredControl',case
      when p_action_key='record-fresh-promotion-case-audit-observation'
        then 'evidence-only'
      else 'prohibited'
    end,
    'reasonCode','test-layer76-observer-policy',
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'executesAction',false
  );
$l76_unknown_policy$;

create or replace function foundation.record_foundation_promoted_release_case_audit_observation_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now()
)
returns jsonb language sql security definer set search_path='' as $l76_observation_target$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationRecord',
      'shine-foundation/promoted-release-case-audit-observation-record-v1',
    'schemaVersion','1.0.0','environment',p_environment,
    'status','recorded-heartbeat',
    'observationId','76000000-0000-4000-8000-000000000020',
    'auditState','idle',
    'structuralIntegrityPass',true,
    'changedFromPrevious',false,
    'semanticFingerprint',repeat('c',64)
  );
$l76_observation_target$;

set local role service_role;

do $l76_observer_execution$
declare result jsonb;
begin
  result:=foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
    'record-fresh-promotion-case-audit-observation','production',now()
  );

  if result->>'status'<>'executed'
     or result->>'actionKey'<>'record-fresh-promotion-case-audit-observation'
     or result#>>'{actionResult,status}'<>'recorded-heartbeat'
     or result->>'releaseTruthMutationPerformed'<>'false'
     or result->>'historyRewritePerformed'<>'false' then
    raise exception 'Layer 76 bounded observer execution invalid: %',result;
  end if;
end;
$l76_observer_execution$;

reset role;


-- Policy denial for a supported safe action records denial and does not dispatch.
create or replace function foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_denied_policy$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentResponseDecision',
      'shine-foundation/promoted-release-case-audit-incident-response-decision-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','warning','causeClass','observer-freshness',
    'actionKey',p_action_key,'actionClass','evidence',
    'decision','deny','requiredControl','prohibited',
    'reasonCode','test-layer76-denied-policy',
    'authorityExpansion',false,'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,'executesAction',false
  );
$l76_denied_policy$;

-- A fresh incident event changes the policy fingerprint/scope so denial can be recorded.
insert into foundation.foundation_promoted_release_case_audit_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,case_audit_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '76000000-0000-4000-8000-000000000003'::uuid,
  'production:promoted_release_case_audit','production',
  'promoted_release_case_audit','changed','unknown','warning',
  'promotion-case-audit-observation-stale',repeat('d',64),null,
  now()-interval '10 minutes',300,660,'{"test":true}'::jsonb,
  now(),'test:layer76:denied'
);

create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l76_denied_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','warning','activeIncidentCount',1,'watchCount',0,
    'caseAuditState','unknown',
    'caseAuditReasonCode','promotion-case-audit-observation-stale',
    'currentEvent',jsonb_build_object(
      'eventId','76000000-0000-4000-8000-000000000003',
      'eventType','changed','sourceState','unknown','severity','warning',
      'reasonCode','promotion-case-audit-observation-stale',
      'evidenceFingerprint',repeat('d',64)
    )
  );
$l76_denied_incident$;

set local role service_role;

do $l76_denied$
declare result jsonb;
begin
  result:=foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
    'record-fresh-promotion-case-audit-observation','production',now()
  );

  if result->>'status'<>'denied'
     or result->>'reasonCode'<>
        'promotion-case-audit-safe-response-policy-not-admitted'
     or result->>'releaseTruthMutationPerformed'<>'false'
     or result->>'historyRewritePerformed'<>'false' then
    raise exception 'Layer 76 denied execution invalid: %',result;
  end if;
end;
$l76_denied$;

reset role;


do $l76_unsupported_action$
begin
  begin
    perform foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(
      'rewrite-case-chain-history','production',now()
    );
    raise exception 'Layer 76 unexpectedly accepted unsupported history rewrite';
  exception
    when others then
      if sqlerrm<>'promotion-case-audit-safe-response-action-not-supported' then
        raise;
      end if;
  end;
end;
$l76_unsupported_action$;


do $l76_function_identifier_closure$
begin
  if to_regprocedure(
       'foundation.case_audit_safe_response_policy_fingerprint_v1(jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'foundation.get_case_audit_safe_response_exec_summary_v1(text,integer)'
     ) is null
     or to_regprocedure(
       'foundation.foundation_promoted_release_case_audit_response_policy_fingerpr(jsonb,jsonb)'
     ) is not null
     or to_regprocedure(
       'foundation.get_foundation_promoted_release_case_audit_safe_response_execut(text,integer)'
     ) is not null then
    raise exception 'Layer 76 canonical function identifier convergence invalid';
  end if;
end;
$l76_function_identifier_closure$;


do $l76_privileges$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.execute_foundation_promoted_release_case_audit_safe_response_v1(text,text,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_safe_response_exec_events',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_safe_response_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_safe_response_exec_summary_v1(text,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_safe_response_exec_summary_v1(text,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 76 safe-response executor privilege boundary invalid';
  end if;
end;
$l76_privileges$;


do $l76_append_only$
declare id uuid;
begin
  select event_id into id
  from foundation.case_audit_safe_response_exec_events
  limit 1;

  begin
    update foundation.case_audit_safe_response_exec_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 76 execution history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l76_append_only$;

rollback;
