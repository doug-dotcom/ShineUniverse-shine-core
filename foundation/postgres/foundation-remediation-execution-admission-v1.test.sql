begin;

-- Layer 40 tests the execution-admission boundary without executing any repair.
-- Replace the live Layer-36 projection reader inside this transaction with a
-- deterministic current incident snapshot. ROLLBACK restores the real reader.

create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer40_projection_stub_a$
  select jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-release-ref-mismatch'),
    'evidenceFingerprint',repeat('4',32),
    'binding',jsonb_build_object(
      'releaseRef','foundation:layer-39:bbbbbbbb'
    ),
    'registry',jsonb_build_object(
      'readinessReleaseRef','foundation:layer-39:bbbbbbbb'
    )
  );
$layer40_projection_stub_a$;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '40000000-0000-4000-8000-000000000001'::uuid,
  'production','fail',repeat('4',32),
  '["registry-release-ref-mismatch"]'::jsonb,
  foundation.get_foundation_release_projection_health_v1('production',now()),
  now()-interval '10 minutes',
  now()-interval '10 minutes'
);

insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '40000000-0000-4000-8000-000000000101'::uuid,
  'production:release_projection','production','release_projection',
  'opened','fail','critical',
  '["registry-release-ref-mismatch"]'::jsonb,
  repeat('4',32),
  '40000000-0000-4000-8000-000000000001'::uuid,
  now()-interval '10 minutes',
  300,600,
  foundation.get_foundation_release_projection_health_v1('production',now()),
  now()-interval '5 minutes',
  'test:layer40:critical-incident'
);


do $layer40_policy_precondition$
declare
  v jsonb;
begin
  select foundation.evaluate_control_plane_incident_response_v1(
    'apply-registry-repair','production'
  ) into v;

  if v->>'incidentState'<>'critical'
     or v->>'decision'<>'approval-required'
     or v->>'requiredControl'<>'external-approval' then
    raise exception 'Layer 40 fixture must require external approval: %',v;
  end if;
end;
$layer40_policy_precondition$;


set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '40000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  'human:layer40-test',
  'explicit-human',
  now()-interval '1 minute',
  now()+interval '10 minutes'
);

reset role;


set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '40000000-0000-4000-8000-000000000301'::uuid,
  '40000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  now()
);

reset role;


do $layer40_control_health$
declare
  v jsonb;
begin
  select foundation.get_remediation_execution_admission_control_health_v1()
    into v;

  if v->>'state'<>'pass'
     or v->>'executorRoleExists'<>'true'
     or v->>'serviceRoleIsExecutorMember'<>'false'
     or v->>'approverRoleIsExecutorMember'<>'false'
     or v->>'serviceRoleCanIssueAdmission'<>'false'
     or v->>'approverRoleCanIssueAdmission'<>'false'
     or v->>'executorRoleCanIssueAdmission'<>'true'
     or v->>'serviceRoleCanInsertAdmissionsDirectly'<>'false'
     or v->>'serviceRoleCanInsertAdmissionEventsDirectly'<>'false'
     or v->>'activeExecutionOperationCount'<>'3'
     or v->>'executesAction'<>'false' then
    raise exception 'Layer 40 execution role separation must pass: %',v;
  end if;

  if exists (
    select 1
    from foundation.remediation_execution_operations
    where action_key='auto-repair-authoritative-truth'
  ) then
    raise exception 'Automatic repair must never be an execution operation';
  end if;
end;
$layer40_control_health$;


set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '40000000-0000-4000-8000-000000000401'::uuid,
  '40000000-0000-4000-8000-000000000501'::uuid,
  '40000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('f',64),
  now()
);

reset role;


do $layer40_wrong_proposal_denied$
declare
  v_admissions integer;
  v_denied integer;
begin
  select count(*) into v_admissions
  from foundation.remediation_execution_admissions
  where approval_receipt_id=
    '40000000-0000-4000-8000-000000000201'::uuid;

  select count(*) into v_denied
  from foundation.remediation_execution_admission_events
  where approval_receipt_id=
      '40000000-0000-4000-8000-000000000201'::uuid
    and event_type='denied'
    and reason_code='remediation-execution-proposal-mismatch';

  if v_admissions<>0 or v_denied<>1 then
    raise exception 'Wrong proposal must deny without issuing admission: admissions %, denied %',
      v_admissions,v_denied;
  end if;
