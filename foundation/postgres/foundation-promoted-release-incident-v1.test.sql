begin;

-- Seed one real Layer-64 observation so incident references can be FK-verified.
create or replace function foundation.get_foundation_promoted_release_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer65_promoted$
  select jsonb_build_object(
    'foundationPromotedReleaseResponse',
      'shine-foundation/promoted-release-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'available',true,
    'state','promoted',
    'reasonCode','promotion-closure-current',
    'promotionClosureState','closed',
    'promotedRelease',jsonb_build_object(
      'bindingId','65000000-0000-4000-8000-000000000001',
      'releaseRef','foundation:layer-58:eeeeeeee',
      'foundationLayer',58,
      'sourceRef',
        'github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'sourceCommitSha',repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('f',64),
      'closureId','65000000-0000-4000-8000-000000000002',
      'closureSha256',repeat('a',64),
      'canonicalSourceTruthFingerprint',repeat('b',32),
      'closedAt','2026-09-30T00:00:00+00:00'
    ),
    'promotedReleaseSha256',repeat('c',64),
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
$layer65_promoted$;

set local role service_role;
select foundation.record_foundation_promoted_release_observation_v1(
  'production','2026-09-30T00:00:00+00:00'
);
reset role;

do $layer65_no_incident_when_normal$
declare
  snapshot jsonb;
  transition jsonb;
begin
  snapshot:=foundation.get_foundation_promoted_release_observation_summary_v1(
    'production','2026-09-30T00:00:00+00:00',600
  );

  transition:=foundation.transition_foundation_promoted_release_incident_v1(
    'production',snapshot,'2026-09-30T00:01:00+00:00',300
  );

  if transition->>'sourceState'<>'normal'
     or transition->>'eventCreated'<>'false'
     or transition->>'activeIncidentCount'<>'0'
     or transition->>'watchCount'<>'0' then
    raise exception 'Layer 65 normal state must not create incident: %',transition;
  end if;
end;
$layer65_no_incident_when_normal$;


-- Persistent HOLD: first sample watch, second identical sample opens critical incident.
do $layer65_hold_lifecycle$
declare
  observation_id uuid;
  hold_snapshot jsonb;
  first_event jsonb;
  opened_event jsonb;
  unchanged_event jsonb;
begin
  select observation_id into observation_id
  from foundation.current_foundation_promoted_release_observation
  where environment='production';

  hold_snapshot:=jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'evaluatedAt','2026-09-30T00:05:00+00:00',
    'state','hold',
    'reasonCode','canonical-source-truth-not-pass',
    'observationFresh',true,
    'observationMatchesLive',true,
    'live',jsonb_build_object(
      'state','hold',
      'reasonCode','canonical-source-truth-not-pass',
      'semanticFingerprint',repeat('d',64)
    ),
    'observation',jsonb_build_object(
      'observationId',observation_id,
      'state','hold',
      'reasonCode','canonical-source-truth-not-pass',
      'semanticFingerprint',repeat('d',64)
    )
  );

  first_event:=foundation.transition_foundation_promoted_release_incident_v1(
    'production',hold_snapshot,'2026-09-30T00:05:00+00:00',300
  );

  if first_event->>'eventType'<>'detected'
     or first_event->>'severity'<>'critical'
     or first_event->>'activeIncidentCount'<>'0'
     or first_event->>'watchCount'<>'1' then
    raise exception 'Layer 65 first hold sample must create critical watch: %',first_event;
  end if;

  opened_event:=foundation.transition_foundation_promoted_release_incident_v1(
    'production',hold_snapshot,'2026-09-30T00:10:00+00:00',300
  );

  if opened_event->>'eventType'<>'opened'
     or opened_event->>'severity'<>'critical'
     or opened_event->>'persistenceSeconds'<>'300'
     or opened_event->>'activeIncidentCount'<>'1'
     or opened_event->>'watchCount'<>'0' then
    raise exception 'Layer 65 persistent hold must open critical incident: %',opened_event;
  end if;

  unchanged_event:=foundation.transition_foundation_promoted_release_incident_v1(
    'production',hold_snapshot,'2026-09-30T00:15:00+00:00',300
  );

  if unchanged_event->>'eventCreated'<>'false'
     or unchanged_event->>'activeIncidentCount'<>'1' then
    raise exception 'Layer 65 unchanged open hold must not append noise: %',unchanged_event;
  end if;
end;
$layer65_hold_lifecycle$;


