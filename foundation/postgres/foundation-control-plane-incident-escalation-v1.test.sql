begin;

-- Synthetic Layer-37 incident lifecycle evidence. The transition helper is deliberately
-- private; CI runs as the database owner to prove the state machine directly.

insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '37000000-0000-4000-8000-000000000001'::uuid,
  'production','fail',repeat('a',32),
  '["registry-release-ref-mismatch"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-release-ref-mismatch'),
    'evidenceFingerprint',repeat('a',32)
  ),
  now()+interval '1 second',
  now()+interval '1 second'
);

do $layer37_detect_fail$
declare
  v jsonb;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000001'::uuid),
    '37000000-0000-4000-8000-000000000001'::uuid,
    now()+interval '1 second',
    300
  ) into v;

  if v->>'eventType' <> 'detected'
     or v->>'sourceState' <> 'fail'
     or v->>'severity' <> 'critical'
     or v->>'activeIncidentCount' <> '0'
     or v->>'watchCount' <> '1' then
    raise exception 'First FAIL must create a critical watch only: %',v;
  end if;
end;
$layer37_detect_fail$;


do $layer37_not_persistent_yet$
declare
  v jsonb;
  v_count integer;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000001'::uuid),
    '37000000-0000-4000-8000-000000000001'::uuid,
    now()+interval '300 seconds',
    300
  ) into v;

  select count(*) into v_count
  from foundation.foundation_control_plane_incident_events
  where incident_key='production:release_projection';

  if v->>'eventCreated' <> 'false'
     or v_count <> 1 then
    raise exception 'FAIL before threshold must not open incident: %, count %',v,v_count;
  end if;
end;
$layer37_not_persistent_yet$;


do $layer37_open_fail$
declare
  v jsonb;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000001'::uuid),
    '37000000-0000-4000-8000-000000000001'::uuid,
    now()+interval '301 seconds',
    300
  ) into v;

  if v->>'eventType' <> 'opened'
     or v->>'severity' <> 'critical'
     or v->>'activeIncidentCount' <> '1'
     or (v->>'persistenceSeconds')::integer < 300 then
    raise exception 'Persistent FAIL must open critical incident: %',v;
  end if;
end;
$layer37_open_fail$;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '37000000-0000-4000-8000-000000000002'::uuid,
  'production','fail',repeat('b',32),
  '["registry-layer-mismatch"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-layer-mismatch'),
    'evidenceFingerprint',repeat('b',32)
  ),
  now()+interval '360 seconds',
  now()+interval '360 seconds'
);

do $layer37_changed$
declare
  v jsonb;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000002'::uuid),
    '37000000-0000-4000-8000-000000000002'::uuid,
    now()+interval '360 seconds',
    300
  ) into v;

  if v->>'eventType' <> 'changed'
     or v->>'activeIncidentCount' <> '1'
     or v->>'severity' <> 'critical' then
    raise exception 'Materially changed persistent FAIL must append changed event: %',v;
  end if;
end;
$layer37_changed$;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '37000000-0000-4000-8000-000000000003'::uuid,
  'production','aligned',repeat('c',32),
  '[]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','aligned',
    'reasonCodes','[]'::jsonb,
    'evidenceFingerprint',repeat('c',32)
  ),
  now()+interval '420 seconds',
  now()+interval '420 seconds'
);

do $layer37_recovered$
declare
  v jsonb;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000003'::uuid),
    '37000000-0000-4000-8000-000000000003'::uuid,
    now()+interval '420 seconds',
    300
  ) into v;

  if v->>'eventType' <> 'recovered'
     or v->>'severity' <> 'info'
     or v->>'activeIncidentCount' <> '0'
     or v->>'watchCount' <> '0' then
    raise exception 'Aligned projection must recover active incident: %',v;
  end if;
end;
$layer37_recovered$;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '37000000-0000-4000-8000-000000000004'::uuid,
  'production','unknown',repeat('d',32),
  '["release-identity-health-unknown"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','unknown',
    'reasonCodes',jsonb_build_array('release-identity-health-unknown'),
    'evidenceFingerprint',repeat('d',32)
  ),
  now()+interval '480 seconds',
  now()+interval '480 seconds'
);

