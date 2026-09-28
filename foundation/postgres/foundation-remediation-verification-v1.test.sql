begin;

-- Synthetic Layer-42 fixture. It does not execute a repair; Layer 41 already proves
-- mutation semantics. This fixture proves that only a fresh independent projection
-- observation can verify/close an executed remediation.

insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '42000000-0000-4000-8000-000000000001'::uuid,
  'production','fail',repeat('4',32),
  '["registry-layer-mismatch"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse','shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0','environment','production','state','fail',
    'reasonCodes',jsonb_build_array('registry-layer-mismatch'),
    'evidenceFingerprint',repeat('4',32),
    'binding',jsonb_build_object('releaseRef','foundation:layer-41:aaaaaaaa'),
    'registry',jsonb_build_object('readinessReleaseRef','foundation:layer-40:99999999')
  ),
  now()-interval '10 minutes',now()-interval '10 minutes'
);

insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '42000000-0000-4000-8000-000000000101'::uuid,
  'production:release_projection','production','release_projection',
  'opened','fail','critical','["registry-layer-mismatch"]'::jsonb,
  repeat('4',32),'42000000-0000-4000-8000-000000000001'::uuid,
  now()-interval '10 minutes',300,600,
  (select snapshot from foundation.foundation_release_projection_observations
   where observation_id='42000000-0000-4000-8000-000000000001'::uuid),
  now()-interval '5 minutes','test:layer42:incident'
);

-- Minimal linked approval/admission/execution evidence.
insert into foundation.remediation_approval_receipts(
  receipt_id,environment,incident_event_id,incident_key,incident_state,severity,
  action_key,policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  approved_by,approval_method,approved_at,expires_at,receipt,receipt_sha256
)
values (
  '42000000-0000-4000-8000-000000000201'::uuid,'production',
  '42000000-0000-4000-8000-000000000101'::uuid,'production:release_projection',
  'critical','critical','apply-registry-repair','1.0.0',repeat('4',32),
  'foundation:layer-41:aaaaaaaa',repeat('a',64),'human:layer42-test',
  'explicit-human',now()-interval '2 minutes',now()+interval '10 minutes',
  '{"test":"layer42"}'::jsonb,
  encode(extensions.digest(convert_to('{"test": "layer42"}'::jsonb::text,'UTF8'),'sha256'),'hex')
);

insert into foundation.remediation_approval_events(
  event_id,receipt_id,event_type,reason_code,action_key,incident_event_id,
  evidence_fingerprint,release_ref,proposal_sha256,occurred_at
)
values (
  '42000000-0000-4000-8000-000000000202'::uuid,
  '42000000-0000-4000-8000-000000000201'::uuid,'consumed',
  'remediation-approval-consumed','apply-registry-repair',
  '42000000-0000-4000-8000-000000000101'::uuid,repeat('4',32),
  'foundation:layer-41:aaaaaaaa',repeat('a',64),now()-interval '90 seconds'
);

insert into foundation.remediation_execution_admissions(
  admission_id,approval_receipt_id,approval_consumption_event_id,environment,
  incident_event_id,incident_key,action_key,operation_contract,target_authority,
  mutation_shape,policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  admitted_at,expires_at,admission,admission_sha256
)
values (
  '42000000-0000-4000-8000-000000000203'::uuid,
  '42000000-0000-4000-8000-000000000201'::uuid,
  '42000000-0000-4000-8000-000000000202'::uuid,'production',
  '42000000-0000-4000-8000-000000000101'::uuid,'production:release_projection',
  'apply-registry-repair','shine-foundation/remediation-registry-repair-v1',
  'universe.app_registry','scoped-registry-correction','1.0.0',repeat('4',32),
  'foundation:layer-41:aaaaaaaa',repeat('a',64),
  now()-interval '80 seconds',now()-interval '20 seconds',
  '{"test":"layer42-admission"}'::jsonb,
  encode(extensions.digest(convert_to('{"test": "layer42-admission"}'::jsonb::text,'UTF8'),'sha256'),'hex')
);