-- Material change while open appends CHANGED and keeps the original detection clock.
do $layer65_changed_evidence$
declare
  observation_id uuid;
  changed_snapshot jsonb;
  changed_event jsonb;
begin
  select observation_id into observation_id
  from foundation.current_foundation_promoted_release_observation
  where environment='production';

  changed_snapshot:=jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'evaluatedAt','2026-09-30T00:16:00+00:00',
    'state','drift',
    'reasonCode','promoted-release-observation-drift',
    'observationFresh',true,
    'observationMatchesLive',false,
    'live',jsonb_build_object(
      'state','hold',
      'reasonCode','promotion-closure-no-longer-current',
      'semanticFingerprint',repeat('e',64)
    ),
    'observation',jsonb_build_object(
      'observationId',observation_id,
      'state','promoted',
      'reasonCode','promotion-closure-current',
      'semanticFingerprint',repeat('c',64)
    )
  );

  changed_event:=foundation.transition_foundation_promoted_release_incident_v1(
    'production',changed_snapshot,'2026-09-30T00:16:00+00:00',300
  );

  if changed_event->>'eventType'<>'changed'
     or changed_event->>'severity'<>'warning'
     or changed_event->>'sourceState'<>'drift'
     or changed_event->>'persistenceSeconds'<>'660'
     or changed_event->>'activeIncidentCount'<>'1' then
    raise exception 'Layer 65 changed evidence must append warning change: %',changed_event;
  end if;
end;
$layer65_changed_evidence$;


-- Recovery is explicit and clears active/watch state.
do $layer65_recovery$
declare
  normal_snapshot jsonb;
  recovered jsonb;
  summary jsonb;
begin
  normal_snapshot:=foundation.get_foundation_promoted_release_observation_summary_v1(
    'production','2026-09-30T00:17:00+00:00',3600
  );

  recovered:=foundation.transition_foundation_promoted_release_incident_v1(
    'production',normal_snapshot,'2026-09-30T00:17:00+00:00',300
  );

  if recovered->>'eventType'<>'recovered'
     or recovered->>'severity'<>'info'
     or recovered->>'activeIncidentCount'<>'0'
     or recovered->>'watchCount'<>'0' then
    raise exception 'Layer 65 recovery invalid: %',recovered;
  end if;

  summary:=foundation.get_foundation_promoted_release_incident_summary_v1(
    'production','2026-09-30T00:17:00+00:00',3600
  );

  if summary->>'state'<>'normal'
     or summary->>'activeIncidentCount'<>'0'
     or summary->>'watchCount'<>'0'
     or summary#>>'{currentEvent,eventType}'<>'recovered'
     or summary->>'automaticRepair'<>'false' then
    raise exception 'Layer 65 recovered summary invalid: %',summary;
  end if;
end;
$layer65_recovery$;


-- UNKNOWN is warning-class and must start a fresh watch after recovery.
do $layer65_unknown_watch$
declare
  unknown_snapshot jsonb;
  detected jsonb;
begin
  unknown_snapshot:=jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'evaluatedAt','2026-09-30T01:00:00+00:00',
    'state','unknown',
    'reasonCode','promoted-release-observation-stale',
    'observationFresh',false,
    'observationMatchesLive',true,
    'live',jsonb_build_object(
      'state','promoted',
      'reasonCode','promotion-closure-current',
      'semanticFingerprint',repeat('c',64)
    ),
    'observation',null
  );

  detected:=foundation.transition_foundation_promoted_release_incident_v1(
    'production',unknown_snapshot,'2026-09-30T01:00:00+00:00',300
  );

  if detected->>'eventType'<>'detected'
     or detected->>'severity'<>'warning'
     or detected->>'sourceState'<>'unknown'
     or detected->>'watchCount'<>'1' then
    raise exception 'Layer 65 unknown freshness must start warning watch: %',detected;
  end if;
end;
$layer65_unknown_watch$;


do $layer65_privileges$
begin
  if has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_incident_events',
       'INSERT'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_foundation_promoted_release_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.run_foundation_promoted_release_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 65 privilege boundary is incorrect';
  end if;
end;
$layer65_privileges$;


do $layer65_append_only$
declare id uuid;
begin
  select event_id into id
  from foundation.current_foundation_promoted_release_incident_state
  where environment='production';

  begin
    update foundation.foundation_promoted_release_incident_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 65 incident history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$layer65_append_only$;

rollback;
