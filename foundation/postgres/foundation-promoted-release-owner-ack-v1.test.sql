begin;

insert into foundation.foundation_promoted_release_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,promoted_release_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '68000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_trust','production','promoted_release_trust',
  'opened','hold','critical','canonical-source-truth-not-pass',repeat('a',64),
  null,now()-interval '10 minutes',300,300,'{"test":true}'::jsonb,
  now()-interval '5 minutes','test:layer68:incident:opened'
);

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $layer68_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse','shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','critical','activeIncidentCount',1,'watchCount',0,'trustState','hold',
    'trustReasonCode','canonical-source-truth-not-pass',
    'currentEvent',jsonb_build_object(
      'eventId','68000000-0000-4000-8000-000000000001','eventType','opened',
      'sourceState','hold','severity','critical',
      'reasonCode','canonical-source-truth-not-pass','evidenceFingerprint',repeat('a',64)
    )
  );
$layer68_incident$;

create or replace function foundation.get_foundation_promoted_release_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $layer68_cause$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentCauseResponse','shine-foundation/promoted-release-incident-cause-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','critical','trustState','hold','reasonCode','canonical-source-truth-not-pass',
    'causeClass','canonical-source-truth','sourceDomain','source-truth',
    'nextEvidenceAction','inspect-canonical-source-truth','authorityExpansion',false,
    'automaticRepairAllowed',false,'mutatesAuthoritativeTruth',false
  );
$layer68_cause$;

create or replace function foundation.get_foundation_promoted_release_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $layer68_plan$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentResponsePlan','shine-foundation/promoted-release-incident-response-plan-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','critical','trustState','hold','causeClass','canonical-source-truth',
    'sourceDomain','source-truth','nextEvidenceAction','inspect-canonical-source-truth',
    'authorityExpansion',false,'automaticRepairAllowed',false,
    'releaseTruthAuthority','foundation.evaluate_control_plane_incident_response_v1',
    'actions',jsonb_build_array(
      jsonb_build_object(
        'actionKey','inspect-canonical-source-truth','actionClass','observe',
        'decision','admit','requiredControl','read-only',
        'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false
      ),
      jsonb_build_object(
        'actionKey','apply-registry-repair','actionClass','authoritative-mutation',
        'decision','approval-required','requiredControl','external-approval',
        'mutatesAuthoritativeTruth',true,'mutatesIncidentHistory',false
      ),
      jsonb_build_object(
        'actionKey','auto-repair-authoritative-truth','actionClass','authoritative-mutation',
        'decision','deny','requiredControl','prohibited',
        'mutatesAuthoritativeTruth',true,'mutatesIncidentHistory',false
      )
    )
  );
$layer68_plan$;

set local role service_role;
select foundation.generate_foundation_promoted_release_owner_handoff_v1('production',now());
reset role;