insert into foundation.remediation_execution_events(
  event_id,execution_id,admission_id,approval_receipt_id,incident_event_id,
  action_key,event_type,reason_code,proposal_sha256,proposal,before_snapshot,
  mutation_result,after_snapshot,occurred_at
)
values (
  '42000000-0000-4000-8000-000000000204'::uuid,
  '42000000-0000-4000-8000-000000000205'::uuid,
  '42000000-0000-4000-8000-000000000203'::uuid,
  '42000000-0000-4000-8000-000000000201'::uuid,
  '42000000-0000-4000-8000-000000000101'::uuid,
  'apply-registry-repair','executed','scoped-remediation-executed',
  repeat('a',64),'{"test":"layer42-proposal"}'::jsonb,
  '{"projection":{"state":"fail"}}'::jsonb,
  '{"operation":"scoped-registry-correction"}'::jsonb,
  '{"projection":{"state":"fail"}}'::jsonb,
  now()-interval '1 minute'
);

do $health$
declare v jsonb;
begin
  select foundation.get_remediation_verification_control_health_v1() into v;
  if v->>'state'<>'pass'
     or v->>'verifierRoleExists'<>'true'
     or v->>'serviceRoleIsVerifierMember'<>'false'
     or v->>'mutatorRoleIsVerifierMember'<>'false'
     or v->>'serviceRoleCanVerify'<>'false'
     or v->>'mutatorRoleCanVerify'<>'false'
     or v->>'verifierRoleCanVerify'<>'true'
     or v->>'verifierCanInsertVerificationEventsDirectly'<>'false'
     or v->>'executionSuccessAloneClosesIncident'<>'false' then
    raise exception 'Layer 42 verifier separation failed: %',v;
  end if;
end;
$health$;

-- First fresh observation remains unhealthy. Verification must be unresolved and
-- must not create a recovered incident event.
create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $fail$
  select jsonb_build_object(
    'foundationReleaseProjectionHealthResponse','shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','fail','reasonCodes',jsonb_build_array('registry-layer-mismatch'),
    'evidenceFingerprint',repeat('4',32),
    'binding',jsonb_build_object('releaseRef','foundation:layer-41:aaaaaaaa'),
    'registry',jsonb_build_object('readinessReleaseRef','foundation:layer-40:99999999')
  );
$fail$;

set local role foundation_remediation_verifier;
select foundation.verify_scoped_remediation_v1(
  '42000000-0000-4000-8000-000000000301'::uuid,
  '42000000-0000-4000-8000-000000000302'::uuid,
  '42000000-0000-4000-8000-000000000204'::uuid,now()
);
reset role;

do $unresolved$
declare v foundation.remediation_verification_events%rowtype;
begin
  select * into v from foundation.remediation_verification_events
  where verification_id='42000000-0000-4000-8000-000000000302'::uuid;
  if v.event_type<>'unresolved' or v.projection_state<>'fail'
     or v.closure_transition_event_id is not null then
    raise exception 'Unhealthy fresh projection must remain unresolved: %',row_to_json(v);
  end if;
  if (select event_type from foundation.current_foundation_control_plane_incident_state
      where incident_key='production:release_projection')<>'opened' then
    raise exception 'Unresolved verification must not close incident';
  end if;
end;
$unresolved$;

-- Separate approval/consumption/admission chains are used for later cases so
-- Layers 39-41 single-use semantics remain intact.
insert into foundation.remediation_approval_receipts(
  receipt_id,environment,incident_event_id,incident_key,incident_state,severity,
  action_key,policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  approved_by,approval_method,approved_at,expires_at,receipt,receipt_sha256
)
select
  '42000000-0000-4000-8000-000000000212'::uuid,environment,incident_event_id,
  incident_key,incident_state,severity,action_key,policy_version,
  evidence_fingerprint,release_ref,proposal_sha256,'human:layer42-test-2',
  approval_method,approved_at,expires_at,'{"test":"layer42-receipt-2"}'::jsonb,
  encode(extensions.digest(convert_to('{"test": "layer42-receipt-2"}'::jsonb::text,'UTF8'),'sha256'),'hex')
from foundation.remediation_approval_receipts
where receipt_id='42000000-0000-4000-8000-000000000201'::uuid;

