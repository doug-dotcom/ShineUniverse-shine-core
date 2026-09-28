-- Foundation Layer 37: persistent release-projection incident escalation.
-- A single bad reconciliation sample becomes a watch. Only a persistent FAIL/UNKNOWN
-- becomes an active control-plane incident. Lifecycle is append-only.

create table foundation.foundation_control_plane_incident_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  incident_key text not null
    check (incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  domain text not null
    check (domain ~ '^[a-z0-9][a-z0-9._:-]*$'),
  event_type text not null
    check (event_type in ('detected','opened','changed','recovered')),
  source_state text not null
    check (source_state in ('aligned','degraded','unknown','fail')),
  severity text not null
    check (severity in ('info','warning','critical')),
  reason_codes jsonb not null default '[]'::jsonb
    check (jsonb_typeof(reason_codes)='array'),
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  projection_observation_id uuid not null
    references foundation.foundation_release_projection_observations(observation_id),
  detection_started_at timestamptz not null,
  persistence_threshold_seconds integer not null
    check (persistence_threshold_seconds between 60 and 3600),
  persistence_seconds integer not null
    check (persistence_seconds >= 0),
  snapshot jsonb not null
    check (jsonb_typeof(snapshot)='object'),
  occurred_at timestamptz not null,
  evidence_ref text not null,
  recorded_at timestamptz not null default now(),
  check (
    (
      event_type in ('detected','opened','changed')
      and source_state in ('unknown','fail')
      and (
        (source_state='unknown' and severity='warning')
        or (source_state='fail' and severity='critical')
      )
    )
    or
    (
      event_type='recovered'
      and source_state in ('aligned','degraded')
      and severity='info'
    )
  )
);

alter table foundation.foundation_control_plane_incident_events enable row level security;

create policy foundation_runtime_control_plane_incident_events_select
on foundation.foundation_control_plane_incident_events
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_control_plane_incident_events
  from public,anon,authenticated,foundation_gateway,service_role;
grant select on foundation.foundation_control_plane_incident_events
  to foundation_runtime,service_role;

create index foundation_control_plane_incident_events_key_time_idx
  on foundation.foundation_control_plane_incident_events(
    incident_key,occurred_at desc,event_sequence desc
  );

create index foundation_control_plane_incident_events_projection_observation_idx
  on foundation.foundation_control_plane_incident_events(projection_observation_id);

create trigger foundation_control_plane_incident_events_append_only
before update or delete on foundation.foundation_control_plane_incident_events
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_foundation_control_plane_incident_state
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
  reason_codes,
  evidence_fingerprint,
  projection_observation_id,
  detection_started_at,
  persistence_threshold_seconds,
  persistence_seconds,
  snapshot,
  occurred_at,
  evidence_ref,
  recorded_at
from foundation.foundation_control_plane_incident_events
order by incident_key,occurred_at desc,event_sequence desc;

revoke all on foundation.current_foundation_control_plane_incident_state
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_foundation_control_plane_incident_state
  to foundation_runtime,service_role;


create view foundation.current_foundation_control_plane_incidents
with (security_invoker=true)
as
select *
from foundation.current_foundation_control_plane_incident_state
where event_type in ('opened','changed');

revoke all on foundation.current_foundation_control_plane_incidents
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_foundation_control_plane_incidents
  to foundation_runtime,service_role;


create view foundation.current_foundation_control_plane_watches
with (security_invoker=true)
as
select *
from foundation.current_foundation_control_plane_incident_state
where event_type='detected';

revoke all on foundation.current_foundation_control_plane_watches
  from public,anon,authenticated,foundation_gateway;
grant select on foundation.current_foundation_control_plane_watches
  to foundation_runtime,service_role;


