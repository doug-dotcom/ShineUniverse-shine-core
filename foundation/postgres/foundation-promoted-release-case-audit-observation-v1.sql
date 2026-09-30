-- Foundation Layer 73: continuous promotion-trust case-audit observations.
-- Layer 72 proves case-chain integrity on demand. Layer 73 records that audit
-- durably and makes stale, missing or drifted audit evidence visible.

create or replace function foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
  p_snapshot jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer73_fingerprint$
  select encode(
    extensions.digest(
      convert_to(
        (
          p_snapshot
          - 'evaluatedAt'
          - 'activeIncidentEventAgeSeconds'
          - 'incidentSummary'
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer73_fingerprint$;

revoke all on function foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(jsonb)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create table foundation.foundation_promoted_release_case_audit_observations (
  observation_sequence bigint generated always as identity primary key,
  observation_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  audit_state text not null
    check (audit_state in ('idle','active-work','historical','gap','invalid')),
  structural_integrity_pass boolean not null,
  incident_state text not null
    check (char_length(incident_state) between 1 and 64),
  active_incident_event_id uuid,
  active_incident_handoff_state text not null
    check (
      active_incident_handoff_state in (
        'not-required','grace','present','missing'
      )
    ),
  case_count integer not null check (case_count>=0),
  invalid_count integer not null check (invalid_count>=0),
  active_case_count integer not null check (active_case_count>=0),
  pending_case_count integer not null check (pending_case_count>=0),
  terminal_case_count integer not null check (terminal_case_count>=0),
  historical_case_count integer not null check (historical_case_count>=0),
  semantic_fingerprint text not null
    check (semantic_fingerprint ~ '^[a-f0-9]{64}$'),
  changed_from_previous boolean not null,
  snapshot jsonb not null
    check (jsonb_typeof(snapshot)='object'),
  observed_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (
    (audit_state in ('gap','invalid') and not structural_integrity_pass)
    or
    (audit_state in ('idle','active-work','historical') and structural_integrity_pass)
  )
);

alter table foundation.foundation_promoted_release_case_audit_observations
  enable row level security;

create policy foundation_runtime_case_audit_observations_select
on foundation.foundation_promoted_release_case_audit_observations
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_promoted_release_case_audit_observations
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.foundation_promoted_release_case_audit_observations
  to foundation_runtime,service_role;

create index foundation_promoted_release_case_audit_observations_env_time_idx
  on foundation.foundation_promoted_release_case_audit_observations(
    environment,observed_at desc,observation_sequence desc
  );

create trigger foundation_promoted_release_case_audit_observations_append_only
before update or delete
on foundation.foundation_promoted_release_case_audit_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_foundation_promoted_release_case_audit_observation
with (security_invoker=true)
as
select distinct on (environment)
  observation_sequence,
  observation_id,
  environment,
  audit_state,
  structural_integrity_pass,
  incident_state,
  active_incident_event_id,
  active_incident_handoff_state,
  case_count,
  invalid_count,
  active_case_count,
  pending_case_count,
  terminal_case_count,
  historical_case_count,
  semantic_fingerprint,
  changed_from_previous,
  snapshot,
  observed_at,
  recorded_at
from foundation.foundation_promoted_release_case_audit_observations
order by environment,observed_at desc,observation_sequence desc;

revoke all on foundation.current_foundation_promoted_release_case_audit_observation
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant select on foundation.current_foundation_promoted_release_case_audit_observation
  to foundation_runtime,service_role;


create or replace function foundation.record_foundation_promoted_release_case_audit_observation_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer73_record$
declare
  v_snapshot jsonb;
  v_prior foundation.foundation_promoted_release_case_audit_observations%rowtype;
  v_fingerprint text;
  v_audit_state text;
  v_integrity boolean;
  v_changed boolean;
  v_observation_id uuid;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_observed_at is null then
    raise exception 'promoted-release-case-audit-observation-input-invalid';
  end if;

  v_snapshot :=
    foundation.get_foundation_promoted_release_case_audit_v1(
      p_environment,100,p_observed_at,180
    );

  if v_snapshot->>'foundationPromotedReleaseCaseAudit'
       is distinct from 'shine-foundation/promoted-release-case-audit-v1'
     or v_snapshot->>'schemaVersion' is distinct from '1.0.0' then
    raise exception 'promoted-release-case-audit-observation-contract-invalid';
  end if;

  v_audit_state := v_snapshot->>'overallState';
  v_integrity := coalesce(
    (v_snapshot->>'structuralIntegrityPass')::boolean,
    false
  );

  if v_audit_state not in ('idle','active-work','historical','gap','invalid')
     or (
       v_audit_state in ('gap','invalid')
       and v_integrity
     )
     or (
       v_audit_state in ('idle','active-work','historical')
       and not v_integrity
     ) then
    raise exception 'promoted-release-case-audit-observation-state-invalid';
  end if;

  v_fingerprint :=
    foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
      v_snapshot
    );

  select * into v_prior
  from foundation.current_foundation_promoted_release_case_audit_observation
  where environment=p_environment;

  v_changed :=
    v_prior.observation_id is null
    or v_prior.semantic_fingerprint is distinct from v_fingerprint;

  insert into foundation.foundation_promoted_release_case_audit_observations(
    environment,
    audit_state,
    structural_integrity_pass,
    incident_state,
    active_incident_event_id,
    active_incident_handoff_state,
    case_count,
    invalid_count,
    active_case_count,
    pending_case_count,
    terminal_case_count,
    historical_case_count,
    semantic_fingerprint,
    changed_from_previous,
    snapshot,
    observed_at
  )
  values (
    p_environment,
    v_audit_state,
    v_integrity,
    coalesce(v_snapshot->>'incidentState','unknown'),
    nullif(v_snapshot->>'activeIncidentEventId','')::uuid,
    coalesce(v_snapshot->>'activeIncidentHandoffState','not-required'),
    coalesce((v_snapshot->>'caseCount')::integer,0),
    coalesce((v_snapshot->>'invalidCount')::integer,0),
    coalesce((v_snapshot->>'activeCaseCount')::integer,0),
    coalesce((v_snapshot->>'pendingCaseCount')::integer,0),
    coalesce((v_snapshot->>'terminalCaseCount')::integer,0),
    coalesce((v_snapshot->>'historicalCaseCount')::integer,0),
    v_fingerprint,
    v_changed,
    v_snapshot,
    p_observed_at
  )
  returning observation_id into v_observation_id;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationRecord',
      'shine-foundation/promoted-release-case-audit-observation-record-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'observationId',v_observation_id,
    'observedAt',p_observed_at,
    'auditState',v_audit_state,
    'structuralIntegrityPass',v_integrity,
    'semanticFingerprint',v_fingerprint,
    'changedFromPrevious',v_changed,
    'status',case
      when v_changed then 'recorded-change'
      else 'recorded-heartbeat'
    end,
    'automaticRepair',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer73_record$;

revoke all on function foundation.record_foundation_promoted_release_case_audit_observation_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.record_foundation_promoted_release_case_audit_observation_v1(
  text,timestamptz
) to service_role;


create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer73_summary$
declare
  v_live jsonb;
  v_live_fingerprint text;
  v_current foundation.foundation_promoted_release_case_audit_observations%rowtype;
  v_age_seconds integer;
  v_fresh boolean := false;
  v_matches_live boolean := false;
  v_state text;
  v_reason text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_max_age_seconds<60
     or p_max_age_seconds>3600 then
    raise exception 'promoted-release-case-audit-observation-summary-input-invalid';
  end if;

  v_live :=
    foundation.get_foundation_promoted_release_case_audit_v1(
      p_environment,100,p_as_of,180
    );

  v_live_fingerprint :=
    foundation.foundation_promoted_release_case_audit_semantic_fingerprint_v1(
      v_live
    );

  select * into v_current
  from foundation.current_foundation_promoted_release_case_audit_observation
  where environment=p_environment;

  if v_current.observation_id is not null then
    v_age_seconds := greatest(
      0,
      floor(extract(epoch from (p_as_of-v_current.observed_at)))::integer
    );

    v_fresh :=
      v_current.observed_at<=p_as_of
      and v_age_seconds<=p_max_age_seconds;

    v_matches_live :=
      v_current.semantic_fingerprint is not distinct from v_live_fingerprint;
  end if;

  if v_current.observation_id is null then
    v_state := 'unknown';
    v_reason := 'promotion-case-audit-observation-missing';
  elsif not v_fresh then
    v_state := 'unknown';
    v_reason := 'promotion-case-audit-observation-stale';
  elsif not v_matches_live then
    v_state := 'drift';
    v_reason := 'promotion-case-audit-observation-drift';
  elsif v_live->>'overallState'='invalid' then
    v_state := 'invalid';
    v_reason := 'promotion-case-audit-invalid';
  elsif v_live->>'overallState'='gap' then
    v_state := 'gap';
    v_reason := 'promotion-case-audit-gap';
  else
    v_state := 'normal';
    v_reason := 'promotion-case-audit-current';
  end if;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'reasonCode',v_reason,
    'observationFresh',v_fresh,
    'observationMatchesLive',v_matches_live,
    'maxAgeSeconds',p_max_age_seconds,
    'observationAgeSeconds',v_age_seconds,
    'live',jsonb_build_object(
      'auditState',v_live->>'overallState',
      'structuralIntegrityPass',v_live->'structuralIntegrityPass',
      'incidentState',v_live->>'incidentState',
      'activeIncidentEventId',v_live->>'activeIncidentEventId',
      'activeIncidentHandoffState',v_live->>'activeIncidentHandoffState',
      'caseCount',v_live->'caseCount',
      'invalidCount',v_live->'invalidCount',
      'activeCaseCount',v_live->'activeCaseCount',
      'pendingCaseCount',v_live->'pendingCaseCount',
      'terminalCaseCount',v_live->'terminalCaseCount',
      'historicalCaseCount',v_live->'historicalCaseCount',
      'semanticFingerprint',v_live_fingerprint
    ),
    'observation',case
      when v_current.observation_id is null then null
      else jsonb_build_object(
        'observationId',v_current.observation_id,
        'auditState',v_current.audit_state,
        'structuralIntegrityPass',v_current.structural_integrity_pass,
        'incidentState',v_current.incident_state,
        'activeIncidentEventId',v_current.active_incident_event_id,
        'activeIncidentHandoffState',v_current.active_incident_handoff_state,
        'caseCount',v_current.case_count,
        'invalidCount',v_current.invalid_count,
        'activeCaseCount',v_current.active_case_count,
        'pendingCaseCount',v_current.pending_case_count,
        'terminalCaseCount',v_current.terminal_case_count,
        'historicalCaseCount',v_current.historical_case_count,
        'semanticFingerprint',v_current.semantic_fingerprint,
        'changedFromPrevious',v_current.changed_from_previous,
        'observedAt',v_current.observed_at
      )
    end,
    'recommendedAction',case v_state
      when 'normal' then 'none'
      when 'gap' then 'investigate-promotion-case-chain-gap'
      when 'invalid' then 'investigate-promotion-case-chain-integrity'
      when 'drift' then 'record-fresh-promotion-case-audit-observation'
      else 'restore-promotion-case-audit-observation-freshness'
    end,
    'automaticRepair',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer73_summary$;

revoke all on function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