do $layer68_security$
begin
  if not has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_foundation_promoted_release_owner_inbox_v1(text,integer,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_core_control_plane',
       'foundation.respond_foundation_promoted_release_owner_handoff_v1(uuid,text,text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.respond_foundation_promoted_release_owner_handoff_v1(uuid,text,text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.respond_foundation_promoted_release_owner_handoff_v1(uuid,text,text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'foundation.respond_foundation_promoted_release_owner_handoff_v1(uuid,text,text,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.respond_foundation_promoted_release_owner_handoff_v1(uuid,text,text,text,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'shine_core_control_plane',
       'foundation.foundation_promoted_release_owner_handoffs','SELECT'
     )
     or has_table_privilege(
       'shine_core_control_plane',
       'foundation.foundation_promoted_release_owner_handoff_responses','SELECT'
     )
     or has_table_privilege(
       'shine_core_control_plane',
       'foundation.foundation_promoted_release_owner_handoff_responses','INSERT'
     )
     or has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_owner_handoff_responses','INSERT'
     ) then
    raise exception 'Layer 68 owner acknowledgement privilege boundary invalid';
  end if;

  if not pg_has_role('postgres','shine_core_control_plane','MEMBER')
     or pg_has_role('foundation_gateway','shine_core_control_plane','MEMBER')
     or pg_has_role('foundation_runtime','shine_core_control_plane','MEMBER') then
    raise exception 'Layer 68 control-plane role membership invalid';
  end if;
end;
$layer68_security$;

set local role shine_core_control_plane;

do $layer68_owner_flow$
declare
  inbox jsonb;
  item jsonb;
  handoff_id uuid;
  response jsonb;
  status jsonb;
  replay jsonb;
begin
  inbox:=foundation.get_foundation_promoted_release_owner_inbox_v1('production',25,now());

  if (inbox->>'pendingCount')::integer<>1
     or (inbox->>'visibleCount')::integer<>1
     or inbox->>'hasMore'<>'false'
     or jsonb_array_length(inbox->'items')<>1
     or inbox->>'responderRole'<>'shine_core_control_plane' then
    raise exception 'Layer 68 pending owner inbox invalid: %',inbox;
  end if;

  item:=inbox->'items'->0;

  if item->>'ownerServiceId'<>'foundation.gateway'
     or item->>'ownerComponent'<>'shine-core'
     or item->>'handoffState'<>'current'
     or item->>'responseState'<>'pending'
     or item->>'integrityVerified'<>'true'
     or item->>'approvalGranted'<>'false'
     or item->>'executionAuthorityGranted'<>'false'
     or item->>'executesAction'<>'false' then
    raise exception 'Layer 68 inbox item invalid: %',item;
  end if;

  handoff_id:=(item->>'handoffId')::uuid;

  response:=foundation.respond_foundation_promoted_release_owner_handoff_v1(
    handoff_id,'accepted','accepted-for-owned-investigation',
    'Shine Core accepts work ownership only. Existing approval and execution controls remain authoritative.',
    now()
  );

  if response->>'status'<>'recorded'
     or response->>'responseState'<>'accepted'
     or response->>'acknowledgesWorkOwnership'<>'true'
     or response->>'workOwnershipOnly'<>'true'
     or response->>'layer38ApprovalGranted'<>'false'
     or response->>'releaseTruthMutationAuthorityGranted'<>'false'
     or response->>'releaseRebindAuthorityGranted'<>'false'
     or response->>'incidentHistoryMutationAuthorityGranted'<>'false'
     or response->>'runtimeMutationAuthorityGranted'<>'false'
     or response->>'incidentClosurePerformed'<>'false'
     or response->>'promotionTrustChanged'<>'false'
     or response->>'approvalGranted'<>'false'
     or response->>'executionAuthorityGranted'<>'false'
     or response->>'executesAction'<>'false' then
    raise exception 'Layer 68 acceptance authority boundary invalid: %',response;
  end if;

  status:=foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(handoff_id,now());

  if status->>'state'<>'accepted'
     or status->>'integrityVerified'<>'true'
     or status->>'acknowledgesWorkOwnership'<>'true'
     or status->>'workOwnershipOnly'<>'true'
     or status->>'executionAuthorityGranted'<>'false'
     or status->>'executesAction'<>'false' then
    raise exception 'Layer 68 response status invalid: %',status;
  end if;

  inbox:=foundation.get_foundation_promoted_release_owner_inbox_v1('production',25,now());

  if (inbox->>'pendingCount')::integer<>0
     or jsonb_array_length(inbox->'items')<>0 then
    raise exception 'Layer 68 accepted work must leave pending inbox: %',inbox;
  end if;

  replay:=foundation.respond_foundation_promoted_release_owner_handoff_v1(
    handoff_id,'rejected','conflicting-replay-must-not-overwrite',null,now()
  );

  if replay->>'status'<>'existing'
     or replay->>'responseState'<>'accepted'
     or replay->>'responseId'<>response->>'responseId'
     or replay->>'responseSha256'<>response->>'responseSha256' then
    raise exception 'Layer 68 first response must remain authoritative: %',replay;
  end if;
end;
$layer68_owner_flow$;

reset role;

do $layer68_integrity$
declare
  v_response foundation.foundation_promoted_release_owner_handoff_responses%rowtype;
  v_expected_hash text;
begin
  select * into v_response
  from foundation.foundation_promoted_release_owner_handoff_responses
  order by response_sequence desc
  limit 1;

  if v_response.response_id is null
     or v_response.response_state<>'accepted'
     or v_response.owner_service_id<>'foundation.gateway'
     or v_response.owner_component<>'shine-core' then
    raise exception 'Layer 68 response row missing or invalid';
  end if;

  v_expected_hash:=encode(
    extensions.digest(convert_to(v_response.response::text,'UTF8'),'sha256'),
    'hex'
  );

  if v_expected_hash<>v_response.response_sha256
     or v_response.response->>'layer38ApprovalGranted'<>'false'
     or v_response.response->>'releaseTruthMutationAuthorityGranted'<>'false'
     or v_response.response->>'releaseRebindAuthorityGranted'<>'false'
     or v_response.response->>'incidentHistoryMutationAuthorityGranted'<>'false'
     or v_response.response->>'runtimeMutationAuthorityGranted'<>'false'
     or v_response.response->>'incidentClosurePerformed'<>'false'
     or v_response.response->>'promotionTrustChanged'<>'false' then
    raise exception 'Layer 68 response integrity/authority invariant failed';
  end if;
end;
$layer68_integrity$;

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $layer68_recovered$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse','shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','normal','activeIncidentCount',0,'watchCount',0,
    'trustState','normal','trustReasonCode','promoted-release-current','currentEvent',null
  );
$layer68_recovered$;

do $layer68_recovery_stales$
declare
  v_handoff_id uuid;
  status jsonb;
begin
  select h.handoff_id into v_handoff_id
  from foundation.foundation_promoted_release_owner_handoffs h
  order by handoff_sequence desc
  limit 1;

  status:=foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
    v_handoff_id,now()
  );

  if status->>'state'<>'stale'
     or status->>'integrityVerified'<>'true'
     or status->>'acknowledgesWorkOwnership'<>'true'
     or status->>'executionAuthorityGranted'<>'false' then
    raise exception 'Layer 68 recovery must stale acknowledgement currentness: %',status;
  end if;
end;
$layer68_recovery_stales$;

do $layer68_append_only$
declare id uuid;
begin
  select response_id into id
  from foundation.foundation_promoted_release_owner_handoff_responses
  limit 1;

  begin
    update foundation.foundation_promoted_release_owner_handoff_responses
    set reason_code='mutation'
    where response_id=id;
    raise exception 'Layer 68 response history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$layer68_append_only$;

rollback;
