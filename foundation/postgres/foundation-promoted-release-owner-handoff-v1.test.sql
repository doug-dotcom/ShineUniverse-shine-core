begin;

-- Normal state never creates owner work.
create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer67_normal_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','normal',
    'activeIncidentCount',0,
    'watchCount',0,
    'trustState','normal',
    'trustReasonCode','promoted-release-current',
    'currentEvent',null
  );
$layer67_normal_incident$;

set local role service_role;
select foundation.generate_foundation_promoted_release_owner_handoff_v1(
  'production','2026-09-30T00:00:00+00:00'
);
reset role;

do $layer67_normal_no_handoff$
begin
  if exists (
    select 1
    from foundation.foundation_promoted_release_owner_handoffs
  ) then
    raise exception 'Layer 67 healthy state unexpectedly created owner handoff';
  end if;
end;
$layer67_normal_no_handoff$;


-- Seed one current critical incident event.
insert into foundation.foundation_promoted_release_incident_events(
  event_id,
  incident_key,
  environment,
  domain,
  event_type,
  source_state,
  severity,
  reason_code,
  evidence_fingerprint,
  promoted_release_observation_id,
  detection_started_at,
  persistence_threshold_seconds,
  persistence_seconds,
  snapshot,
  occurred_at,
  evidence_ref
)
values (
  '67000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_trust',
  'production',
  'promoted_release_trust',
  'opened',
  'hold',
  'critical',
  'canonical-source-truth-not-pass',
  repeat('a',64),
  null,
  '2026-09-30T00:00:00+00:00',
  300,
  300,
  '{"test":true}'::jsonb,
  '2026-09-30T00:05:00+00:00',
  'test:layer67:incident:opened'
);

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer67_critical_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','critical',
    'activeIncidentCount',1,
    'watchCount',0,
    'trustState','hold',
    'trustReasonCode','canonical-source-truth-not-pass',
    'currentEvent',jsonb_build_object(
      'eventId','67000000-0000-4000-8000-000000000001',
      'eventType','opened',
      'sourceState','hold',
      'severity','critical',
      'reasonCode','canonical-source-truth-not-pass',
      'evidenceFingerprint',repeat('a',64)
    )
  );
$layer67_critical_incident$;

create or replace function foundation.get_foundation_promoted_release_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer67_cause$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentCauseResponse',
      'shine-foundation/promoted-release-incident-cause-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState','critical',
    'trustState','hold',
    'reasonCode','canonical-source-truth-not-pass',
    'causeClass','canonical-source-truth',
    'sourceDomain','source-truth',
    'nextEvidenceAction','inspect-canonical-source-truth',
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'mutatesAuthoritativeTruth',false
  );
$layer67_cause$;

create or replace function foundation.get_foundation_promoted_release_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer67_plan$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentResponsePlan',
      'shine-foundation/promoted-release-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState','critical',
    'trustState','hold',
    'causeClass','canonical-source-truth',
    'sourceDomain','source-truth',
    'nextEvidenceAction','inspect-canonical-source-truth',
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'releaseTruthAuthority',
      'foundation.evaluate_control_plane_incident_response_v1',
    'actions',jsonb_build_array(
      jsonb_build_object(
        'actionKey','inspect-canonical-source-truth',
        'actionClass','observe',
        'decision','admit',
        'requiredControl','read-only',
        'mutatesAuthoritativeTruth',false,
        'mutatesIncidentHistory',false
      ),
      jsonb_build_object(
        'actionKey','propose-registry-repair',
        'actionClass','proposal',
        'decision','admit',
        'requiredControl','operator-proposal',
        'mutatesAuthoritativeTruth',false,
        'mutatesIncidentHistory',false
      ),
      jsonb_build_object(
        'actionKey','apply-registry-repair',
        'actionClass','authoritative-mutation',
        'decision','approval-required',
        'requiredControl','external-approval',
        'mutatesAuthoritativeTruth',true,
        'mutatesIncidentHistory',false
      ),
      jsonb_build_object(
        'actionKey','auto-repair-authoritative-truth',
        'actionClass','authoritative-mutation',
        'decision','deny',
        'requiredControl','prohibited',
        'mutatesAuthoritativeTruth',true,
        'mutatesIncidentHistory',false
      )
    )
  );
$layer67_plan$;


do $layer67_fingerprint_stable$
declare
  a jsonb;
  b jsonb;
  fa text;
  fb text;
begin
  a:=foundation.get_foundation_promoted_release_incident_response_plan_v1(
    'production','2026-09-30T00:05:00+00:00',600
  );
  b:=jsonb_set(
    a,
    '{evaluatedAt}',
    to_jsonb('2026-09-30T00:06:00+00:00'::text)
  );

  fa:=foundation.foundation_promoted_release_owner_plan_fingerprint_v1(a);
  fb:=foundation.foundation_promoted_release_owner_plan_fingerprint_v1(b);

  if fa is distinct from fb then
    raise exception 'Layer 67 semantic plan fingerprint must ignore evaluatedAt';
  end if;
