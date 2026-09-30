-- Foundation Layer 74: incident lifecycle for promotion-trust case-audit health.
-- Layer 73 records case-audit truth continuously. Layer 74 escalates persistent
-- GAP/INVALID/DRIFT/UNKNOWN observer states without granting repair authority.

create or replace function foundation.foundation_promoted_release_case_audit_incident_fingerprint_v1(
  p_snapshot jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer74_fingerprint$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'state',p_snapshot->>'state',
          'reasonCode',p_snapshot->>'reasonCode',
          'liveAuditState',p_snapshot#>>'{live,auditState}',
          'liveStructuralIntegrityPass',
            p_snapshot#>'{live,structuralIntegrityPass}',
          'liveIncidentState',p_snapshot#>>'{live,incidentState}',
          'liveActiveIncidentEventId',
            p_snapshot#>>'{live,activeIncidentEventId}',
          'liveActiveIncidentHandoffState',
            p_snapshot#>>'{live,activeIncidentHandoffState}',
          'liveCaseCount',p_snapshot#>'{live,caseCount}',
          'liveInvalidCount',p_snapshot#>'{live,invalidCount}',
          'liveActiveCaseCount',p_snapshot#>'{live,activeCaseCount}',
          'livePendingCaseCount',p_snapshot#>'{live,pendingCaseCount}',
          'liveTerminalCaseCount',p_snapshot#>'{live,terminalCaseCount}',
          'liveHistoricalCaseCount',p_snapshot#>'{live,historicalCaseCount}',
          'liveSemanticFingerprint',
            p_snapshot#>>'{live,semanticFingerprint}',
          'observationAuditState',
            p_snapshot#>>'{observation,auditState}',
          'observationStructuralIntegrityPass',
            p_snapshot#>'{observation,structuralIntegrityPass}',
          'observationSemanticFingerprint',
            p_snapshot#>>'{observation,semanticFingerprint}'
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer74_fingerprint$;

revoke all on function foundation.foundation_promoted_release_case_audit_incident_fingerprint_v1(jsonb)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create table foundation.foundation_promoted_release_case_audit_incident_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  incident_key text not null
    check (incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  domain text not null
    check (domain='promoted_release_case_audit'),
  event_type text not null
    check (event_type in ('detected','opened','changed','recovered')),
  source_state text not null
    check (source_state in ('normal','gap','invalid','drift','unknown')),
  severity text not null
    check (severity in ('info','warning','critical')),
  reason_code text not null
    check (char_length(reason_code) between 1 and 160),
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  case_audit_observation_id uuid
    references foundation.foundation_promoted_release_case_audit_observations(observation_id),
  detection_started_at timestamptz not null,
  persistence_threshold_seconds integer not null
    check (persistence_threshold_seconds between 60 and 3600),
  persistence_seconds integer not null
    check (persistence_seconds>=0),
  snapshot jsonb not null
    check (jsonb_typeof(snapshot)='object'),
  occurred_at timestamptz not null,
  evidence_ref text not null unique,
  recorded_at timestamptz not null default now(),
  check (
    (
      event_type in ('detected','opened','changed')
      and source_state in ('gap','invalid','drift','unknown')
      and (
        (source_state in ('gap','invalid') and severity='critical')
        or
        (source_state in ('drift','unknown') and severity='warning')
      )
    )
    or
    (
      event_type='recovered'
      and source_state='normal'
      and severity='info'
    )
  )
);

alter table foundation.foundation_promoted_release_case_audit_incident_events
  enable row level security;

create policy foundation_runtime_case_audit_incident_events_select
on foundation.foundation_promoted_release_case_audit_incident_events
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_promoted_release_case_audit_incident_events
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.foundation_promoted_release_case_audit_incident_events
  to foundation_runtime,service_role;

create index foundation_promoted_release_case_audit_incident_events_key_time_idx
  on foundation.foundation_promoted_release_case_audit_incident_events(
    incident_key,occurred_at desc,event_sequence desc
  );

create index foundation_promoted_release_case_audit_incident_events_observation_idx
  on foundation.foundation_promoted_release_case_audit_incident_events(
    case_audit_observation_id
  );

create trigger foundation_promoted_release_case_audit_incident_events_append_only
before update or delete
on foundation.foundation_promoted_release_case_audit_incident_events
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_foundation_promoted_release_case_audit_incident_state
with (security_invoker=true)
as
select distinct on (incident_key)
  event_sequence,
  event_id,
  incident_key,
  environment,
  domain,
  event_type,
  source_state,
  severity,
  reason_code,
  evidence_fingerprint,
  case_audit_observation_id,
  detection_started_at,
  persistence_threshold_seconds,
  persistence_seconds,
  snapshot,
  occurred_at,
  evidence_ref,
  recorded_at
from foundation.foundation_promoted_release_case_audit_incident_events
order by incident_key,occurred_at desc,event_sequence desc;

revoke all on foundation.current_foundation_promoted_release_case_audit_incident_state
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant select on foundation.current_foundation_promoted_release_case_audit_incident_state
  to foundation_runtime,service_role;


create view foundation.current_foundation_promoted_release_case_audit_incidents
with (security_invoker=true)
as
select *
from foundation.current_foundation_promoted_release_case_audit_incident_state
where event_type in ('opened','changed');

revoke all on foundation.current_foundation_promoted_release_case_audit_incidents
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant select on foundation.current_foundation_promoted_release_case_audit_incidents
  to foundation_runtime,service_role;


create view foundation.current_foundation_promoted_release_case_audit_watches
with (security_invoker=true)
as
select *
from foundation.current_foundation_promoted_release_case_audit_incident_state
where event_type='detected';

revoke all on foundation.current_foundation_promoted_release_case_audit_watches
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant select on foundation.current_foundation_promoted_release_case_audit_watches
  to foundation_runtime,service_role;


create or replace function foundation.transition_foundation_promoted_release_case_audit_incident_v1(
  p_environment text,
  p_snapshot jsonb,
  p_observed_at timestamptz,
  p_persistence_threshold_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer74_transition$
declare
  v_incident_key text;
  v_state text;
  v_reason text;
  v_severity text;
  v_fingerprint text;
  v_observation_id uuid;
  v_prior foundation.foundation_promoted_release_case_audit_incident_events%rowtype;
  v_event_type text;
  v_detection_started_at timestamptz;
  v_persistence_seconds integer := 0;
  v_event_id uuid;
  v_active_count integer := 0;
  v_watch_count integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_observed_at is null
     or p_persistence_threshold_seconds<60
     or p_persistence_threshold_seconds>3600 then
    raise exception 'promotion-case-audit-incident-input-invalid';
  end if;

  if p_snapshot is null
     or jsonb_typeof(p_snapshot)<>'object'
     or p_snapshot->>'foundationPromotedReleaseCaseAuditObservationSummary'
          is distinct from
          'shine-foundation/promoted-release-case-audit-observation-summary-v1' then
    raise exception 'promotion-case-audit-incident-snapshot-invalid';
  end if;

  v_state := coalesce(p_snapshot->>'state','unknown');
  v_reason := coalesce(
    p_snapshot->>'reasonCode',
    'promotion-case-audit-state-unknown'
  );

  if v_state not in ('normal','gap','invalid','drift','unknown') then
    raise exception 'promotion-case-audit-incident-state-invalid';
  end if;

  v_fingerprint :=
    foundation.foundation_promoted_release_case_audit_incident_fingerprint_v1(
      p_snapshot
    );

  begin
    v_observation_id :=
      nullif(p_snapshot#>>'{observation,observationId}','')::uuid;
  exception when invalid_text_representation then
    raise exception 'promotion-case-audit-incident-observation-id-invalid';
  end;

  if v_observation_id is not null
     and not exists(
       select 1
       from foundation.foundation_promoted_release_case_audit_observations
       where observation_id=v_observation_id
     ) then
    raise exception 'promotion-case-audit-incident-observation-missing';
  end if;

  v_incident_key := p_environment||':promoted_release_case_audit';

  select * into v_prior
  from foundation.foundation_promoted_release_case_audit_incident_events
  where incident_key=v_incident_key
  order by occurred_at desc,event_sequence desc
  limit 1;

  v_event_type := null;

  if v_state in ('gap','invalid','drift','unknown') then
    v_severity := case
      when v_state in ('gap','invalid') then 'critical'
      else 'warning'
    end;

    if v_prior.event_id is null or v_prior.event_type='recovered' then
      v_event_type := 'detected';
      v_detection_started_at := p_observed_at;
      v_persistence_seconds := 0;

    elsif v_prior.event_type='detected' then
      if v_prior.source_state is distinct from v_state
         or v_prior.evidence_fingerprint is distinct from v_fingerprint then
        v_event_type := 'detected';
        v_detection_started_at := p_observed_at;
        v_persistence_seconds := 0;
      else
        v_detection_started_at := v_prior.detection_started_at;
        v_persistence_seconds := greatest(
          0,
          floor(extract(epoch from (
            p_observed_at-v_detection_started_at
          )))::integer
        );

        if v_persistence_seconds>=p_persistence_threshold_seconds then
          v_event_type := 'opened';
        end if;
      end if;

    elsif v_prior.event_type in ('opened','changed') then
      v_detection_started_at := v_prior.detection_started_at;
      v_persistence_seconds := greatest(
        0,
        floor(extract(epoch from (
          p_observed_at-v_detection_started_at
        )))::integer
      );

      if v_prior.source_state is distinct from v_state
         or v_prior.evidence_fingerprint is distinct from v_fingerprint then
        v_event_type := 'changed';
      end if;
    end if;

  else
    v_severity := 'info';

    if v_prior.event_id is not null
       and v_prior.event_type in ('detected','opened','changed') then
      v_event_type := 'recovered';
      v_detection_started_at := v_prior.detection_started_at;
      v_persistence_seconds := greatest(
        0,
        floor(extract(epoch from (
          p_observed_at-v_detection_started_at
        )))::integer
      );
    end if;
  end if;

  if v_event_type is not null then
    v_event_id := gen_random_uuid();

    insert into foundation.foundation_promoted_release_case_audit_incident_events(
      event_id,
      incident_key,
      environment,
      domain,
      event_type,
      source_state,
      severity,
      reason_code,
      evidence_fingerprint,
      case_audit_observation_id,
      detection_started_at,
      persistence_threshold_seconds,
      persistence_seconds,
      snapshot,
      occurred_at,
      evidence_ref
    )
    values(
      v_event_id,
      v_incident_key,
      p_environment,
      'promoted_release_case_audit',
      v_event_type,
      v_state,
      v_severity,
      v_reason,
      v_fingerprint,
      v_observation_id,
      v_detection_started_at,
      p_persistence_threshold_seconds,
      v_persistence_seconds,
      p_snapshot,
      p_observed_at,
      'foundation-promoted-release-case-audit-incident:'||v_event_id::text
    );
  end if;

  select count(*) into v_active_count
  from foundation.current_foundation_promoted_release_case_audit_incidents
  where environment=p_environment;

  select count(*) into v_watch_count
  from foundation.current_foundation_promoted_release_case_audit_watches
  where environment=p_environment;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentTransition',
      'shine-foundation/promoted-release-case-audit-incident-transition-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'incidentKey',v_incident_key,
    'sourceState',v_state,
    'severity',v_severity,
    'reasonCode',v_reason,
    'eventType',v_event_type,
    'eventId',v_event_id,
    'eventCreated',v_event_type is not null,
    'evidenceFingerprint',v_fingerprint,
    'persistenceThresholdSeconds',p_persistence_threshold_seconds,
    'persistenceSeconds',case
      when v_detection_started_at is null then 0
      else greatest(
        v_persistence_seconds,
        floor(extract(epoch from (
          p_observed_at-v_detection_started_at
        )))::integer
      )
    end,
    'activeIncidentCount',v_active_count,
    'watchCount',v_watch_count,
    'automaticRepair',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer74_transition$;

revoke all on function foundation.transition_foundation_promoted_release_case_audit_incident_v1(
  text,jsonb,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime,service_role;


create or replace function foundation.run_foundation_promoted_release_case_audit_incident_sentinel_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now(),
  p_persistence_threshold_seconds integer default 300,
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer74_sentinel$
declare
  v_snapshot jsonb;
  v_transition jsonb;
begin
  v_snapshot :=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      p_environment,p_observed_at,p_observation_max_age_seconds
    );

  v_transition :=
    foundation.transition_foundation_promoted_release_case_audit_incident_v1(
      p_environment,
      v_snapshot,
      p_observed_at,
      p_persistence_threshold_seconds
    );

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSentinel',
      'shine-foundation/promoted-release-case-audit-incident-sentinel-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'observedAt',p_observed_at,
    'caseAuditState',v_snapshot->>'state',
    'caseAuditReasonCode',v_snapshot->>'reasonCode',
    'observationFresh',v_snapshot->'observationFresh',
    'observationMatchesLive',v_snapshot->'observationMatchesLive',
    'incidentTransition',v_transition,
    'automaticRepair',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer74_sentinel$;

revoke all on function foundation.run_foundation_promoted_release_case_audit_incident_sentinel_v1(
  text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_foundation_promoted_release_case_audit_incident_sentinel_v1(
  text,timestamptz,integer,integer
) to service_role;


create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer74_summary$
declare
  v_audit jsonb;
  v_current foundation.foundation_promoted_release_case_audit_incident_events%rowtype;
  v_active_count integer := 0;
  v_watch_count integer := 0;
  v_state text := 'normal';
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null then
    raise exception 'promotion-case-audit-incident-summary-input-invalid';
  end if;

  v_audit :=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  select * into v_current
  from foundation.current_foundation_promoted_release_case_audit_incident_state
  where incident_key=p_environment||':promoted_release_case_audit';

  select count(*) into v_active_count
  from foundation.current_foundation_promoted_release_case_audit_incidents
  where environment=p_environment;

  select count(*) into v_watch_count
  from foundation.current_foundation_promoted_release_case_audit_watches
  where environment=p_environment;

  v_state := case
    when v_active_count>0 and v_current.severity='critical' then 'critical'
    when v_active_count>0 then 'warning'
    when v_watch_count>0 then 'watching'
    else 'normal'
  end;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'activeIncidentCount',v_active_count,
    'watchCount',v_watch_count,
    'caseAuditState',v_audit->>'state',
    'caseAuditReasonCode',v_audit->>'reasonCode',
    'observationFresh',v_audit->'observationFresh',
    'observationMatchesLive',v_audit->'observationMatchesLive',
    'currentEvent',case
      when v_current.event_id is null then null
      else jsonb_build_object(
        'eventId',v_current.event_id,
        'incidentKey',v_current.incident_key,
        'eventType',v_current.event_type,
        'sourceState',v_current.source_state,
        'severity',v_current.severity,
        'reasonCode',v_current.reason_code,
        'evidenceFingerprint',v_current.evidence_fingerprint,
        'caseAuditObservationId',v_current.case_audit_observation_id,
        'detectionStartedAt',v_current.detection_started_at,
        'persistenceThresholdSeconds',
          v_current.persistence_threshold_seconds,
        'persistenceSeconds',v_current.persistence_seconds,
        'occurredAt',v_current.occurred_at,
        'evidenceRef',v_current.evidence_ref
      )
    end,
    'recommendedAction',case v_state
      when 'critical' then 'investigate-persistent-promotion-case-audit-failure'
      when 'warning' then 'investigate-promotion-case-audit-observer'
      when 'watching' then 'observe-until-persistence-threshold-or-recovery'
      else 'none'
    end,
    'automaticRepair',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer74_summary$;

revoke all on function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
