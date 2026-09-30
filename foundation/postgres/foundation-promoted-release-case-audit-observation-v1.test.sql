begin;

create or replace function foundation.get_foundation_promoted_release_case_audit_v1(
  p_environment text default 'production',
  p_limit integer default 25,
  p_as_of timestamptz default now(),
  p_handoff_grace_seconds integer default 180
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l73_idle$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAudit',
      'shine-foundation/promoted-release-case-audit-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'overallState','idle',
    'structuralIntegrityPass',true,
    'incidentState','normal',
    'activeIncidentEventId',null,
    'activeIncidentEventAgeSeconds',null,
    'activeIncidentHandoffState','not-required',
    'handoffGraceSeconds',p_handoff_grace_seconds,
    'caseCount',0,
    'visibleCount',0,
    'invalidCount',0,
    'activeCaseCount',0,
    'pendingCaseCount',0,
    'terminalCaseCount',0,
    'historicalCaseCount',0,
    'hasMore',false,
    'cases','[]'::jsonb,
    'incidentSummary',jsonb_build_object(
      'state','normal','evaluatedAt',p_as_of
    ),
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'grantsApproval',false,
    'grantsExecutionAuthority',false
  );
$l73_idle$;

set local role service_role;
select foundation.record_foundation_promoted_release_case_audit_observation_v1(
  'production','2026-09-30T00:00:00+00:00'
);
select foundation.record_foundation_promoted_release_case_audit_observation_v1(
  'production','2026-09-30T00:05:00+00:00'
);
reset role;

do $l73_idle_checks$
declare
  first_row foundation.foundation_promoted_release_case_audit_observations%rowtype;
  second_row foundation.foundation_promoted_release_case_audit_observations%rowtype;
  summary jsonb;
begin
  select * into first_row
  from foundation.foundation_promoted_release_case_audit_observations
  where environment='production'
  order by observed_at,observation_sequence
  limit 1;

  select * into second_row
  from foundation.foundation_promoted_release_case_audit_observations
  where environment='production'
  order by observed_at desc,observation_sequence desc
  limit 1;

  if first_row.audit_state<>'idle'
     or first_row.structural_integrity_pass is not true
     or first_row.changed_from_previous is not true
     or second_row.changed_from_previous is not false
     or first_row.semantic_fingerprint is distinct from second_row.semantic_fingerprint then
    raise exception 'Layer 73 heartbeat semantics invalid';
  end if;

  summary:=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      'production','2026-09-30T00:05:00+00:00',600
    );

  if summary->>'state'<>'normal'
     or summary->>'observationFresh'<>'true'
     or summary->>'observationMatchesLive'<>'true'
     or summary#>>'{live,auditState}'<>'idle' then
    raise exception 'Layer 73 idle summary invalid: %',summary;
  end if;
end;
$l73_idle_checks$;


create or replace function foundation.get_foundation_promoted_release_case_audit_v1(
  p_environment text default 'production',
  p_limit integer default 25,
  p_as_of timestamptz default now(),
  p_handoff_grace_seconds integer default 180
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l73_gap$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAudit',
      'shine-foundation/promoted-release-case-audit-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'overallState','gap',
    'structuralIntegrityPass',false,
    'incidentState','critical',
    'activeIncidentEventId','73000000-0000-4000-8000-000000000001',
    'activeIncidentEventAgeSeconds',300,
    'activeIncidentHandoffState','missing',
    'handoffGraceSeconds',p_handoff_grace_seconds,
    'caseCount',0,
    'visibleCount',0,
    'invalidCount',0,
    'activeCaseCount',0,
    'pendingCaseCount',0,
    'terminalCaseCount',0,
    'historicalCaseCount',0,
    'hasMore',false,
    'cases','[]'::jsonb,
    'incidentSummary',jsonb_build_object(
      'state','critical','evaluatedAt',p_as_of
    ),
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'grantsApproval',false,
    'grantsExecutionAuthority',false
  );
$l73_gap$;

do $l73_drift_before_gap_record$
declare summary jsonb;
begin
  summary:=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      'production','2026-09-30T00:05:00+00:00',600
    );

  if summary->>'state'<>'drift'
     or summary->>'reasonCode'<>'promotion-case-audit-observation-drift'
     or summary->>'observationFresh'<>'true'
     or summary->>'observationMatchesLive'<>'false' then
    raise exception 'Layer 73 live audit drift must be visible: %',summary;
  end if;