insert into foundation.remediation_approval_events(
  event_id,receipt_id,event_type,reason_code,action_key,incident_event_id,
  evidence_fingerprint,release_ref,proposal_sha256,occurred_at
)
select
  '42000000-0000-4000-8000-000000000213'::uuid,
  '42000000-0000-4000-8000-000000000212'::uuid,event_type,reason_code,
  action_key,incident_event_id,evidence_fingerprint,release_ref,proposal_sha256,occurred_at
from foundation.remediation_approval_events
where event_id='42000000-0000-4000-8000-000000000202'::uuid;

insert into foundation.remediation_execution_admissions(
  admission_id,approval_receipt_id,approval_consumption_event_id,environment,
  incident_event_id,incident_key,action_key,operation_contract,target_authority,
  mutation_shape,policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  admitted_at,expires_at,admission,admission_sha256
)
select
  '42000000-0000-4000-8000-000000000210'::uuid,
  '42000000-0000-4000-8000-000000000212'::uuid,
  '42000000-0000-4000-8000-000000000213'::uuid,environment,incident_event_id,
  incident_key,action_key,operation_contract,target_authority,mutation_shape,
  policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  admitted_at,expires_at,'{"test":"layer42-admission-2"}'::jsonb,
  encode(extensions.digest(convert_to('{"test": "layer42-admission-2"}'::jsonb::text,'UTF8'),'sha256'),'hex')
from foundation.remediation_execution_admissions
where admission_id='42000000-0000-4000-8000-000000000203'::uuid;

-- A separate executed remediation event is used for the successful verification.
insert into foundation.remediation_execution_events(
  event_id,execution_id,admission_id,approval_receipt_id,incident_event_id,
  action_key,event_type,reason_code,proposal_sha256,proposal,before_snapshot,
  mutation_result,after_snapshot,occurred_at
)
select
  '42000000-0000-4000-8000-000000000206'::uuid,
  '42000000-0000-4000-8000-000000000207'::uuid,
  '42000000-0000-4000-8000-000000000210'::uuid,
  '42000000-0000-4000-8000-000000000212'::uuid,
  incident_event_id,action_key,event_type,
  reason_code,proposal_sha256,proposal,before_snapshot,mutation_result,
  after_snapshot,now()
from foundation.remediation_execution_events
where event_id='42000000-0000-4000-8000-000000000204'::uuid;

create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',p_as_of timestamptz default now()
)
returns jsonb language sql stable security definer set search_path='' as $aligned$
  select jsonb_build_object(
    'foundationReleaseProjectionHealthResponse','shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','aligned','reasonCodes','[]'::jsonb,
    'evidenceFingerprint',repeat('5',32),
    'binding',jsonb_build_object('releaseRef','foundation:layer-41:aaaaaaaa'),
    'registry',jsonb_build_object('readinessReleaseRef','foundation:layer-41:aaaaaaaa')
  );
$aligned$;

set local role foundation_remediation_verifier;
select foundation.verify_scoped_remediation_v1(
  '42000000-0000-4000-8000-000000000303'::uuid,
  '42000000-0000-4000-8000-000000000304'::uuid,
  '42000000-0000-4000-8000-000000000206'::uuid,now()
);
reset role;

do $verified$
declare v foundation.remediation_verification_events%rowtype; h text;
begin
  select * into v from foundation.remediation_verification_events
  where verification_id='42000000-0000-4000-8000-000000000304'::uuid;
  h:=encode(extensions.digest(convert_to(v.verification::text,'UTF8'),'sha256'),'hex');
  if v.event_type<>'verified' or v.projection_state<>'aligned'
     or v.closure_transition_event_id is null or v.verification_sha256<>h then
    raise exception 'Aligned fresh projection must verify and record recovery: %',row_to_json(v);
  end if;
  if (select event_type from foundation.current_foundation_control_plane_incident_state
      where incident_key='production:release_projection')<>'recovered' then
    raise exception 'Verified remediation must transition incident to recovered';
  end if;
end;
$verified$;

