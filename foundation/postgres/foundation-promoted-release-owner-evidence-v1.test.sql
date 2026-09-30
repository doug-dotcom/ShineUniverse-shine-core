begin;

insert into foundation.foundation_promoted_release_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,promoted_release_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '69000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_trust','production','promoted_release_trust',
  'opened','hold','critical','canonical-source-truth-not-pass',repeat('a',64),
  null,now()-interval '10 minutes',300,300,'{"test":true}'::jsonb,
  now()-interval '5 minutes','test:layer69:incident:opened'
);

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l69_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse','shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','critical','activeIncidentCount',1,'watchCount',0,'trustState','hold',
    'trustReasonCode','canonical-source-truth-not-pass',
    'currentEvent',jsonb_build_object(
      'eventId','69000000-0000-4000-8000-000000000001','eventType','opened',
      'sourceState','hold','severity','critical',
      'reasonCode','canonical-source-truth-not-pass','evidenceFingerprint',repeat('a',64)
    )
  );
$l69_incident$;

create or replace function foundation.get_foundation_promoted_release_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l69_cause$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentCauseResponse','shine-foundation/promoted-release-incident-cause-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','critical','trustState','hold','reasonCode','canonical-source-truth-not-pass',
    'causeClass','canonical-source-truth','sourceDomain','source-truth',
    'nextEvidenceAction','inspect-canonical-source-truth','authorityExpansion',false,
    'automaticRepairAllowed',false,'mutatesAuthoritativeTruth',false
  );
$l69_cause$;

create or replace function foundation.get_foundation_promoted_release_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l69_plan$
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
      )
    )
  );
$l69_plan$;

set local role service_role;
select foundation.generate_foundation_promoted_release_owner_handoff_v1('production',now());
reset role;

set local role shine_core_control_plane;

do $l69_accept$
declare inbox jsonb; hid uuid; response jsonb;
begin
  inbox:=foundation.get_foundation_promoted_release_owner_inbox_v1('production',25,now());
  hid:=(inbox->'items'->0->>'handoffId')::uuid;

  response:=foundation.respond_foundation_promoted_release_owner_handoff_v1(
    hid,'accepted','accepted-for-owner-evidence',null,now()
  );

  if response->>'status'<>'recorded'
     or response->>'responseState'<>'accepted' then
    raise exception 'Layer 69 prerequisite owner acceptance failed: %',response;
  end if;
end;
$l69_accept$;

do $l69_return$
declare
  hid uuid;
  result jsonb;
  replay jsonb;
  status jsonb;
begin
  select h.handoff_id into hid
  from foundation.foundation_promoted_release_owner_handoffs h
  order by handoff_sequence desc limit 1;

  result:=foundation.return_foundation_promoted_release_owner_evidence_v1(
    hid,
    'improved',
    'Owner-side investigation found the release-truth evidence repaired, but Foundation must independently verify current promotion trust.',
    jsonb_build_array(
      'Canonical source records now align under owner inspection.',
      'No incident history was modified by owner evidence.'
    ),
    jsonb_build_array(
      'test:layer69:source-truth-review',
      'test:layer69:owner-work-log'
    ),
    'Run independent Foundation promotion-trust verification.',
    now()
  );

  if result->>'status'<>'recorded'
     or result->>'ownerReportedOutcome'<>'improved'
     or result->>'requiresIndependentVerification'<>'true'
     or result->>'ownerEvidenceIsCanonicalPromotionTrust'<>'false'
     or result->>'ownerOutcomeClaimOnly'<>'true'
     or result->>'promotionTrustChangedByOwnerEvidence'<>'false'
     or result->>'incidentClosurePerformed'<>'false'
     or result->>'layer38ApprovalGranted'<>'false'
     or result->>'releaseTruthMutationAuthorityGranted'<>'false'
     or result->>'releaseRebindAuthorityGranted'<>'false'
     or result->>'incidentHistoryMutationAuthorityGranted'<>'false'
     or result->>'runtimeMutationAuthorityGranted'<>'false'
     or result->>'approvalGranted'<>'false'
     or result->>'executionAuthorityGranted'<>'false'
     or result->>'executesAction'<>'false' then
    raise exception 'Layer 69 evidence return boundary invalid: %',result;
  end if;

  status:=foundation.get_foundation_promoted_release_owner_evidence_status_v1(
    hid,now()
  );

  if status->>'state'<>'current'
     or status->>'integrityVerified'<>'true'
     or status->>'ownerReportedOutcome'<>'improved'
     or status->>'requiresIndependentVerification'<>'true'
     or status->>'ownerEvidenceIsCanonicalPromotionTrust'<>'false'
     or status->>'executionAuthorityGranted'<>'false' then
    raise exception 'Layer 69 evidence status invalid: %',status;
  end if;

  replay:=foundation.return_foundation_promoted_release_owner_evidence_v1(
    hid,
    'resolved',
    'Conflicting replay must not replace first owner evidence.',
    jsonb_build_array('conflicting replay fact'),
    jsonb_build_array('test:layer69:conflicting-replay'),
    null,
    now()
  );

  if replay->>'status'<>'existing'
     or replay->>'evidenceReturnId'<>result->>'evidenceReturnId'
     or replay->>'ownerReportedOutcome'<>'improved'
     or replay->>'evidenceReturnSha256'<>result->>'evidenceReturnSha256' then
    raise exception 'Layer 69 first evidence packet must remain authoritative: %',replay;
  end if;
end;
$l69_return$;

reset role;

do $l69_security$
begin
  if not has_function_privilege(
       'shine_core_control_plane',
       'foundation.return_foundation_promoted_release_owner_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.return_foundation_promoted_release_owner_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.return_foundation_promoted_release_owner_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'foundation.return_foundation_promoted_release_owner_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.return_foundation_promoted_release_owner_evidence_v1(uuid,text,text,jsonb,jsonb,text,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'shine_core_control_plane',
       'foundation.foundation_promoted_release_owner_evidence_returns','SELECT'
     )
     or has_table_privilege(
       'shine_core_control_plane',
       'foundation.foundation_promoted_release_owner_evidence_returns','INSERT'
     )
     or has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_owner_evidence_returns','INSERT'
     ) then
    raise exception 'Layer 69 privilege boundary invalid';
  end if;
end;
$l69_security$;

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l69_recovered$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse','shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','normal','activeIncidentCount',0,'watchCount',0,
    'trustState','normal','trustReasonCode','promoted-release-current','currentEvent',null
  );
$l69_recovered$;

do $l69_recovery$
declare hid uuid; status jsonb;
begin
  select h.handoff_id into hid
  from foundation.foundation_promoted_release_owner_handoffs h
  order by handoff_sequence desc limit 1;

  status:=foundation.get_foundation_promoted_release_owner_evidence_status_v1(
    hid,now()
  );

  if status->>'state'<>'stale'
     or status->>'integrityVerified'<>'true'
     or status->>'ownerReportedOutcome'<>'improved'
     or status->>'promotionTrustChangedByOwnerEvidence'<>'false' then
    raise exception 'Layer 69 recovery must stale owner evidence currentness: %',status;
  end if;
end;
$l69_recovery$;

do $l69_append_only$
declare id uuid;
begin
  select evidence_return_id into id
  from foundation.foundation_promoted_release_owner_evidence_returns
  limit 1;

  begin
    update foundation.foundation_promoted_release_owner_evidence_returns
    set summary='mutation'
    where evidence_return_id=id;
    raise exception 'Layer 69 owner evidence history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l69_append_only$;

rollback;
