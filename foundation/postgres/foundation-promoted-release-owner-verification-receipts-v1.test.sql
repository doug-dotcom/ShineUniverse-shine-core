begin;

insert into foundation.foundation_promoted_release_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,promoted_release_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '71000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_trust','production','promoted_release_trust',
  'opened','hold','critical','canonical-source-truth-not-pass',repeat('a',64),
  null,now()-interval '10 minutes',300,300,'{"test":true}'::jsonb,
  now()-interval '5 minutes','test:layer71:incident'
);

insert into foundation.foundation_promoted_release_owner_handoffs(
  handoff_id,environment,incident_event_id,incident_evidence_fingerprint,
  incident_state,cause_class,source_domain,response_plan_fingerprint,
  owner_service_id,owner_component,requested_actions,handoff,handoff_sha256,created_at
)
values(
  '71000000-0000-4000-8000-000000000002'::uuid,
  'production',
  '71000000-0000-4000-8000-000000000001'::uuid,
  repeat('a',64),
  'critical','canonical-source-truth','source-truth',repeat('b',64),
  'foundation.gateway','shine-core','[]'::jsonb,
  '{"test":"handoff"}'::jsonb,repeat('c',64),now()-interval '4 minutes'
);

insert into foundation.foundation_promoted_release_owner_handoff_responses(
  response_id,handoff_id,incident_event_id,environment,owner_service_id,
  owner_component,response_state,reason_code,response_note,handoff_sha256,
  response_plan_fingerprint,response,response_sha256,responded_at
)
values(
  '71000000-0000-4000-8000-000000000003'::uuid,
  '71000000-0000-4000-8000-000000000002'::uuid,
  '71000000-0000-4000-8000-000000000001'::uuid,
  'production','foundation.gateway','shine-core','accepted',
  'accepted-for-verification-receipt',null,repeat('c',64),repeat('b',64),
  '{"test":"response"}'::jsonb,repeat('d',64),now()-interval '3 minutes'
);

insert into foundation.foundation_promoted_release_owner_evidence_returns(
  evidence_return_id,handoff_id,response_id,incident_event_id,environment,
  owner_service_id,owner_component,owner_reported_outcome,summary,observed_facts,
  evidence_refs,recommended_next_step,handoff_sha256,response_sha256,
  response_plan_fingerprint,evidence_return,evidence_return_sha256,returned_at
)
values(
  '71000000-0000-4000-8000-000000000004'::uuid,
  '71000000-0000-4000-8000-000000000002'::uuid,
  '71000000-0000-4000-8000-000000000003'::uuid,
  '71000000-0000-4000-8000-000000000001'::uuid,
  'production','foundation.gateway','shine-core','resolved',
  'Owner reported the issue resolved.',
  jsonb_build_array('owner fact'),
  jsonb_build_array('test:layer71:evidence'),
  'Await independent Foundation verification.',
  repeat('c',64),repeat('d',64),repeat('b',64),
  '{"test":"evidence"}'::jsonb,repeat('e',64),now()-interval '2 minutes'
);

insert into foundation.foundation_promoted_release_owner_evidence_verifications(
  verification_id,evidence_return_id,handoff_id,response_id,incident_event_id,
  environment,owner_reported_outcome,source_evidence_return_sha256,
  canonical_source_truth_state,canonical_source_truth_fingerprint,
  promotion_closure_state,promoted_release_state,promoted_release_available,
  promoted_release_sha256,trust_state,incident_state,verification_state,
  owner_claim_alignment,verification_proof,verification_proof_sha256,verified_at
)
values(
  '71000000-0000-4000-8000-000000000005'::uuid,
  '71000000-0000-4000-8000-000000000004'::uuid,
  '71000000-0000-4000-8000-000000000002'::uuid,
  '71000000-0000-4000-8000-000000000003'::uuid,
  '71000000-0000-4000-8000-000000000001'::uuid,
  'production','resolved',repeat('e',64),
  'pass',repeat('f',32),'closed','promoted',true,repeat('1',64),
  'normal','normal','recovered','agrees',
  '{"test":"verification"}'::jsonb,repeat('2',64),now()-interval '1 minute'
);

create or replace function foundation.get_promoted_release_owner_evidence_verification_status_v1(
  p_evidence_return_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_verification_status$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceVerificationStatus',
      'shine-foundation/promoted-release-owner-evidence-verification-status-v1',
    'schemaVersion','1.0.0',
    'state','completed',
    'verificationId','71000000-0000-4000-8000-000000000005',
    'evidenceReturnId',p_evidence_return_id,
    'verificationState','recovered',
    'integrityVerified',true
  );
$l71_verification_status$;

create or replace function foundation.get_foundation_promoted_release_owner_handoff_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_handoff_current$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffStatus',
      'shine-foundation/promoted-release-owner-handoff-status-v1',
    'schemaVersion','1.0.0','state','current','usable',true,
    'handoffId',p_handoff_id,'integrityVerified',true,'ownerRouteCurrent',true
  );
$l71_handoff_current$;

create or replace function foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_ack_current$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffResponseStatus',
      'shine-foundation/promoted-release-owner-handoff-ack-status-v1',
    'schemaVersion','1.0.0','state','accepted',
    'handoffId',p_handoff_id,'integrityVerified',true,
    'acknowledgesWorkOwnership',true
  );
$l71_ack_current$;

