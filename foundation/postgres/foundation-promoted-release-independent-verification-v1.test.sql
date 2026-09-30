begin;

-- Build one accepted current owner-evidence packet through Layers 67-69.
insert into foundation.foundation_promoted_release_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,promoted_release_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '70000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_trust','production','promoted_release_trust',
  'opened','hold','critical','canonical-source-truth-not-pass',repeat('a',64),
  null,now()-interval '10 minutes',300,300,'{"test":true}'::jsonb,
  now()-interval '5 minutes','test:layer70:incident:opened'
);

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l70_incident_bad$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','critical','activeIncidentCount',1,'watchCount',0,'trustState','hold',
    'trustReasonCode','canonical-source-truth-not-pass',
    'currentEvent',jsonb_build_object(
      'eventId','70000000-0000-4000-8000-000000000001','eventType','opened',
      'sourceState','hold','severity','critical',
      'reasonCode','canonical-source-truth-not-pass','evidenceFingerprint',repeat('a',64)
    )
  );
$l70_incident_bad$;

create or replace function foundation.get_foundation_promoted_release_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l70_cause$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentCauseResponse',
      'shine-foundation/promoted-release-incident-cause-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','critical','trustState','hold',
    'reasonCode','canonical-source-truth-not-pass',
    'causeClass','canonical-source-truth','sourceDomain','source-truth',
    'nextEvidenceAction','inspect-canonical-source-truth',
    'authorityExpansion',false,'automaticRepairAllowed',false,
    'mutatesAuthoritativeTruth',false
  );
$l70_cause$;

create or replace function foundation.get_foundation_promoted_release_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l70_plan$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentResponsePlan',
      'shine-foundation/promoted-release-incident-response-plan-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'incidentState','critical','trustState','hold',
    'causeClass','canonical-source-truth','sourceDomain','source-truth',
    'nextEvidenceAction','inspect-canonical-source-truth',
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
$l70_plan$;

set local role service_role;
select foundation.generate_foundation_promoted_release_owner_handoff_v1(
  'production',now()
);
reset role;

set local role shine_core_control_plane;

do $l70_owner_evidence$
declare
  inbox jsonb;
  hid uuid;
  response jsonb;
  evidence jsonb;
begin
  inbox:=foundation.get_foundation_promoted_release_owner_inbox_v1(
    'production',25,now()
  );
  hid:=(inbox->'items'->0->>'handoffId')::uuid;

  response:=foundation.respond_foundation_promoted_release_owner_handoff_v1(
    hid,'accepted','accepted-for-independent-verification',null,now()
  );

  if response->>'status'<>'recorded' then
    raise exception 'Layer 70 prerequisite acknowledgement failed: %',response;
  end if;

  evidence:=foundation.return_foundation_promoted_release_owner_evidence_v1(
    hid,
    'resolved',
    'Owner reports the promotion-trust fault resolved; Foundation must independently verify.',
    jsonb_build_array(
      'Owner-side release records appear aligned.',
      'Owner did not modify incident history.'
    ),
    jsonb_build_array(
      'test:layer70:owner-review',
      'test:layer70:owner-change-log'
    ),
    'Run independent Foundation verification.',
    now()
  );

  if evidence->>'status'<>'recorded'
     or evidence->>'ownerReportedOutcome'<>'resolved'
     or evidence->>'requiresIndependentVerification'<>'true' then
    raise exception 'Layer 70 prerequisite owner evidence failed: %',evidence;
  end if;
end;
$l70_owner_evidence$;

reset role;

-- Independent live truth remains impaired despite the owner's resolved claim.
create or replace function foundation.get_foundation_canonical_source_truth_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $l70_canonical_bad$
  select jsonb_build_object(
    'foundationCanonicalSourceTruthResponse','shine-foundation/canonical-source-truth-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','fail','reasonCodes',jsonb_build_array('test-source-truth-fail'),
    'evidenceFingerprint',repeat('1',32)
  );
$l70_canonical_bad$;

create or replace function foundation.get_foundation_release_promotion_closure_status_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $l70_closure_bad$
  select jsonb_build_object(
    'foundationReleasePromotionClosureStatusResponse',
      'shine-foundation/release-promotion-closure-status-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','blocked','reasonCode','canonical-source-truth-not-pass',
    'releaseClosed',false,'integrityVerified',true,'receiptCurrent',false
  );