end;
$layer40_wrong_proposal_denied$;


set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '40000000-0000-4000-8000-000000000402'::uuid,
  '40000000-0000-4000-8000-000000000502'::uuid,
  '40000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  now()
);

reset role;


do $layer40_admission_integrity$
declare
  a foundation.remediation_execution_admissions%rowtype;
  v_status jsonb;
  v_expected text;
begin
  select * into a
  from foundation.remediation_execution_admissions
  where admission_id='40000000-0000-4000-8000-000000000502'::uuid;

  if a.admission_id is null
     or a.action_key<>'apply-registry-repair'
     or a.operation_contract<>
        'shine-foundation/remediation-registry-repair-v1'
     or a.target_authority<>'universe.app_registry'
     or a.mutation_shape<>'scoped-registry-correction'
     or a.evidence_fingerprint<>repeat('4',32)
     or a.release_ref<>'foundation:layer-39:bbbbbbbb'
     or a.proposal_sha256<>repeat('a',64)
     or a.expires_at>a.admitted_at+interval '60 seconds' then
    raise exception 'Execution admission scope/TTL is invalid: %',row_to_json(a);
  end if;

  v_expected:=encode(
    extensions.digest(convert_to(a.admission::text,'UTF8'),'sha256'),
    'hex'
  );

  if a.admission_sha256<>v_expected
     or a.admission->>'singleUse'<>'true'
     or a.admission->>'mayAttemptExecution'<>'true'
     or a.admission->>'executesAction'<>'false' then
    raise exception 'Execution admission integrity/authority boundary failed: %',
      a.admission;
  end if;

  select foundation.get_remediation_execution_admission_status_v1(
    a.admission_id
  ) into v_status;

  if v_status->>'status'<>'active'
     or v_status->>'integrityVerified'<>'true'
     or v_status->>'mayAttemptExecution'<>'true'
     or v_status->>'executesAction'<>'false' then
    raise exception 'Fresh execution admission should be active but non-executing: %',
      v_status;
  end if;
end;
$layer40_admission_integrity$;


set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '40000000-0000-4000-8000-000000000403'::uuid,
  '40000000-0000-4000-8000-000000000503'::uuid,
  '40000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  now()
);

reset role;


do $layer40_duplicate_admission_denied$
declare
  v_admitted integer;
  v_denied integer;
begin
  select count(*) into v_admitted
  from foundation.remediation_execution_admissions
  where approval_receipt_id=
    '40000000-0000-4000-8000-000000000201'::uuid;

  select count(*) into v_denied
  from foundation.remediation_execution_admission_events
  where approval_receipt_id=
      '40000000-0000-4000-8000-000000000201'::uuid
    and event_type='denied'
    and reason_code='remediation-execution-admission-already-issued';

  if v_admitted<>1 or v_denied<>1 then
    raise exception 'One consumed approval may issue at most one execution admission: admitted %, denied %',
      v_admitted,v_denied;
  end if;
end;
$layer40_duplicate_admission_denied$;


-- A second approval exists but is intentionally not consumed.
set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '40000000-0000-4000-8000-000000000202'::uuid,
  'apply-release-ledger-repair',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('b',64),
  'human:layer40-unconsumed',
  'explicit-human',
  now()-interval '1 minute',
  now()+interval '10 minutes'
);

reset role;


set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '40000000-0000-4000-8000-000000000404'::uuid,
  '40000000-0000-4000-8000-000000000504'::uuid,
  '40000000-0000-4000-8000-000000000202'::uuid,
  'apply-release-ledger-repair',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('b',64),
  now()
);

reset role;


do $layer40_unconsumed_denied$
declare
  v integer;
begin
  select count(*) into v
  from foundation.remediation_execution_admission_events
  where approval_receipt_id=
      '40000000-0000-4000-8000-000000000202'::uuid
    and event_type='denied'
    and reason_code='remediation-approval-not-consumed';

  if v<>1 then
    raise exception 'Unconsumed approval must not produce execution admission';
  end if;
end;
$layer40_unconsumed_denied$;


-- A third approval is consumed while valid, then presented after expiry.
set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '40000000-0000-4000-8000-000000000203'::uuid,
  'rebind-release-identity',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('c',64),
  'governance:layer40-expiry',
  'external-governance',
  now()-interval '1 minute',
  now()+interval '30 seconds'
);

