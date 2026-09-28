begin;

-- Layer 39 uses a synthetic critical incident so approval receipts can be tested
-- without mutating the real CI release projection.

insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '39000000-0000-4000-8000-000000000001'::uuid,
  'production','fail',repeat('9',32),
  '["registry-release-ref-mismatch"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-release-ref-mismatch'),
    'evidenceFingerprint',repeat('9',32),
    'binding',jsonb_build_object(
      'releaseRef','foundation:layer-38:aaaaaaaa'
    ),
    'registry',jsonb_build_object(
      'readinessReleaseRef','foundation:layer-38:aaaaaaaa'
    )
  ),
  now()+interval '1 second',
  now()+interval '1 second'
);

insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '39000000-0000-4000-8000-000000000101'::uuid,
  'production:release_projection','production','release_projection',
  'opened','fail','critical',
  '["registry-release-ref-mismatch"]'::jsonb,
  repeat('9',32),
  '39000000-0000-4000-8000-000000000001'::uuid,
  now()-interval '10 minutes',
  300,600,
  (select snapshot
   from foundation.foundation_release_projection_observations
   where observation_id='39000000-0000-4000-8000-000000000001'::uuid),
  now()+interval '2 seconds',
  'test:layer39:critical-incident'
);


do $layer39_control_health$
declare
  v jsonb;
begin
  select foundation.get_remediation_approval_control_health_v1() into v;

  if v->>'state' <> 'pass'
     or v->>'approverRoleExists' <> 'true'
     or v->>'serviceRoleCanIssue' <> 'false'
     or v->>'foundationRuntimeCanIssue' <> 'false'
     or v->>'serviceRoleIsApproverMember' <> 'false'
     or v->>'serviceRoleCanConsume' <> 'true'
     or v->>'foundationRuntimeCanConsume' <> 'false'
     or v->>'serviceRoleCanInsertReceiptsDirectly' <> 'false'
     or v->>'serviceRoleCanInsertEventsDirectly' <> 'false'
     or v->>'executionAuthority' <> 'false' then
    raise exception 'Layer 39 approval role separation must pass: %',v;
  end if;
end;
$layer39_control_health$;


do $layer39_policy_precondition$
declare
  v jsonb;
begin
  select foundation.evaluate_control_plane_incident_response_v1(
    'apply-registry-repair','production'
  ) into v;

  if v->>'incidentState' <> 'critical'
     or v->>'decision' <> 'approval-required'
     or v->>'requiredControl' <> 'external-approval' then
    raise exception 'Synthetic critical incident must require external approval: %',v;
  end if;
end;
$layer39_policy_precondition$;


set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  'human:layer39-test',
  'explicit-human',
  now()-interval '1 second',
  now()+interval '10 minutes'
);

reset role;


do $layer39_receipt_integrity$
declare
  r foundation.remediation_approval_receipts%rowtype;
  v_status jsonb;
  v_expected text;
begin
  select * into r
  from foundation.remediation_approval_receipts
  where receipt_id='39000000-0000-4000-8000-000000000201'::uuid;

  if r.receipt_id is null
     or r.action_key <> 'apply-registry-repair'
     or r.incident_event_id <>
        '39000000-0000-4000-8000-000000000101'::uuid
     or r.evidence_fingerprint <> repeat('9',32)
     or r.release_ref <> 'foundation:layer-38:aaaaaaaa'
     or r.proposal_sha256 <> repeat('a',64)
     or r.incident_state <> 'critical'
     or r.severity <> 'critical' then
    raise exception 'Approval receipt scope is incomplete: %',row_to_json(r);
  end if;

  v_expected:=encode(
    extensions.digest(convert_to(r.receipt::text,'UTF8'),'sha256'),
    'hex'
  );

  if r.receipt_sha256 <> v_expected
     or r.receipt->>'singleUse' <> 'true'
     or r.receipt->>'executionAuthority' <> 'false'
     or r.receipt->>'executesAction' <> 'false' then
    raise exception 'Approval receipt integrity/authority boundary failed: %',r.receipt;
  end if;

  select foundation.get_remediation_approval_status_v1(r.receipt_id)
    into v_status;

  if v_status->>'status' <> 'active'
     or v_status->>'integrityVerified' <> 'true'
     or v_status->>'incidentStillCurrent' <> 'true'
     or v_status->>'executionAuthority' <> 'false' then
    raise exception 'Fresh approval receipt should be active and non-executing: %',v_status;
  end if;