end;
$l73_drift_before_gap_record$;

set local role service_role;
select foundation.record_foundation_promoted_release_case_audit_observation_v1(
  'production','2026-09-30T00:10:00+00:00'
);
reset role;

do $l73_gap_checks$
declare
  current_row foundation.foundation_promoted_release_case_audit_observations%rowtype;
  summary jsonb;
begin
  select * into current_row
  from foundation.current_foundation_promoted_release_case_audit_observation
  where environment='production';

  if current_row.audit_state<>'gap'
     or current_row.structural_integrity_pass is not false
     or current_row.active_incident_handoff_state<>'missing'
     or current_row.changed_from_previous is not true then
    raise exception 'Layer 73 recorded gap invalid';
  end if;

  summary:=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      'production','2026-09-30T00:10:00+00:00',600
    );

  if summary->>'state'<>'gap'
     or summary->>'reasonCode'<>'promotion-case-audit-gap'
     or summary->>'observationMatchesLive'<>'true' then
    raise exception 'Layer 73 gap summary invalid: %',summary;
  end if;
end;
$l73_gap_checks$;


create or replace function foundation.get_foundation_promoted_release_case_audit_v1(
  p_environment text default 'production',
  p_limit integer default 25,
  p_as_of timestamptz default now(),
  p_handoff_grace_seconds integer default 180
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l73_invalid$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAudit',
      'shine-foundation/promoted-release-case-audit-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'overallState','invalid',
    'structuralIntegrityPass',false,
    'incidentState','normal',
    'activeIncidentEventId',null,
    'activeIncidentEventAgeSeconds',null,
    'activeIncidentHandoffState','not-required',
    'handoffGraceSeconds',p_handoff_grace_seconds,
    'caseCount',1,
    'visibleCount',1,
    'invalidCount',1,
    'activeCaseCount',0,
    'pendingCaseCount',0,
    'terminalCaseCount',0,
    'historicalCaseCount',1,
    'hasMore',false,
    'cases',jsonb_build_array(
      jsonb_build_object(
        'handoffId','73000000-0000-4000-8000-000000000002',
        'caseStage','invalid',
        'historical',true,
        'structurallyValid',false,
        'integrityChecks',jsonb_build_object('handoff',false),
        'bindingChecks',jsonb_build_object('response',true)
      )
    ),
    'incidentSummary',jsonb_build_object(
      'state','normal','evaluatedAt',p_as_of
    ),
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'grantsApproval',false,
    'grantsExecutionAuthority',false
  );
$l73_invalid$;

set local role service_role;
select foundation.record_foundation_promoted_release_case_audit_observation_v1(
  'production','2026-09-30T00:15:00+00:00'
);
reset role;

do $l73_invalid_and_stale$
declare
  summary jsonb;
  stale_summary jsonb;
begin
  summary:=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      'production','2026-09-30T00:15:00+00:00',600
    );

  if summary->>'state'<>'invalid'
     or summary->>'reasonCode'<>'promotion-case-audit-invalid'
     or summary#>>'{live,invalidCount}'<>'1' then
    raise exception 'Layer 73 invalid summary invalid: %',summary;
  end if;

  stale_summary:=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      'production','2026-09-30T00:26:01+00:00',600
    );

  if stale_summary->>'state'<>'unknown'
     or stale_summary->>'reasonCode'<>'promotion-case-audit-observation-stale'
     or stale_summary->>'observationFresh'<>'false' then
    raise exception 'Layer 73 stale observer must fail visibly: %',stale_summary;
  end if;
end;
$l73_invalid_and_stale$;


do $l73_privileges$
begin
  if has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_case_audit_observations',
       'INSERT'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.record_foundation_promoted_release_case_audit_observation_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.record_foundation_promoted_release_case_audit_observation_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_has_role(
       'foundation_gateway','foundation_runtime','MEMBER'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 73 privilege boundary invalid';
  end if;
end;
$l73_privileges$;


do $l73_append_only$
declare id uuid;
begin
  select observation_id into id
  from foundation.current_foundation_promoted_release_case_audit_observation
  where environment='production';

  begin
    update foundation.foundation_promoted_release_case_audit_observations
    set audit_state='idle'
    where observation_id=id;
    raise exception 'Layer 73 audit observation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l73_append_only$;

rollback;
