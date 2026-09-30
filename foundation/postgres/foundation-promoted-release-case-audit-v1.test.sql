begin;

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path=''
as $l72_incident_normal$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','normal',
    'activeIncidentCount',0,
    'watchCount',0,
    'currentEvent',null
  );
$l72_incident_normal$;

do $l72_idle$
declare v jsonb;
begin
  v:=foundation.get_foundation_promoted_release_case_audit_v1(
    'production',25,now(),180
  );

  if v->>'overallState'<>'idle'
     or v->>'structuralIntegrityPass'<>'true'
     or v->>'caseCount'<>'0'
     or v->>'activeIncidentHandoffState'<>'not-required' then
    raise exception 'Layer 72 idle audit invalid: %',v;
  end if;
end;
$l72_idle$;


insert into foundation.foundation_promoted_release_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,promoted_release_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '72000000-0000-4000-8000-000000000001'::uuid,
  'production:promoted_release_trust','production','promoted_release_trust',
  'opened','hold','critical','canonical-source-truth-not-pass',repeat('a',64),
  null,now()-interval '10 minutes',300,300,'{"test":true}'::jsonb,
  now()-interval '5 minutes','test:layer72:incident:current'
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
set search_path=''
as $l72_incident_active$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','critical',
    'activeIncidentCount',1,
    'watchCount',0,
    'currentEvent',jsonb_build_object(
      'eventId','72000000-0000-4000-8000-000000000001',
      'eventType','opened',
      'sourceState','hold',
      'severity','critical',
      'reasonCode','canonical-source-truth-not-pass',
      'evidenceFingerprint',repeat('a',64)
    )
  );
$l72_incident_active$;

do $l72_missing_handoff$
declare v jsonb;
begin
  v:=foundation.get_foundation_promoted_release_case_audit_v1(
    'production',25,now(),180
  );

  if v->>'overallState'<>'gap'
     or v->>'structuralIntegrityPass'<>'false'
     or v->>'activeIncidentHandoffState'<>'missing' then
    raise exception 'Layer 72 overdue active incident must expose handoff gap: %',v;
  end if;
end;
$l72_missing_handoff$;