do $layer37_unknown_watch$
declare
  v jsonb;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000004'::uuid),
    '37000000-0000-4000-8000-000000000004'::uuid,
    now()+interval '480 seconds',
    300
  ) into v;

  if v->>'eventType' <> 'detected'
     or v->>'severity' <> 'warning'
     or v->>'watchCount' <> '1' then
    raise exception 'UNKNOWN should begin as warning watch: %',v;
  end if;
end;
$layer37_unknown_watch$;


do $layer37_unknown_open$
declare
  v jsonb;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000004'::uuid),
    '37000000-0000-4000-8000-000000000004'::uuid,
    now()+interval '780 seconds',
    300
  ) into v;

  if v->>'eventType' <> 'opened'
     or v->>'severity' <> 'warning'
     or v->>'activeIncidentCount' <> '1' then
    raise exception 'Persistent UNKNOWN should open warning incident: %',v;
  end if;
end;
$layer37_unknown_open$;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '37000000-0000-4000-8000-000000000005'::uuid,
  'production','degraded',repeat('e',32),
  '["registry-release-not-fully-verified"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','degraded',
    'reasonCodes',jsonb_build_array('registry-release-not-fully-verified'),
    'evidenceFingerprint',repeat('e',32)
  ),
  now()+interval '840 seconds',
  now()+interval '840 seconds'
);

do $layer37_degraded_recovery$
declare
  v jsonb;
begin
  select foundation.transition_foundation_control_plane_incident_v1(
    'production',
    (select snapshot
     from foundation.foundation_release_projection_observations
     where observation_id='37000000-0000-4000-8000-000000000005'::uuid),
    '37000000-0000-4000-8000-000000000005'::uuid,
    now()+interval '840 seconds',
    300
  ) into v;

  if v->>'eventType' <> 'recovered'
     or v->>'sourceState' <> 'degraded'
     or v->>'activeIncidentCount' <> '0' then
    raise exception 'DEGRADED is non-incident and must recover persistent UNKNOWN: %',v;
  end if;
end;
$layer37_degraded_recovery$;


-- End-to-end sentinel integration. With no CI Universe registry projection outside
-- Layer-36's rolled-back fixture, the real reconciler reports UNKNOWN and the sentinel
-- must create a warning watch rather than an active incident.
do $layer37_sentinel_integration$
declare
  v jsonb;
begin
  select foundation.run_foundation_control_plane_incident_sentinel_v1(
    'production',now()+interval '900 seconds',300
  ) into v;

  if v->>'projectionState' <> 'unknown'
     or v#>>'{incidentTransition,eventType}' <> 'detected'
     or v#>>'{incidentTransition,severity}' <> 'warning'
     or v#>>'{incidentTransition,activeIncidentCount}' <> '0'
     or v#>>'{incidentTransition,watchCount}' <> '1' then
    raise exception 'Sentinel should translate live UNKNOWN projection into warning watch: %',v;
  end if;
end;
$layer37_sentinel_integration$;


do $layer37_security$
begin
  if not has_function_privilege(
    'foundation_runtime',
    'foundation.get_foundation_control_plane_incident_summary_v1(text)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must read control-plane incident summary';
  end if;

  if not has_function_privilege(
    'service_role',
    'foundation.run_foundation_control_plane_incident_sentinel_v1(text,timestamptz,integer)',
    'EXECUTE'
  ) then
    raise exception 'service_role must run control-plane incident sentinel';
  end if;

  if has_function_privilege(
    'foundation_runtime',
    'foundation.run_foundation_control_plane_incident_sentinel_v1(text,timestamptz,integer)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must not run incident sentinel';
  end if;

  if has_function_privilege(
    'service_role',
    'foundation.transition_foundation_control_plane_incident_v1(text,jsonb,uuid,timestamptz,integer)',
    'EXECUTE'
  ) then
    raise exception 'transition helper must remain owner-private';
  end if;

  if has_table_privilege(
    'service_role',
    'foundation.foundation_control_plane_incident_events',
    'INSERT'
  ) then
    raise exception 'service_role must not bypass incident sentinel with direct INSERT';
  end if;
end;
$layer37_security$;

rollback;