create or replace function foundation.transition_foundation_control_plane_incident_v1(
  p_environment text,
  p_snapshot jsonb,
  p_projection_observation_id uuid,
  p_observed_at timestamptz,
  p_persistence_threshold_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer37_transition$
declare
  v_incident_key text;
  v_state text;
  v_severity text;
  v_fingerprint text;
  v_reasons jsonb;
  v_observation foundation.foundation_release_projection_observations%rowtype;
  v_prior foundation.foundation_control_plane_incident_events%rowtype;
  v_event_type text;
  v_detection_started_at timestamptz;
  v_persistence_seconds integer := 0;
  v_event_id uuid;
  v_active_count integer := 0;
  v_watch_count integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'control-plane-incident-environment-invalid';
  end if;

  if p_observed_at is null then
    raise exception 'control-plane-incident-observed-at-invalid';
  end if;

  if p_persistence_threshold_seconds<60
     or p_persistence_threshold_seconds>3600 then
    raise exception 'control-plane-incident-threshold-invalid';
  end if;

  if p_snapshot is null
     or jsonb_typeof(p_snapshot)<>'object'
     or p_snapshot->>'foundationReleaseProjectionHealthResponse'
        is distinct from 'shine-foundation/release-projection-health-response-v1' then
    raise exception 'control-plane-incident-snapshot-invalid';
  end if;

  v_state := coalesce(p_snapshot->>'state','unknown');
  if v_state not in ('aligned','degraded','unknown','fail') then
    raise exception 'control-plane-incident-source-state-invalid';
  end if;

  v_fingerprint := lower(coalesce(p_snapshot->>'evidenceFingerprint',''));
  if v_fingerprint !~ '^[a-f0-9]{32}$' then
    raise exception 'control-plane-incident-fingerprint-invalid';
  end if;

  v_reasons := coalesce(p_snapshot->'reasonCodes','[]'::jsonb);
  if jsonb_typeof(v_reasons)<>'array' then
    raise exception 'control-plane-incident-reasons-invalid';
  end if;

  select * into v_observation
  from foundation.foundation_release_projection_observations
  where observation_id=p_projection_observation_id;

  if v_observation.observation_id is null then
    raise exception 'control-plane-incident-observation-missing';
  end if;

  if v_observation.environment is distinct from p_environment
     or v_observation.evidence_fingerprint is distinct from v_fingerprint then
    raise exception 'control-plane-incident-observation-mismatch';
  end if;

  v_incident_key := p_environment||':release_projection';

  select * into v_prior
  from foundation.foundation_control_plane_incident_events
  where incident_key=v_incident_key
  order by occurred_at desc,event_sequence desc
  limit 1;

  v_event_type := null;

  if v_state in ('unknown','fail') then
    v_severity := case when v_state='fail' then 'critical' else 'warning' end;

    if v_prior.event_id is null or v_prior.event_type='recovered' then
      v_event_type := 'detected';
      v_detection_started_at := p_observed_at;
      v_persistence_seconds := 0;

    elsif v_prior.event_type='detected' then
      if v_prior.source_state is distinct from v_state
         or v_prior.evidence_fingerprint is distinct from v_fingerprint then
        -- Materially different unhealthy evidence starts a new persistence watch.
        v_event_type := 'detected';
        v_detection_started_at := p_observed_at;
        v_persistence_seconds := 0;
      else
        v_detection_started_at := v_prior.detection_started_at;
        v_persistence_seconds := greatest(
          0,
          floor(extract(epoch from (p_observed_at-v_detection_started_at)))::integer
        );

        if v_persistence_seconds>=p_persistence_threshold_seconds then
          v_event_type := 'opened';
        end if;
      end if;

    elsif v_prior.event_type in ('opened','changed') then
      v_detection_started_at := v_prior.detection_started_at;
      v_persistence_seconds := greatest(
        0,
        floor(extract(epoch from (p_observed_at-v_detection_started_at)))::integer
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
        floor(extract(epoch from (p_observed_at-v_detection_started_at)))::integer
      );
    end if;
  end if;

  if v_event_type is not null then
    insert into foundation.foundation_control_plane_incident_events(
      incident_key,
      environment,
      domain,
      event_type,
      source_state,
      severity,
      reason_codes,
      evidence_fingerprint,
      projection_observation_id,
      detection_started_at,
      persistence_threshold_seconds,
      persistence_seconds,
      snapshot,
      occurred_at,
      evidence_ref
    )
    values (
      v_incident_key,
      p_environment,
      'release_projection',
      v_event_type,
      v_state,
      v_severity,
      v_reasons,
      v_fingerprint,
      p_projection_observation_id,
      v_detection_started_at,
      p_persistence_threshold_seconds,
      v_persistence_seconds,
      p_snapshot,
      p_observed_at,
      'foundation-release-projection:'||p_projection_observation_id::text
    )
    returning event_id into v_event_id;
  end if;

  select count(*) into v_active_count
  from foundation.current_foundation_control_plane_incidents
  where environment=p_environment;

  select count(*) into v_watch_count
  from foundation.current_foundation_control_plane_watches
  where environment=p_environment;

  return jsonb_build_object(
    'foundationControlPlaneIncidentTransitionResponse',
    'shine-foundation/control-plane-incident-transition-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'incidentKey',v_incident_key,
    'sourceState',v_state,
    'severity',v_severity,
    'eventType',v_event_type,
    'eventId',v_event_id,
    'eventCreated',v_event_type is not null,
    'persistenceThresholdSeconds',p_persistence_threshold_seconds,
    'persistenceSeconds',case
      when v_detection_started_at is null then 0
      else greatest(
        v_persistence_seconds,
        floor(extract(epoch from (p_observed_at-v_detection_started_at)))::integer
      )
    end,
    'activeIncidentCount',v_active_count,
    'watchCount',v_watch_count
  );
end;
$layer37_transition$;

revoke all on function foundation.transition_foundation_control_plane_incident_v1(
  text,jsonb,uuid,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role;


create or replace function foundation.run_foundation_control_plane_incident_sentinel_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now(),
  p_persistence_threshold_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer37_sentinel$
declare
  v_reconciliation jsonb;
  v_snapshot jsonb;
  v_observation_id uuid;
  v_transition jsonb;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'control-plane-incident-environment-invalid';
  end if;

  if p_observed_at is null then
    raise exception 'control-plane-incident-observed-at-invalid';
  end if;

  if p_persistence_threshold_seconds<60
     or p_persistence_threshold_seconds>3600 then
    raise exception 'control-plane-incident-threshold-invalid';
  end if;

  v_reconciliation :=
    foundation.record_foundation_release_projection_observation_v1(
      p_environment,p_observed_at
    );

  v_snapshot := v_reconciliation->'snapshot';

  begin
    v_observation_id := nullif(v_reconciliation->>'observationId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'control-plane-incident-observation-id-invalid';
  end;

  if v_observation_id is null then
    raise exception 'control-plane-incident-observation-id-missing';
  end if;

  v_transition :=
    foundation.transition_foundation_control_plane_incident_v1(
      p_environment,
      v_snapshot,
      v_observation_id,
      p_observed_at,
      p_persistence_threshold_seconds
    );

  return jsonb_build_object(
    'foundationControlPlaneIncidentSentinelResponse',
    'shine-foundation/control-plane-incident-sentinel-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'observedAt',p_observed_at,
    'projectionObservationStatus',v_reconciliation->>'status',
    'projectionObservationId',v_observation_id,
    'projectionState',v_snapshot->>'state',
    'projectionEvidenceFingerprint',v_snapshot->>'evidenceFingerprint',
    'incidentTransition',v_transition
  );
end;
$layer37_sentinel$;

revoke all on function foundation.run_foundation_control_plane_incident_sentinel_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_foundation_control_plane_incident_sentinel_v1(
  text,timestamptz,integer
) to service_role;


create or replace function foundation.get_foundation_control_plane_incident_summary_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer37_summary$
declare
  v_projection jsonb;
  v_current foundation.foundation_control_plane_incident_events%rowtype;
  v_active_count integer := 0;
  v_watch_count integer := 0;
  v_summary_state text := 'normal';
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'control-plane-incident-environment-invalid';
  end if;

  v_projection :=
    foundation.get_foundation_release_projection_health_v1(
      p_environment,now()
    );

  select * into v_current
  from foundation.current_foundation_control_plane_incident_state
  where incident_key=p_environment||':release_projection';

  select count(*) into v_active_count
  from foundation.current_foundation_control_plane_incidents
  where environment=p_environment;

  select count(*) into v_watch_count
  from foundation.current_foundation_control_plane_watches
  where environment=p_environment;

  v_summary_state := case
    when v_active_count>0 and v_current.severity='critical' then 'critical'
    when v_active_count>0 then 'warning'
    when v_watch_count>0 then 'watching'
    else 'normal'
  end;

  return jsonb_build_object(
    'foundationControlPlaneIncidentSummaryResponse',
    'shine-foundation/control-plane-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'state',v_summary_state,
    'activeIncidentCount',v_active_count,
    'watchCount',v_watch_count,
    'projectionState',v_projection->>'state',
    'projectionEvidenceFingerprint',v_projection->>'evidenceFingerprint',
    'currentEvent',case
      when v_current.event_id is null then null
      else jsonb_build_object(
        'eventId',v_current.event_id,
        'incidentKey',v_current.incident_key,
        'eventType',v_current.event_type,
        'sourceState',v_current.source_state,
        'severity',v_current.severity,
        'reasonCodes',v_current.reason_codes,
        'projectionObservationId',v_current.projection_observation_id,
        'detectionStartedAt',v_current.detection_started_at,
        'persistenceThresholdSeconds',v_current.persistence_threshold_seconds,
        'persistenceSeconds',v_current.persistence_seconds,
        'occurredAt',v_current.occurred_at,
        'evidenceRef',v_current.evidence_ref
      )
    end,
    'recommendedAction',case v_summary_state
      when 'critical' then 'investigate-and-remediate-release-projection-drift'
      when 'warning' then 'investigate-persistent-release-projection-unknown'
      when 'watching' then 'observe-until-persistence-threshold-or-recovery'
      else 'none'
    end
  );
end;
$layer37_summary$;

revoke all on function foundation.get_foundation_control_plane_incident_summary_v1(text)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_foundation_control_plane_incident_summary_v1(text)
  to foundation_runtime,service_role;