$l70_closure_bad$;

create or replace function foundation.get_foundation_promoted_release_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $l70_promoted_bad$
  select jsonb_build_object(
    'foundationPromotedReleaseResponse','shine-foundation/promoted-release-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'available',false,'state','hold','reasonCode','canonical-source-truth-not-pass',
    'promotionClosureState','blocked','promotedRelease',null,
    'runtimeReadinessClaimed',false,'mutatesAuthoritativeTruth',false
  );
$l70_promoted_bad$;

create or replace function foundation.get_foundation_promoted_release_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l70_trust_bad$
  select jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','hold','reasonCode','canonical-source-truth-not-pass',
    'observationFresh',true,'observationMatchesLive',true,
    'live',jsonb_build_object('state','hold','available',false)
  );
$l70_trust_bad$;

do $l70_independent_bad$
declare
  v jsonb;
begin
  v:=foundation.evaluate_foundation_promoted_release_independent_recovery_v1(
    'production',now(),600
  );

  if v->>'verificationState'<>'impaired'
     or v->>'canonicalRecoveryObserved'<>'false'
     or v->>'ownerEvidenceUsedAsCanonicalInput'<>'false'
     or v->>'ownerOutcomeAcceptedAsPromotionTrust'<>'false'
     or v->>'incidentClosurePerformed'<>'false'
     or v->>'mutatesAuthoritativeTruth'<>'false' then
    raise exception 'Layer 70 impaired independent evaluation invalid: %',v;
  end if;
end;
$l70_independent_bad$;

set local role service_role;

do $l70_verify$
declare
  eid uuid;
  result jsonb;
  replay jsonb;
  status jsonb;
begin
  select evidence_return_id into eid
  from foundation.foundation_promoted_release_owner_evidence_returns
  order by evidence_return_sequence desc
  limit 1;

  result:=foundation.run_promoted_release_owner_evidence_verification_v1(
    eid,now(),900,600
  );

  if result->>'status'<>'recorded'
     or result->>'verificationState'<>'impaired'
     or result->>'ownerReportedOutcome'<>'resolved'
     or result->>'ownerClaimAlignment'<>'disagrees'
     or result->>'canonicalRecoveryObserved'<>'false'
     or result->>'independentVerification'<>'true'
     or result->>'ownerOutcomeAcceptedAsPromotionTrust'<>'false'
     or result->>'sourceEvidenceUsedAsTriggerOnly'<>'true'
     or result->>'incidentClosurePerformed'<>'false'
     or result->>'promotionTrustChangedByVerification'<>'false'
     or result->>'releaseTruthMutationPerformed'<>'false'
     or result->>'approvalGranted'<>'false'
     or result->>'executionAuthorityGranted'<>'false'
     or result->>'executesAction'<>'false' then
    raise exception 'Layer 70 independent verification boundary invalid: %',result;
  end if;

  replay:=foundation.run_promoted_release_owner_evidence_verification_v1(
    eid,now(),900,600
  );

  if replay->>'status'<>'existing'
     or replay->>'verificationId'<>result->>'verificationId'
     or replay->>'verificationState'<>'impaired'
     or replay->>'verificationProofSha256'<>result->>'verificationProofSha256' then
    raise exception 'Layer 70 verification replay must preserve first proof: %',replay;
  end if;

  status:=foundation.get_promoted_release_owner_evidence_verification_status_v1(eid);

  if status->>'state'<>'completed'
     or status->>'integrityVerified'<>'true'
     or status->>'verificationState'<>'impaired'
     or status->>'ownerClaimAlignment'<>'disagrees'
     or status->>'ownerOutcomeAcceptedAsPromotionTrust'<>'false'
     or status->>'executionAuthorityGranted'<>'false' then
    raise exception 'Layer 70 verification status invalid: %',status;
  end if;
end;
$l70_verify$;

reset role;

-- Independent live truth later recovers. This tests the evaluator itself;
-- the prior verification remains immutable history and source evidence becomes stale.
create or replace function foundation.get_foundation_canonical_source_truth_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $l70_canonical_good$
  select jsonb_build_object(
    'foundationCanonicalSourceTruthResponse','shine-foundation/canonical-source-truth-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','pass','reasonCodes','[]'::jsonb,'evidenceFingerprint',repeat('2',32)
  );