insert into foundation.foundation_promoted_release_owner_handoffs(
  handoff_id,environment,incident_event_id,incident_evidence_fingerprint,
  incident_state,cause_class,source_domain,response_plan_fingerprint,
  owner_service_id,owner_component,requested_actions,handoff,handoff_sha256,created_at
)
values(
  '72000000-0000-4000-8000-000000000002'::uuid,
  'production',
  '72000000-0000-4000-8000-000000000001'::uuid,
  repeat('a',64),
  'critical','canonical-source-truth','source-truth',repeat('b',64),
  'foundation.gateway','shine-core','[]'::jsonb,
  '{"stage":"handoff"}'::jsonb,
  encode(
    extensions.digest(
      convert_to('{"stage": "handoff"}'::jsonb::text,'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  now()-interval '2 minutes'
);

do $l72_awaiting_response$
declare v jsonb; item jsonb;
begin
  v:=foundation.get_foundation_promoted_release_case_audit_v1(
    'production',25,now(),180
  );
  item:=v->'cases'->0;

  if v->>'overallState'<>'active-work'
     or v->>'structuralIntegrityPass'<>'true'
     or v->>'activeIncidentHandoffState'<>'present'
     or item->>'caseStage'<>'awaiting-owner-response'
     or item->>'structurallyValid'<>'true' then
    raise exception 'Layer 72 awaiting-response stage invalid: %',v;
  end if;
end;
$l72_awaiting_response$;


insert into foundation.foundation_promoted_release_owner_handoff_responses(
  response_id,handoff_id,incident_event_id,environment,owner_service_id,
  owner_component,response_state,reason_code,response_note,handoff_sha256,
  response_plan_fingerprint,response,response_sha256,responded_at
)
select
  '72000000-0000-4000-8000-000000000003'::uuid,
  h.handoff_id,h.incident_event_id,h.environment,h.owner_service_id,
  h.owner_component,'accepted','accepted-for-layer72',null,h.handoff_sha256,
  h.response_plan_fingerprint,'{"stage":"response"}'::jsonb,
  encode(
    extensions.digest(
      convert_to('{"stage": "response"}'::jsonb::text,'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  now()-interval '90 seconds'
from foundation.foundation_promoted_release_owner_handoffs h
where h.handoff_id='72000000-0000-4000-8000-000000000002'::uuid;

do $l72_awaiting_evidence$
declare v jsonb;
begin
  v:=foundation.get_foundation_promoted_release_case_audit_v1(
    'production',25,now(),180
  );

  if v#>>'{cases,0,caseStage}'<>'awaiting-owner-evidence'
     or v->>'pendingCaseCount'<>'1' then
    raise exception 'Layer 72 awaiting-evidence stage invalid: %',v;
  end if;
end;
$l72_awaiting_evidence$;


insert into foundation.foundation_promoted_release_owner_evidence_returns(
  evidence_return_id,handoff_id,response_id,incident_event_id,environment,
  owner_service_id,owner_component,owner_reported_outcome,summary,observed_facts,
  evidence_refs,recommended_next_step,handoff_sha256,response_sha256,
  response_plan_fingerprint,evidence_return,evidence_return_sha256,returned_at
)
select
  '72000000-0000-4000-8000-000000000004'::uuid,
  h.handoff_id,r.response_id,h.incident_event_id,h.environment,
  h.owner_service_id,h.owner_component,'resolved','Layer 72 owner claim.',
  jsonb_build_array('fact'),jsonb_build_array('test:layer72:evidence'),null,
  h.handoff_sha256,r.response_sha256,h.response_plan_fingerprint,
  '{"stage":"evidence"}'::jsonb,
  encode(
    extensions.digest(
      convert_to('{"stage": "evidence"}'::jsonb::text,'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  now()-interval '60 seconds'
from foundation.foundation_promoted_release_owner_handoffs h
join foundation.foundation_promoted_release_owner_handoff_responses r
  on r.handoff_id=h.handoff_id
where h.handoff_id='72000000-0000-4000-8000-000000000002'::uuid;

do $l72_awaiting_verification$
declare v jsonb;
begin
  v:=foundation.get_foundation_promoted_release_case_audit_v1(
    'production',25,now(),180
  );

  if v#>>'{cases,0,caseStage}'<>'awaiting-independent-verification' then
    raise exception 'Layer 72 awaiting-verification stage invalid: %',v;
  end if;
end;
$l72_awaiting_verification$;


insert into foundation.foundation_promoted_release_owner_evidence_verifications(
  verification_id,evidence_return_id,handoff_id,response_id,incident_event_id,
  environment,owner_reported_outcome,source_evidence_return_sha256,
  canonical_source_truth_state,canonical_source_truth_fingerprint,
  promotion_closure_state,promoted_release_state,promoted_release_available,
  promoted_release_sha256,trust_state,incident_state,verification_state,
  owner_claim_alignment,verification_proof,verification_proof_sha256,verified_at
)
select
  '72000000-0000-4000-8000-000000000005'::uuid,
  e.evidence_return_id,h.handoff_id,r.response_id,h.incident_event_id,
  h.environment,e.owner_reported_outcome,e.evidence_return_sha256,
  'pass',repeat('f',32),'closed','promoted',true,repeat('1',64),
  'normal','normal','recovered','agrees',
  '{"stage":"verification"}'::jsonb,
  encode(
    extensions.digest(
      convert_to('{"stage": "verification"}'::jsonb::text,'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  now()-interval '30 seconds'
from foundation.foundation_promoted_release_owner_handoffs h
join foundation.foundation_promoted_release_owner_handoff_responses r
  on r.handoff_id=h.handoff_id
join foundation.foundation_promoted_release_owner_evidence_returns e
  on e.handoff_id=h.handoff_id
where h.handoff_id='72000000-0000-4000-8000-000000000002'::uuid;

do $l72_verified$
declare v jsonb; item jsonb;
begin
  v:=foundation.get_foundation_promoted_release_case_audit_v1(
    'production',25,now(),180
  );
  item:=v->'cases'->0;

  if item->>'caseStage'<>'verified'
     or item->>'terminal'<>'true'
     or item->>'structurallyValid'<>'true'
     or item#>>'{integrityChecks,handoff}'<>'true'
     or item#>>'{integrityChecks,response}'<>'true'
     or item#>>'{integrityChecks,evidence}'<>'true'
     or item#>>'{integrityChecks,verification}'<>'true'
     or v->>'terminalCaseCount'<>'1' then
    raise exception 'Layer 72 verified case invalid: %',v;
  end if;
end;
$l72_verified$;


insert into foundation.foundation_promoted_release_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_code,evidence_fingerprint,promoted_release_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values(
  '72000000-0000-4000-8000-000000000011'::uuid,
  'production:promoted_release_trust:historical-test','production',
  'promoted_release_trust','opened','hold','critical',
  'historical-test',repeat('2',64),null,
  now()-interval '20 minutes',300,300,'{"test":"historical"}'::jsonb,
  now()-interval '15 minutes','test:layer72:incident:historical'
);

insert into foundation.foundation_promoted_release_owner_handoffs(
  handoff_id,environment,incident_event_id,incident_evidence_fingerprint,
  incident_state,cause_class,source_domain,response_plan_fingerprint,
  owner_service_id,owner_component,requested_actions,handoff,handoff_sha256,created_at
)
values(
  '72000000-0000-4000-8000-000000000012'::uuid,
  'production',
  '72000000-0000-4000-8000-000000000011'::uuid,
  repeat('2',64),
  'critical','canonical-source-truth','source-truth',repeat('3',64),
  'foundation.gateway','shine-core','[]'::jsonb,
  '{"stage":"corrupt-handoff"}'::jsonb,
  repeat('0',64),
  now()-interval '14 minutes'
);

do $l72_invalid_history$
declare v jsonb;
begin
  v:=foundation.get_foundation_promoted_release_case_audit_v1(
    'production',25,now(),180
  );

  if v->>'overallState'<>'invalid'
     or v->>'structuralIntegrityPass'<>'false'
     or v->>'invalidCount'<>'1'
     or v->>'caseCount'<>'2' then
    raise exception 'Layer 72 corrupted historical case must fail audit: %',v;
  end if;
end;
$l72_invalid_history$;


do $l72_security$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_case_audit_v1(text,integer,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.get_foundation_promoted_release_case_audit_v1(text,integer,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_foundation_promoted_release_case_audit_v1(text,integer,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.get_foundation_promoted_release_case_audit_v1(text,integer,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_foundation_promoted_release_case_audit_v1(text,integer,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_case_audit_v1(text,integer,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_case_audit_v1(text,integer,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 72 case audit privilege boundary invalid';
  end if;
end;
$l72_security$;

rollback;
