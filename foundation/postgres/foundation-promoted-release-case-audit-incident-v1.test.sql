begin;

-- One real Layer-73 observation row for FK-backed incident evidence.
create or replace function foundation.get_foundation_promoted_release_case_audit_v1(
  p_environment text default 'production',
  p_limit integer default 25,
  p_as_of timestamptz default now(),
  p_handoff_grace_seconds integer default 180
)
returns jsonb language sql stable security definer set search_path='' as $l74_idle_audit$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAudit','shine-foundation/promoted-release-case-audit-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'overallState','idle','structuralIntegrityPass',true,'incidentState','normal',
    'activeIncidentEventId',null,'activeIncidentEventAgeSeconds',null,
    'activeIncidentHandoffState','not-required','handoffGraceSeconds',p_handoff_grace_seconds,
    'caseCount',0,'visibleCount',0,'invalidCount',0,'activeCaseCount',0,
    'pendingCaseCount',0,'terminalCaseCount',0,'historicalCaseCount',0,
    'hasMore',false,'cases','[]'::jsonb,
    'incidentSummary',jsonb_build_object('state','normal','evaluatedAt',p_as_of),
    'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false,
    'grantsApproval',false,'grantsExecutionAuthority',false
  );
$l74_idle_audit$;

set local role service_role;
select foundation.record_foundation_promoted_release_case_audit_observation_v1(
  'production',now()
);
reset role;

do $l74_normal$
declare s jsonb; t jsonb;
begin
  s:=foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
    'production',now(),600
  );
  t:=foundation.transition_foundation_promoted_release_case_audit_incident_v1(
    'production',s,now(),300
  );

  if t->>'sourceState'<>'normal'
     or t->>'eventCreated'<>'false'
     or t->>'activeIncidentCount'<>'0'
     or t->>'watchCount'<>'0' then
    raise exception 'Layer 74 normal state must not create incident: %',t;
  end if;
end;
$l74_normal$;


-- Deterministic GAP summary. Same evidence persists 300s: watch -> critical incident.
create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l74_gap_summary$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','gap','reasonCode','promotion-case-audit-gap',
    'observationFresh',true,'observationMatchesLive',true,
    'live',jsonb_build_object(
      'auditState','gap',
      'structuralIntegrityPass',false,
      'incidentState','critical',
      'activeIncidentEventId','74000000-0000-4000-8000-000000000001',
      'activeIncidentHandoffState','missing',
      'caseCount',0,'invalidCount',0,'activeCaseCount',0,
      'pendingCaseCount',0,'terminalCaseCount',0,'historicalCaseCount',0,
      'semanticFingerprint',repeat('a',64)
    ),
    'observation',jsonb_build_object(
      'observationId',(
        select observation_id::text
        from foundation.current_foundation_promoted_release_case_audit_observation
        where environment='production'
      ),
      'auditState','gap',
      'structuralIntegrityPass',false,
      'semanticFingerprint',repeat('a',64)
    )
  );
$l74_gap_summary$;

do $l74_gap_lifecycle$
declare
  snap jsonb;
  first_event jsonb;
  opened_event jsonb;
  unchanged_event jsonb;
begin
  snap:=foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
    'production','2026-09-30T01:00:00+00:00',600
  );

  first_event:=foundation.transition_foundation_promoted_release_case_audit_incident_v1(
    'production',snap,'2026-09-30T01:00:00+00:00',300
  );

  if first_event->>'eventType'<>'detected'
     or first_event->>'severity'<>'critical'
     or first_event->>'activeIncidentCount'<>'0'
     or first_event->>'watchCount'<>'1' then
    raise exception 'Layer 74 first GAP sample must create critical watch: %',first_event;
  end if;

  opened_event:=foundation.transition_foundation_promoted_release_case_audit_incident_v1(
    'production',snap,'2026-09-30T01:05:00+00:00',300
  );

  if opened_event->>'eventType'<>'opened'
     or opened_event->>'severity'<>'critical'
     or opened_event->>'persistenceSeconds'<>'300'
     or opened_event->>'activeIncidentCount'<>'1'
     or opened_event->>'watchCount'<>'0' then
    raise exception 'Layer 74 persistent GAP must open critical incident: %',opened_event;
  end if;

  unchanged_event:=foundation.transition_foundation_promoted_release_case_audit_incident_v1(
    'production',snap,'2026-09-30T01:10:00+00:00',300
  );

  if unchanged_event->>'eventCreated'<>'false'
     or unchanged_event->>'activeIncidentCount'<>'1' then
    raise exception 'Layer 74 unchanged open GAP must not append noise: %',unchanged_event;
  end if;
end;
$l74_gap_lifecycle$;