-- Failed execution cannot be verified or close anything.
insert into foundation.remediation_approval_receipts(
  receipt_id,environment,incident_event_id,incident_key,incident_state,severity,
  action_key,policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  approved_by,approval_method,approved_at,expires_at,receipt,receipt_sha256
)
select
  '42000000-0000-4000-8000-000000000214'::uuid,environment,incident_event_id,
  incident_key,incident_state,severity,action_key,policy_version,
  evidence_fingerprint,release_ref,proposal_sha256,'human:layer42-test-3',
  approval_method,approved_at,expires_at,'{"test":"layer42-receipt-3"}'::jsonb,
  encode(extensions.digest(convert_to('{"test": "layer42-receipt-3"}'::jsonb::text,'UTF8'),'sha256'),'hex')
from foundation.remediation_approval_receipts
where receipt_id='42000000-0000-4000-8000-000000000201'::uuid;

insert into foundation.remediation_approval_events(
  event_id,receipt_id,event_type,reason_code,action_key,incident_event_id,
  evidence_fingerprint,release_ref,proposal_sha256,occurred_at
)
select
  '42000000-0000-4000-8000-000000000215'::uuid,
  '42000000-0000-4000-8000-000000000214'::uuid,event_type,reason_code,
  action_key,incident_event_id,evidence_fingerprint,release_ref,proposal_sha256,occurred_at
from foundation.remediation_approval_events
where event_id='42000000-0000-4000-8000-000000000202'::uuid;

insert into foundation.remediation_execution_admissions(
  admission_id,approval_receipt_id,approval_consumption_event_id,environment,
  incident_event_id,incident_key,action_key,operation_contract,target_authority,
  mutation_shape,policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  admitted_at,expires_at,admission,admission_sha256
)
select
  '42000000-0000-4000-8000-000000000211'::uuid,
  '42000000-0000-4000-8000-000000000214'::uuid,
  '42000000-0000-4000-8000-000000000215'::uuid,environment,incident_event_id,
  incident_key,action_key,operation_contract,target_authority,mutation_shape,
  policy_version,evidence_fingerprint,release_ref,proposal_sha256,
  admitted_at,expires_at,'{"test":"layer42-admission-3"}'::jsonb,
  encode(extensions.digest(convert_to('{"test": "layer42-admission-3"}'::jsonb::text,'UTF8'),'sha256'),'hex')
from foundation.remediation_execution_admissions
where admission_id='42000000-0000-4000-8000-000000000203'::uuid;

insert into foundation.remediation_execution_events(
  event_id,execution_id,admission_id,approval_receipt_id,incident_event_id,
  action_key,event_type,reason_code,proposal_sha256,proposal,before_snapshot,
  error_detail,occurred_at
)
select
  '42000000-0000-4000-8000-000000000208'::uuid,
  '42000000-0000-4000-8000-000000000209'::uuid,
  '42000000-0000-4000-8000-000000000211'::uuid,
  '42000000-0000-4000-8000-000000000214'::uuid,
  incident_event_id,action_key,'failed',
  'scoped-remediation-mutation-failed',proposal_sha256,proposal,before_snapshot,
  'test failure',now()
from foundation.remediation_execution_events
where event_id='42000000-0000-4000-8000-000000000204'::uuid;

set local role foundation_remediation_verifier;
select foundation.verify_scoped_remediation_v1(
  '42000000-0000-4000-8000-000000000305'::uuid,
  '42000000-0000-4000-8000-000000000306'::uuid,
  '42000000-0000-4000-8000-000000000208'::uuid,now()
);
reset role;

do $failed_denied$
begin
  if not exists(
    select 1 from foundation.remediation_verification_events
    where verification_id='42000000-0000-4000-8000-000000000306'::uuid
      and event_type='denied'
      and reason_code='remediation-execution-not-successful'
      and closure_transition_event_id is null
  ) then
    raise exception 'Failed execution must be denied verification';
  end if;
end;
$failed_denied$;

do $security$
begin
  if has_function_privilege('service_role','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE')
     or has_function_privilege('foundation_remediation_mutator','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE')
     or not has_function_privilege('foundation_remediation_verifier','foundation.verify_scoped_remediation_v1(uuid,uuid,uuid,timestamptz)','EXECUTE')
     or pg_has_role('foundation_remediation_mutator','foundation_remediation_verifier','MEMBER') then
    raise exception 'Verification authority separation failed';
  end if;
end;
$security$;

rollback;