$l70_canonical_good$;

create or replace function foundation.get_foundation_release_promotion_closure_status_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $l70_closure_good$
  select jsonb_build_object(
    'foundationReleasePromotionClosureStatusResponse',
      'shine-foundation/release-promotion-closure-status-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','closed','reasonCode','canonical-source-truth-closed',
    'releaseClosed',true,'integrityVerified',true,'receiptCurrent',true
  );
$l70_closure_good$;

create or replace function foundation.get_foundation_promoted_release_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $l70_promoted_good$
  select jsonb_build_object(
    'foundationPromotedReleaseResponse','shine-foundation/promoted-release-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'available',true,'state','promoted','reasonCode','promotion-closure-current',
    'promotionClosureState','closed',
    'promotedRelease',jsonb_build_object('releaseRef','foundation:layer-58:eeeeeeee'),
    'promotedReleaseSha256',repeat('c',64),
    'runtimeReadinessClaimed',false,'mutatesAuthoritativeTruth',false
  );
$l70_promoted_good$;

create or replace function foundation.get_foundation_promoted_release_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l70_trust_good$
  select jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','normal','reasonCode','promoted-release-current',
    'observationFresh',true,'observationMatchesLive',true,
    'live',jsonb_build_object('state','promoted','available',true)
  );
$l70_trust_good$;

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l70_incident_good$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','normal','activeIncidentCount',0,'watchCount',0,
    'trustState','normal','trustReasonCode','promoted-release-current',
    'currentEvent',null
  );
$l70_incident_good$;

do $l70_independent_good$
declare
  v jsonb;
  eid uuid;
  status jsonb;
begin
  v:=foundation.evaluate_foundation_promoted_release_independent_recovery_v1(
    'production',now(),600
  );

  if v->>'verificationState'<>'recovered'
     or v->>'canonicalRecoveryObserved'<>'true'
     or v#>>'{checks,canonicalSourceTruthPass}'<>'true'
     or v#>>'{checks,promotionClosureClosed}'<>'true'
     or v#>>'{checks,promotedReleaseAvailable}'<>'true'
     or v#>>'{checks,liveObservationNormal}'<>'true'
     or v#>>'{checks,incidentLifecycleNormal}'<>'true' then
    raise exception 'Layer 70 recovered independent evaluation invalid: %',v;
  end if;

  select evidence_return_id into eid
  from foundation.foundation_promoted_release_owner_evidence_returns
  order by evidence_return_sequence desc
  limit 1;

  status:=foundation.get_promoted_release_owner_evidence_verification_status_v1(eid);

  if status->>'state'<>'completed'
     or status->>'integrityVerified'<>'true'
     or status->>'verificationState'<>'impaired'
     or status->>'sourceEvidenceCurrentState'<>'stale' then
    raise exception 'Layer 70 historical proof must stay immutable after later recovery: %',status;
  end if;
end;
$l70_independent_good$;

do $l70_security$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_promoted_release_owner_evidence_verification_v1(uuid,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_promoted_release_owner_evidence_verification_v1(uuid,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_promoted_release_owner_evidence_verification_v1(uuid,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_promoted_release_owner_evidence_verification_v1(uuid,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_promoted_release_owner_evidence_verification_v1(uuid,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_owner_evidence_verifications',
       'INSERT'
     )
     or has_table_privilege(
       'shine_core_control_plane',
       'foundation.foundation_promoted_release_owner_evidence_verifications',
       'SELECT'
     )
     or has_function_privilege(
       'anon',
       'foundation.evaluate_foundation_promoted_release_independent_recovery_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.evaluate_foundation_promoted_release_independent_recovery_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 70 privilege boundary invalid';
  end if;
end;
$l70_security$;

do $l70_append_only$
declare id uuid;
begin
  select verification_id into id
  from foundation.foundation_promoted_release_owner_evidence_verifications
  limit 1;

  begin
    update foundation.foundation_promoted_release_owner_evidence_verifications
    set verification_state='recovered'
    where verification_id=id;
    raise exception 'Layer 70 verification history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l70_append_only$;

rollback;