end;
$layer39_receipt_integrity$;


set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000301'::uuid,
  '39000000-0000-4000-8000-000000000201'::uuid,
  'apply-release-ledger-repair',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  now()+interval '3 seconds'
);

reset role;


do $layer39_wrong_scope_not_consumed$
declare
  v_consumed integer;
  v_denied integer;
begin
  select count(*) filter (where event_type='consumed'),
         count(*) filter (where event_type='denied')
    into v_consumed,v_denied
  from foundation.remediation_approval_events
  where receipt_id='39000000-0000-4000-8000-000000000201'::uuid;

  if v_consumed<>0 or v_denied<>1 then
    raise exception 'Wrong action must deny without consuming approval: consumed %, denied %',
      v_consumed,v_denied;
  end if;
end;
$layer39_wrong_scope_not_consumed$;


set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000302'::uuid,
  '39000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  now()+interval '4 seconds'
);

reset role;


do $layer39_consumed_once$
declare
  v_status jsonb;
  v_consumed integer;
begin
  select foundation.get_remediation_approval_status_v1(
    '39000000-0000-4000-8000-000000000201'::uuid
  ) into v_status;

  select count(*) into v_consumed
  from foundation.remediation_approval_events
  where receipt_id='39000000-0000-4000-8000-000000000201'::uuid
    and event_type='consumed';

  if v_status->>'status' <> 'consumed'
     or v_consumed<>1 then
    raise exception 'Correct scope must consume receipt exactly once: %, count %',
      v_status,v_consumed;
  end if;
end;
$layer39_consumed_once$;


set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000303'::uuid,
  '39000000-0000-4000-8000-000000000201'::uuid,
  'apply-registry-repair',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('a',64),
  now()+interval '5 seconds'
);

reset role;


do $layer39_replay_denied$
declare
  v_consumed integer;
  v_replay_denied integer;
begin
  select count(*) filter (where event_type='consumed'),
         count(*) filter (
           where event_type='denied'
             and reason_code='remediation-approval-already-consumed'
         )
  into v_consumed,v_replay_denied
  from foundation.remediation_approval_events
  where receipt_id='39000000-0000-4000-8000-000000000201'::uuid;

  if v_consumed<>1 or v_replay_denied<>1 then
    raise exception 'Consumed receipt must deny replay: consumed %, replayDenied %',
      v_consumed,v_replay_denied;
  end if;
end;
$layer39_replay_denied$;


set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000202'::uuid,
  'apply-release-ledger-repair',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('b',64),
  'governance:layer39-test',
  'external-governance',
  now()-interval '10 minutes',
  now()-interval '1 minute'
);

reset role;


set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000304'::uuid,
  '39000000-0000-4000-8000-000000000202'::uuid,
  'apply-release-ledger-repair',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('b',64),
  now()
);

reset role;


do $layer39_expired_denied$
declare
  v integer;
begin
  select count(*) into v
  from foundation.remediation_approval_events
  where receipt_id='39000000-0000-4000-8000-000000000202'::uuid
    and event_type='denied'
    and reason_code='remediation-approval-expired';

  if v<>1 then
    raise exception 'Expired approval must be denied without consumption';
  end if;
end;
$layer39_expired_denied$;


set local role foundation_remediation_approver;

select foundation.issue_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000203'::uuid,
  'rebind-release-identity',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('c',64),
  'human:layer39-stale-test',
  'explicit-human',
  now()-interval '1 second',
  now()+interval '10 minutes'
);

reset role;


insert into foundation.foundation_release_projection_observations(
  observation_id,environment,reconciliation_state,evidence_fingerprint,
  reason_codes,snapshot,observed_at,recorded_at
)
values (
  '39000000-0000-4000-8000-000000000002'::uuid,
  'production','fail',repeat('8',32),
  '["registry-layer-mismatch"]'::jsonb,
  jsonb_build_object(
    'foundationReleaseProjectionHealthResponse',
      'shine-foundation/release-projection-health-response-v1',
    'schemaVersion','1.0.0',
    'environment','production',
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-layer-mismatch'),
    'evidenceFingerprint',repeat('8',32),
    'binding',jsonb_build_object(
      'releaseRef','foundation:layer-38:aaaaaaaa'
    )
  ),
  now()+interval '20 seconds',
  now()+interval '20 seconds'
);