create or replace function foundation.get_foundation_promoted_release_owner_evidence_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_evidence_current$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceStatus',
      'shine-foundation/promoted-release-owner-evidence-status-v1',
    'schemaVersion','1.0.0','state','current',
    'handoffId',p_handoff_id,'integrityVerified',true
  );
$l71_evidence_current$;

do $l71_security$
begin
  if not has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_foundation_promoted_release_owner_verification_receipts_v1(text,integer,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'foundation.get_foundation_promoted_release_owner_verification_receipts_v1(text,integer,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_owner_verification_receipts_v1(text,integer,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.get_foundation_promoted_release_owner_verification_receipts_v1(text,integer,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_foundation_promoted_release_owner_verification_receipts_v1(text,integer,timestamptz)',
       'EXECUTE'
     )
     or has_table_privilege(
       'shine_core_control_plane',
       'foundation.foundation_promoted_release_owner_evidence_verifications',
       'SELECT'
     ) then
    raise exception 'Layer 71 verification receipt privilege boundary invalid';
  end if;
end;
$l71_security$;

set local role shine_core_control_plane;

do $l71_current_receipt$
declare
  receipts jsonb;
  item jsonb;
begin
  receipts:=foundation.get_foundation_promoted_release_owner_verification_receipts_v1(
    'production',25,now()
  );

  if receipts->>'receiptCount'<>'1'
     or receipts->>'visibleCount'<>'1'
     or receipts->>'invalidCount'<>'0'
     or receipts->>'hasMore'<>'false'
     or jsonb_array_length(receipts->'items')<>1 then
    raise exception 'Layer 71 receipt counts invalid: %',receipts;
  end if;

  item:=receipts->'items'->0;

  if item->>'handoffState'<>'current'
     or item->>'historical'<>'false'
     or item->>'ownerReportedOutcome'<>'resolved'
     or item->>'verificationState'<>'recovered'
     or item->>'ownerClaimAlignment'<>'agrees'
     or item->>'receiptState'<>'verified'
     or item->>'integrityVerified'<>'true'
     or item->>'ownerOutcomeAcceptedAsPromotionTrust'<>'false'
     or item->>'incidentClosurePerformed'<>'false'
     or item->>'approvalGranted'<>'false'
     or item->>'executionAuthorityGranted'<>'false'
     or item->>'executesAction'<>'false' then
    raise exception 'Layer 71 current receipt invalid: %',item;
  end if;
end;
$l71_current_receipt$;

reset role;

create or replace function foundation.get_foundation_promoted_release_owner_handoff_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_handoff_stale$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffStatus',
      'shine-foundation/promoted-release-owner-handoff-status-v1',
    'schemaVersion','1.0.0','state','stale','usable',false,
    'handoffId',p_handoff_id,'integrityVerified',true,'ownerRouteCurrent',true
  );
$l71_handoff_stale$;

create or replace function foundation.get_foundation_promoted_release_owner_handoff_response_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_ack_stale$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerHandoffResponseStatus',
      'shine-foundation/promoted-release-owner-handoff-ack-status-v1',
    'schemaVersion','1.0.0','state','stale',
    'handoffId',p_handoff_id,'integrityVerified',true,
    'acknowledgesWorkOwnership',true
  );
$l71_ack_stale$;

create or replace function foundation.get_foundation_promoted_release_owner_evidence_status_v1(
  p_handoff_id uuid,
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_evidence_stale$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceStatus',
      'shine-foundation/promoted-release-owner-evidence-status-v1',
    'schemaVersion','1.0.0','state','stale',
    'handoffId',p_handoff_id,'integrityVerified',true
  );
$l71_evidence_stale$;

set local role shine_core_control_plane;

do $l71_historical_receipt$
declare
  receipts jsonb;
  item jsonb;
begin
  receipts:=foundation.get_foundation_promoted_release_owner_verification_receipts_v1(
    'production',25,now()
  );
  item:=receipts->'items'->0;

  if receipts->>'receiptCount'<>'1'
     or jsonb_array_length(receipts->'items')<>1
     or item->>'handoffState'<>'stale'
     or item->>'acknowledgementState'<>'stale'
     or item->>'evidenceState'<>'stale'
     or item->>'historical'<>'true'
     or item->>'verificationState'<>'recovered'
     or item->>'integrityVerified'<>'true' then
    raise exception 'Layer 71 historical receipt must remain visible: %',receipts;
  end if;
end;
$l71_historical_receipt$;

reset role;

create or replace function foundation.get_promoted_release_owner_evidence_verification_status_v1(
  p_evidence_return_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l71_verification_invalid$
  select jsonb_build_object(
    'foundationPromotedReleaseOwnerEvidenceVerificationStatus',
      'shine-foundation/promoted-release-owner-evidence-verification-status-v1',
    'schemaVersion','1.0.0','state','invalid',
    'verificationId','71000000-0000-4000-8000-000000000005',
    'evidenceReturnId',p_evidence_return_id,'integrityVerified',false
  );
$l71_verification_invalid$;

set local role shine_core_control_plane;

do $l71_invalid_hidden$
declare receipts jsonb;
begin
  receipts:=foundation.get_foundation_promoted_release_owner_verification_receipts_v1(
    'production',25,now()
  );

  if receipts->>'receiptCount'<>'0'
     or receipts->>'visibleCount'<>'0'
     or receipts->>'invalidCount'<>'1'
     or jsonb_array_length(receipts->'items')<>0 then
    raise exception 'Layer 71 invalid verification must be hidden: %',receipts;
  end if;
end;
$l71_invalid_hidden$;

reset role;

rollback;