-- INVALID while open changes evidence and preserves original detection clock.
create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l74_invalid_summary$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','invalid','reasonCode','promotion-case-audit-invalid',
    'observationFresh',true,'observationMatchesLive',true,
    'live',jsonb_build_object(
      'auditState','invalid',
      'structuralIntegrityPass',false,
      'incidentState','normal',
      'activeIncidentEventId',null,
      'activeIncidentHandoffState','not-required',
      'caseCount',1,'invalidCount',1,'activeCaseCount',0,
      'pendingCaseCount',0,'terminalCaseCount',0,'historicalCaseCount',1,
      'semanticFingerprint',repeat('b',64)
    ),
    'observation',jsonb_build_object(
      'observationId',(
        select observation_id::text
        from foundation.current_foundation_promoted_release_case_audit_observation
        where environment='production'
      ),
      'auditState','invalid',
      'structuralIntegrityPass',false,
      'semanticFingerprint',repeat('b',64)
    )
  );
$l74_invalid_summary$;

do $l74_changed$
declare snap jsonb; changed_event jsonb;
begin
  snap:=foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
    'production','2026-09-30T01:11:00+00:00',600
  );

  changed_event:=foundation.transition_foundation_promoted_release_case_audit_incident_v1(
    'production',snap,'2026-09-30T01:11:00+00:00',300
  );

  if changed_event->>'eventType'<>'changed'
     or changed_event->>'severity'<>'critical'
     or changed_event->>'sourceState'<>'invalid'
     or changed_event->>'persistenceSeconds'<>'660'
     or changed_event->>'activeIncidentCount'<>'1' then
    raise exception 'Layer 74 material integrity change must append CHANGED: %',changed_event;
  end if;
end;
$l74_changed$;


-- NORMAL explicitly recovers.
create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l74_normal_summary$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','normal','reasonCode','promotion-case-audit-current',
    'observationFresh',true,'observationMatchesLive',true,
    'live',jsonb_build_object(
      'auditState','idle','structuralIntegrityPass',true,
      'semanticFingerprint',repeat('c',64)
    ),
    'observation',jsonb_build_object(
      'observationId',(
        select observation_id::text
        from foundation.current_foundation_promoted_release_case_audit_observation
        where environment='production'
      ),
      'auditState','idle','structuralIntegrityPass',true,
      'semanticFingerprint',repeat('c',64)
    )
  );
$l74_normal_summary$;

do $l74_recovery$
declare snap jsonb; recovered jsonb; summary jsonb;
begin
  snap:=foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
    'production','2026-09-30T01:12:00+00:00',600
  );

  recovered:=foundation.transition_foundation_promoted_release_case_audit_incident_v1(
    'production',snap,'2026-09-30T01:12:00+00:00',300
  );

  if recovered->>'eventType'<>'recovered'
     or recovered->>'severity'<>'info'
     or recovered->>'activeIncidentCount'<>'0'
     or recovered->>'watchCount'<>'0' then
    raise exception 'Layer 74 recovery invalid: %',recovered;
  end if;

  summary:=foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
    'production','2026-09-30T01:12:00+00:00',600
  );

  if summary->>'state'<>'normal'
     or summary->>'activeIncidentCount'<>'0'
     or summary->>'watchCount'<>'0'
     or summary#>>'{currentEvent,eventType}'<>'recovered'
     or summary->>'automaticRepair'<>'false' then
    raise exception 'Layer 74 recovered summary invalid: %',summary;
  end if;
end;
$l74_recovery$;


-- UNKNOWN freshness is warning-class and starts a watch.
create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l74_unknown_summary$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','unknown','reasonCode','promotion-case-audit-observation-stale',
    'observationFresh',false,'observationMatchesLive',true,
    'live',jsonb_build_object(
      'auditState','idle','structuralIntegrityPass',true,
      'semanticFingerprint',repeat('c',64)
    ),
    'observation',null
  );
$l74_unknown_summary$;

do $l74_unknown$
declare snap jsonb; detected jsonb;
begin
  snap:=foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
    'production','2026-09-30T02:00:00+00:00',600
  );

  detected:=foundation.transition_foundation_promoted_release_case_audit_incident_v1(
    'production',snap,'2026-09-30T02:00:00+00:00',300
  );

  if detected->>'eventType'<>'detected'
     or detected->>'severity'<>'warning'
     or detected->>'sourceState'<>'unknown'
     or detected->>'watchCount'<>'1' then
    raise exception 'Layer 74 UNKNOWN must start warning watch: %',detected;
  end if;
end;
$l74_unknown$;


do $l74_privileges$
begin
  if has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_case_audit_incident_events',
       'INSERT'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.run_foundation_promoted_release_case_audit_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_foundation_promoted_release_case_audit_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_has_role(
       'foundation_gateway','foundation_runtime','MEMBER'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 74 case-audit incident privilege boundary invalid';
  end if;
end;
$l74_privileges$;


do $l74_append_only$
declare id uuid;
begin
  select event_id into id
  from foundation.current_foundation_promoted_release_case_audit_incident_state
  where environment='production';

  begin
    update foundation.foundation_promoted_release_case_audit_incident_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 74 case-audit incident history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l74_append_only$;

rollback;