end;
$layer67_fingerprint_stable$;


set local role service_role;
select foundation.generate_foundation_promoted_release_owner_handoff_v1(
  'production','2026-09-30T00:05:30+00:00'
);
select foundation.generate_foundation_promoted_release_owner_handoff_v1(
  'production','2026-09-30T00:06:30+00:00'
);
reset role;

do $layer67_handoff_checks$
declare
  h foundation.foundation_promoted_release_owner_handoffs%rowtype;
  status jsonb;
  summary jsonb;
begin
  select * into h
  from foundation.foundation_promoted_release_owner_handoffs
  order by handoff_sequence desc
  limit 1;

  if h.handoff_id is null
     or h.incident_event_id<>
        '67000000-0000-4000-8000-000000000001'::uuid
     or h.incident_state<>'critical'
     or h.cause_class<>'canonical-source-truth'
     or h.source_domain<>'source-truth'
     or h.owner_service_id<>'foundation.gateway'
     or h.owner_component<>'shine-core'
     or jsonb_array_length(h.requested_actions)<>3
     or h.handoff->>'approvalGranted'<>'false'
     or h.handoff->>'executionAuthorityGranted'<>'false'
     or h.handoff->>'executesAction'<>'false' then
    raise exception 'Layer 67 generated handoff invalid: %',to_jsonb(h);
  end if;

  if (select count(*) from foundation.foundation_promoted_release_owner_handoffs)<>1 then
    raise exception 'Layer 67 replay must remain idempotent';
  end if;

  status:=foundation.get_foundation_promoted_release_owner_handoff_status_v1(
    h.handoff_id,'2026-09-30T00:07:00+00:00'
  );

  if status->>'state'<>'current'
     or status->>'usable'<>'true'
     or status->>'integrityVerified'<>'true'
     or status->>'ownerRouteCurrent'<>'true'
     or status->>'executionAuthorityGranted'<>'false' then
    raise exception 'Layer 67 current handoff status invalid: %',status;
  end if;

  summary:=foundation.get_foundation_promoted_release_owner_handoff_summary_v1(
    'production','2026-09-30T00:07:00+00:00'
  );

  if summary->>'currentHandoffCount'<>'1'
     or jsonb_array_length(summary->'items')<>1
     or summary->>'ownerServiceId'<>'foundation.gateway'
     or summary->>'ownerComponent'<>'shine-core' then
    raise exception 'Layer 67 owner handoff summary invalid: %',summary;
  end if;
end;
$layer67_handoff_checks$;


-- Recovery immediately stales the work packet rather than leaving obsolete work current.
create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer67_recovered_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','normal',
    'activeIncidentCount',0,
    'watchCount',0,
    'trustState','normal',
    'trustReasonCode','promoted-release-current',
    'currentEvent',jsonb_build_object(
      'eventId','67000000-0000-4000-8000-000000000002',
      'eventType','recovered',
      'sourceState','normal',
      'severity','info'
    )
  );
$layer67_recovered_incident$;

do $layer67_recovery_stales$
declare
  h uuid;
  status jsonb;
  summary jsonb;
begin
  select handoff_id into h
  from foundation.foundation_promoted_release_owner_handoffs
  order by handoff_sequence desc
  limit 1;

  status:=foundation.get_foundation_promoted_release_owner_handoff_status_v1(
    h,'2026-09-30T00:08:00+00:00'
  );

  if status->>'state'<>'stale'
     or status->>'usable'<>'false' then
    raise exception 'Layer 67 recovered incident must stale owner handoff: %',status;
  end if;

  summary:=foundation.get_foundation_promoted_release_owner_handoff_summary_v1(
    'production','2026-09-30T00:08:00+00:00'
  );

  if summary->>'currentHandoffCount'<>'0'
     or jsonb_array_length(summary->'items')<>0 then
    raise exception 'Layer 67 recovered handoff must leave no current owner work: %',summary;
  end if;
end;
$layer67_recovery_stales$;


do $layer67_privileges$
begin
  if has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_owner_handoffs',
       'INSERT'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.generate_foundation_promoted_release_owner_handoff_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.generate_foundation_promoted_release_owner_handoff_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_owner_handoff_summary_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_owner_handoff_summary_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_owner_handoff_summary_v1(text,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 67 privilege boundary invalid';
  end if;
end;
$layer67_privileges$;


do $layer67_append_only$
declare id uuid;
begin
  select handoff_id into id
  from foundation.foundation_promoted_release_owner_handoffs
  limit 1;

  begin
    update foundation.foundation_promoted_release_owner_handoffs
    set cause_class='mutation'
    where handoff_id=id;
    raise exception 'Layer 67 owner handoff history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$layer67_append_only$;

rollback;