insert into foundation.foundation_control_plane_incident_events(
  event_id,incident_key,environment,domain,event_type,source_state,severity,
  reason_codes,evidence_fingerprint,projection_observation_id,
  detection_started_at,persistence_threshold_seconds,persistence_seconds,
  snapshot,occurred_at,evidence_ref
)
values (
  '39000000-0000-4000-8000-000000000102'::uuid,
  'production:release_projection','production','release_projection',
  'changed','fail','critical',
  '["registry-layer-mismatch"]'::jsonb,
  repeat('8',32),
  '39000000-0000-4000-8000-000000000002'::uuid,
  now()-interval '10 minutes',
  300,620,
  (select snapshot
   from foundation.foundation_release_projection_observations
   where observation_id='39000000-0000-4000-8000-000000000002'::uuid),
  now()+interval '20 seconds',
  'test:layer39:changed-incident'
);


set local role service_role;

select foundation.consume_remediation_approval_receipt_v1(
  '39000000-0000-4000-8000-000000000305'::uuid,
  '39000000-0000-4000-8000-000000000203'::uuid,
  'rebind-release-identity',
  '39000000-0000-4000-8000-000000000101'::uuid,
  repeat('c',64),
  now()+interval '21 seconds'
);

reset role;


do $layer39_stale_incident_denied$
declare
  v integer;
begin
  select count(*) into v
  from foundation.remediation_approval_events
  where receipt_id='39000000-0000-4000-8000-000000000203'::uuid
    and event_type='denied'
    and reason_code='remediation-approval-incident-no-longer-current';

  if v<>1 then
    raise exception 'Approval must become stale when the incident evidence changes';
  end if;
end;
$layer39_stale_incident_denied$;


set local role foundation_remediation_approver;

do $layer39_auto_repair_never_approvable$
begin
  begin
    perform foundation.issue_remediation_approval_receipt_v1(
      '39000000-0000-4000-8000-000000000204'::uuid,
      'auto-repair-authoritative-truth',
      '39000000-0000-4000-8000-000000000102'::uuid,
      repeat('d',64),
      'human:layer39-deny-test',
      'explicit-human',
      now(),
      now()+interval '10 minutes'
    );
    raise exception 'automatic repair unexpectedly became approvable';
  exception
    when others then
      if sqlerrm not like '%remediation-approval-action-not-approval-required%' then
        raise;
      end if;
  end;
end;
$layer39_auto_repair_never_approvable$;

reset role;


do $layer39_security$
begin
  if has_function_privilege(
    'service_role',
    'foundation.issue_remediation_approval_receipt_v1(uuid,text,uuid,text,text,text,timestamptz,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role must never mint remediation approval';
  end if;

  if pg_has_role(
    'service_role','foundation_remediation_approver','MEMBER'
  ) then
    raise exception 'service_role must not inherit remediation approver role';
  end if;

  if not has_function_privilege(
    'foundation_remediation_approver',
    'foundation.issue_remediation_approval_receipt_v1(uuid,text,uuid,text,text,text,timestamptz,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'dedicated approver role must be able to issue approval receipt';
  end if;

  if not has_function_privilege(
    'service_role',
    'foundation.consume_remediation_approval_receipt_v1(uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role must be able to consume, but not issue, approval';
  end if;

  if has_table_privilege(
    'service_role','foundation.remediation_approval_receipts','INSERT'
  ) or has_table_privilege(
    'service_role','foundation.remediation_approval_events','INSERT'
  ) then
    raise exception 'service_role must not bypass receipt functions with direct inserts';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.get_remediation_approval_status_v1(uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'foundation.get_remediation_approval_status_v1(uuid)',
    'EXECUTE'
  ) then
    raise exception 'approval status must remain internal';
  end if;
end;
$layer39_security$;

rollback;