reset role;


set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '40000000-0000-4000-8000-000000000303'::uuid,
  '40000000-0000-4000-8000-000000000203'::uuid,
  'rebind-release-identity',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('c',64),
  now()
);

reset role;


set local role foundation_remediation_executor;

select foundation.issue_remediation_execution_admission_v1(
  '40000000-0000-4000-8000-000000000405'::uuid,
  '40000000-0000-4000-8000-000000000505'::uuid,
  '40000000-0000-4000-8000-000000000203'::uuid,
  'rebind-release-identity',
  '40000000-0000-4000-8000-000000000101'::uuid,
  repeat('c',64),
  now()+interval '31 seconds'
);

reset role;


do $layer40_expired_denied$
declare
  v integer;
begin
  select count(*) into v
  from foundation.remediation_execution_admission_events
  where approval_receipt_id=
      '40000000-0000-4000-8000-000000000203'::uuid
    and event_type='denied'
    and reason_code='remediation-approval-expired';

  if v<>1 then
    raise exception 'Expired consumed approval must not produce execution admission';
  end if;
end;
$layer40_expired_denied$;


-- Change the live evidence and current incident. Existing admission must become stale.
create or replace function foundation.get_foundation_release_projection_health_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer40_projection_stub_b$
  select jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-layer-mismatch'),
    'evidenceFingerprint',repeat('5',32),
    'binding',jsonb_build_object(
      'releaseRef','foundation:layer-39:bbbbbbbb'
    ),
    'registry',jsonb_build_object(
      'readinessReleaseRef','foundation:layer-39:bbbbbbbb'
    )
  );
$layer40_projection_stub_b$;

insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '40000000-0000-4000-8000-000000000002'::uuid,
  'production','fail',repeat('5',32),
  '["registry-layer-mismatch"]'::jsonb,
  foundation.get_foundation_release_projection_health_v1('production',now()),
  now(),
  now()
);

insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '40000000-0000-4000-8000-000000000102'::uuid,
  'production:release_projection','production','release_projection',
  'changed','fail','critical',
  '["registry-layer-mismatch"]'::jsonb,
  repeat('5',32),
  '40000000-0000-4000-8000-000000000002'::uuid,
  now()-interval '10 minutes',
  300,700,
  foundation.get_foundation_release_projection_health_v1('production',now()),
  now(),
  'test:layer40:changed-incident'
);


do $layer40_existing_admission_stale$
declare
  v jsonb;
begin
  select foundation.get_remediation_execution_admission_status_v1(
    '40000000-0000-4000-8000-000000000502'::uuid
  ) into v;

  if v->>'status'<>'stale'
     or v->>'mayAttemptExecution'<>'false'
     or v->>'executesAction'<>'false' then
    raise exception 'Changed live evidence must invalidate old execution admission: %',
      v;
  end if;
end;
$layer40_existing_admission_stale$;


do $layer40_security$
begin
  if has_function_privilege(
    'service_role',
    'foundation.issue_remediation_execution_admission_v1(uuid,uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role must not issue execution admissions';
  end if;

  if has_function_privilege(
    'foundation_remediation_approver',
    'foundation.issue_remediation_execution_admission_v1(uuid,uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'approver role must not issue execution admissions';
  end if;

  if not has_function_privilege(
    'foundation_remediation_executor',
    'foundation.issue_remediation_execution_admission_v1(uuid,uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'executor role must issue execution admissions';
  end if;

  if pg_has_role(
    'service_role','foundation_remediation_executor','MEMBER'
  ) or pg_has_role(
    'foundation_remediation_approver',
    'foundation_remediation_executor','MEMBER'
  ) then
    raise exception 'executor authority must remain separate from service and approver roles';
  end if;

  if has_table_privilege(
    'service_role','foundation.remediation_execution_admissions','INSERT'
  ) or has_table_privilege(
    'service_role','foundation.remediation_execution_admission_events','INSERT'
  ) then
    raise exception 'service_role must not bypass execution admission gate';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.get_remediation_execution_admission_status_v1(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'foundation.get_remediation_execution_admission_status_v1(uuid)',
    'EXECUTE'
  ) then
    raise exception 'execution admission status must remain internal';
  end if;
end;
$layer40_security$;

rollback;
