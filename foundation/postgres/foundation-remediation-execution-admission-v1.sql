-- Foundation Layer 40: remediation execution admission.
-- A consumed Layer-39 approval may be presented to a separate executor gate.
-- The gate independently revalidates live incident/policy/projection scope and may
-- issue a short-lived execution admission. It never performs the remediation.

do $layer40_roles$
begin
  if not exists (
    select 1 from pg_roles where rolname='foundation_remediation_executor'
  ) then
    create role foundation_remediation_executor nologin noinherit;
  end if;
end;
$layer40_roles$;

alter role foundation_remediation_executor nologin noinherit;
grant foundation_remediation_executor to postgres;
grant usage on schema foundation to foundation_remediation_executor;


create table foundation.remediation_execution_operations (
  action_key text primary key
    references foundation.control_plane_incident_response_actions(action_key),
  operation_contract text not null
    check (operation_contract ~ '^shine-foundation/[a-z0-9._/-]+-v[0-9]+$'),
  target_authority text not null
    check (target_authority in (
      'universe.app_registry',
      'universe.readiness_releases',
      'foundation.release_identity'
    )),
  mutation_shape text not null
    check (mutation_shape in (
      'scoped-registry-correction',
      'scoped-release-ledger-correction',
      'append-only-release-rebind'
    )),
  max_admission_seconds integer not null default 60
    check (max_admission_seconds between 15 and 60),
  lifecycle text not null default 'active'
    check (lifecycle in ('active','disabled','retired')),
  description text not null,
  evidence_ref text not null,
  registered_at timestamptz not null default now()
);

alter table foundation.remediation_execution_operations enable row level security;

create policy foundation_runtime_remediation_execution_operations_select
on foundation.remediation_execution_operations
for select
to foundation_runtime
using (true);

revoke all on foundation.remediation_execution_operations
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       service_role;
grant select on foundation.remediation_execution_operations
  to foundation_runtime,foundation_remediation_executor,service_role;


insert into foundation.remediation_execution_operations(
  action_key,operation_contract,target_authority,mutation_shape,
  max_admission_seconds,lifecycle,description,evidence_ref
)
values
  (
    'apply-registry-repair',
    'shine-foundation/remediation-registry-repair-v1',
    'universe.app_registry',
    'scoped-registry-correction',
    60,'active',
    'Future executor may apply only the exact approved Foundation registry correction.',
    'foundation:layer40:operation:registry-repair:v1'
  ),
  (
    'apply-release-ledger-repair',
    'shine-foundation/remediation-release-ledger-repair-v1',
    'universe.readiness_releases',
    'scoped-release-ledger-correction',
    60,'active',
    'Future executor may apply only the exact approved readiness-release ledger correction.',
    'foundation:layer40:operation:release-ledger-repair:v1'
  ),
  (
    'rebind-release-identity',
    'shine-foundation/remediation-release-rebind-v1',
    'foundation.release_identity',
    'append-only-release-rebind',
    60,'active',
    'Future executor may append only the exact approved release-identity rebind.',
    'foundation:layer40:operation:release-rebind:v1'
  )
on conflict (action_key) do nothing;


create table foundation.remediation_execution_admissions (
  admission_sequence bigint generated always as identity primary key,
  admission_id uuid not null unique,
  approval_receipt_id uuid not null unique
    references foundation.remediation_approval_receipts(receipt_id),
  approval_consumption_event_id uuid not null unique
    references foundation.remediation_approval_events(event_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  incident_event_id uuid not null
    references foundation.foundation_control_plane_incident_events(event_id),
  incident_key text not null
    check (incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  action_key text not null
    references foundation.remediation_execution_operations(action_key),
  operation_contract text not null,
  target_authority text not null,
  mutation_shape text not null,
  policy_version text not null,
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  release_ref text not null
    check (release_ref ~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'),
  proposal_sha256 text not null
    check (proposal_sha256 ~ '^[a-f0-9]{64}$'),
  admitted_at timestamptz not null,
  expires_at timestamptz not null,
  admission jsonb not null
    check (jsonb_typeof(admission)='object'),
  admission_sha256 text not null
    check (admission_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default now(),
  check (expires_at>admitted_at),
  check (expires_at<=admitted_at+interval '60 seconds')
);

alter table foundation.remediation_execution_admissions enable row level security;

create policy foundation_runtime_remediation_execution_admissions_select
on foundation.remediation_execution_admissions
for select
to foundation_runtime
using (true);

revoke all on foundation.remediation_execution_admissions
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       service_role;
grant select on foundation.remediation_execution_admissions
  to foundation_runtime,service_role;

create index remediation_execution_admissions_incident_idx
  on foundation.remediation_execution_admissions(
    incident_event_id,admitted_at desc,admission_sequence desc
  );

create index remediation_execution_admissions_action_idx
  on foundation.remediation_execution_admissions(
    action_key,admitted_at desc,admission_sequence desc
  );

create trigger remediation_execution_admissions_append_only
before update or delete on foundation.remediation_execution_admissions
for each row execute function foundation.reject_append_only_mutation();


create table foundation.remediation_execution_admission_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique,
  admission_id uuid
    references foundation.remediation_execution_admissions(admission_id),
  approval_receipt_id uuid not null
    references foundation.remediation_approval_receipts(receipt_id),
  event_type text not null
    check (event_type in ('admitted','denied')),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  action_key text,
  incident_event_id uuid,
  evidence_fingerprint text,
  release_ref text,
  proposal_sha256 text,
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (
    evidence_fingerprint is null
    or evidence_fingerprint ~ '^[a-f0-9]{32}$'
  ),
  check (
    release_ref is null
    or release_ref ~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'
  ),
  check (
    proposal_sha256 is null
    or proposal_sha256 ~ '^[a-f0-9]{64}$'
  ),
  check (
    (event_type='admitted' and admission_id is not null)
    or (event_type='denied')
  )
);

alter table foundation.remediation_execution_admission_events enable row level security;

create policy foundation_runtime_remediation_execution_admission_events_select
on foundation.remediation_execution_admission_events
for select
to foundation_runtime
using (true);

revoke all on foundation.remediation_execution_admission_events
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor,
       service_role;
grant select on foundation.remediation_execution_admission_events
  to foundation_runtime,service_role;

create index remediation_execution_admission_events_receipt_idx
  on foundation.remediation_execution_admission_events(
    approval_receipt_id,occurred_at desc,event_sequence desc
  );

create index remediation_execution_admission_events_admission_idx
  on foundation.remediation_execution_admission_events(admission_id);

create trigger remediation_execution_admission_events_append_only
before update or delete on foundation.remediation_execution_admission_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.issue_remediation_execution_admission_v1(
  p_event_id uuid,
  p_admission_id uuid,
  p_approval_receipt_id uuid,
  p_action_key text,
  p_incident_event_id uuid,
  p_proposal_sha256 text,
  p_requested_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer40_issue$
declare
  v_receipt foundation.remediation_approval_receipts%rowtype;
  v_consumption foundation.remediation_approval_events%rowtype;
  v_operation foundation.remediation_execution_operations%rowtype;
  v_current_incident foundation.foundation_control_plane_incident_events%rowtype;
  v_policy jsonb;
  v_projection jsonb;
  v_live_fingerprint text;
  v_live_release_ref text;
  v_receipt_hash text;
  v_reason text;
  v_admission jsonb;
  v_admission_hash text;
  v_expires_at timestamptz;
begin
  if p_event_id is null
     or p_admission_id is null
     or p_approval_receipt_id is null
     or p_incident_event_id is null
     or p_requested_at is null then
    raise exception 'remediation-execution-admission-fields-missing';
  end if;

  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'remediation-execution-admission-action-invalid';
  end if;

  if p_proposal_sha256 is null
     or lower(p_proposal_sha256) !~ '^[a-f0-9]{64}$' then
    raise exception 'remediation-execution-admission-proposal-invalid';
  end if;

  if p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes' then
    raise exception 'remediation-execution-admission-requested-at-invalid';
  end if;

  select * into v_receipt
  from foundation.remediation_approval_receipts
  where receipt_id=p_approval_receipt_id;
  if v_receipt.receipt_id is null then
    return jsonb_build_object(
      'foundationRemediationExecutionAdmissionResponse',
        'shine-foundation/remediation-execution-admission-response-v1',
      'schemaVersion','1.0.0',
      'admitted',false,
      'reasonCode','remediation-approval-receipt-not-found',
      'mayAttemptExecution',false,
      'executesAction',false
    );
  end if;

  v_receipt_hash := encode(
    extensions.digest(
      convert_to(v_receipt.receipt::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select * into v_consumption
  from foundation.remediation_approval_events
  where receipt_id=v_receipt.receipt_id
    and event_type='consumed'
  order by occurred_at desc,event_sequence desc
  limit 1;

  select * into v_operation
  from foundation.remediation_execution_operations
  where action_key=p_action_key
    and lifecycle='active';

  select * into v_current_incident
  from foundation.current_foundation_control_plane_incident_state
  where incident_key=v_receipt.incident_key;

  v_policy :=
    foundation.evaluate_control_plane_incident_response_v1(
      p_action_key,v_receipt.environment
    );

  v_projection :=
    foundation.get_foundation_release_projection_health_v1(
      v_receipt.environment,p_requested_at
    );

  v_live_fingerprint := lower(coalesce(v_projection->>'evidenceFingerprint',''));
  v_live_release_ref := coalesce(
    v_projection#>>'{binding,releaseRef}',
    v_projection#>>'{registry,readinessReleaseRef}'
  );

  v_reason := null;

  if v_receipt.receipt_sha256 is distinct from v_receipt_hash then
    v_reason := 'remediation-approval-integrity-failed';
  elsif v_consumption.event_id is null then
    v_reason := 'remediation-approval-not-consumed';
  elsif p_requested_at<v_receipt.approved_at
     or p_requested_at<v_consumption.occurred_at then
    v_reason := 'remediation-execution-admission-not-yet-valid';
  elsif v_receipt.expires_at<=p_requested_at then
    v_reason := 'remediation-approval-expired';
  elsif v_receipt.action_key is distinct from p_action_key then
    v_reason := 'remediation-execution-action-mismatch';
  elsif v_receipt.incident_event_id is distinct from p_incident_event_id then
    v_reason := 'remediation-execution-incident-mismatch';
  elsif v_receipt.proposal_sha256 is distinct from
        lower(p_proposal_sha256) then
    v_reason := 'remediation-execution-proposal-mismatch';
  elsif v_operation.action_key is null then
    v_reason := 'remediation-execution-operation-not-registered';
  elsif v_current_incident.event_id is distinct from
        v_receipt.incident_event_id
     or v_current_incident.event_type not in ('opened','changed') then
    v_reason := 'remediation-execution-incident-no-longer-current';
  elsif v_current_incident.evidence_fingerprint is distinct from
        v_receipt.evidence_fingerprint then
    v_reason := 'remediation-execution-incident-evidence-mismatch';
  elsif coalesce(v_projection->>'state','unknown')
        not in ('fail','unknown') then
    v_reason := 'remediation-execution-projection-no-longer-incident';
  elsif v_live_fingerprint is distinct from
        v_receipt.evidence_fingerprint then
    v_reason := 'remediation-execution-live-evidence-mismatch';
  elsif v_live_release_ref is distinct from v_receipt.release_ref then
    v_reason := 'remediation-execution-release-mismatch';
  elsif v_policy->>'decision'<>'approval-required'
     or v_policy->>'requiredControl'<>'external-approval'
     or v_policy->>'policyVersion' is distinct from
        v_receipt.policy_version then
    v_reason := 'remediation-execution-policy-no-longer-valid';
  elsif v_consumption.action_key is distinct from v_receipt.action_key
     or v_consumption.incident_event_id is distinct from
        v_receipt.incident_event_id
     or v_consumption.evidence_fingerprint is distinct from
        v_receipt.evidence_fingerprint
     or v_consumption.release_ref is distinct from v_receipt.release_ref
     or v_consumption.proposal_sha256 is distinct from
        v_receipt.proposal_sha256 then
    v_reason := 'remediation-execution-consumption-scope-mismatch';
  elsif exists (
    select 1
    from foundation.remediation_execution_admissions a
    where a.approval_receipt_id=v_receipt.receipt_id
  ) then
    v_reason := 'remediation-execution-admission-already-issued';
  end if;

  if v_reason is not null then
    insert into foundation.remediation_execution_admission_events(
      event_id,admission_id,approval_receipt_id,event_type,reason_code,
      action_key,incident_event_id,evidence_fingerprint,release_ref,
      proposal_sha256,occurred_at
    )
    values (
      p_event_id,null,v_receipt.receipt_id,'denied',v_reason,
      p_action_key,p_incident_event_id,nullif(v_live_fingerprint,''),
      v_live_release_ref,lower(p_proposal_sha256),p_requested_at
    );

    return jsonb_build_object(
      'foundationRemediationExecutionAdmissionResponse',
        'shine-foundation/remediation-execution-admission-response-v1',
      'schemaVersion','1.0.0',
      'admitted',false,
      'approvalReceiptId',v_receipt.receipt_id,
      'reasonCode',v_reason,
      'mayAttemptExecution',false,
      'executesAction',false
    );
  end if;

  v_expires_at :=
    least(
      v_receipt.expires_at,
      p_requested_at
        + make_interval(secs=>v_operation.max_admission_seconds)
    );

  if v_expires_at<=p_requested_at then
    raise exception 'remediation-execution-admission-expiry-invalid';
  end if;

  v_admission := jsonb_build_object(
    'remediationExecutionAdmission',
      'shine-foundation/remediation-execution-admission-v1',
    'schemaVersion','1.0.0',
    'admissionId',p_admission_id,
    'approvalReceiptId',v_receipt.receipt_id,
    'approvalConsumptionEventId',v_consumption.event_id,
    'environment',v_receipt.environment,
    'incidentEventId',v_receipt.incident_event_id,
    'incidentKey',v_receipt.incident_key,
    'actionKey',v_receipt.action_key,
    'operationContract',v_operation.operation_contract,
    'targetAuthority',v_operation.target_authority,
    'mutationShape',v_operation.mutation_shape,
    'policyVersion',v_receipt.policy_version,
    'evidenceFingerprint',v_receipt.evidence_fingerprint,
    'releaseRef',v_receipt.release_ref,
    'proposalSha256',v_receipt.proposal_sha256,
    'admittedAt',p_requested_at,
    'expiresAt',v_expires_at,
    'singleUse',true,
    'mayAttemptExecution',true,
    'executesAction',false
  );

  v_admission_hash := encode(
    extensions.digest(
      convert_to(v_admission::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.remediation_execution_admissions(
    admission_id,approval_receipt_id,approval_consumption_event_id,
    environment,incident_event_id,incident_key,action_key,
    operation_contract,target_authority,mutation_shape,policy_version,
    evidence_fingerprint,release_ref,proposal_sha256,admitted_at,
    expires_at,admission,admission_sha256
  )
  values (
    p_admission_id,v_receipt.receipt_id,v_consumption.event_id,
    v_receipt.environment,v_receipt.incident_event_id,
    v_receipt.incident_key,v_receipt.action_key,
    v_operation.operation_contract,v_operation.target_authority,
    v_operation.mutation_shape,v_receipt.policy_version,
    v_receipt.evidence_fingerprint,v_receipt.release_ref,
    v_receipt.proposal_sha256,p_requested_at,v_expires_at,
    v_admission,v_admission_hash
  );

  insert into foundation.remediation_execution_admission_events(
    event_id,admission_id,approval_receipt_id,event_type,reason_code,
    action_key,incident_event_id,evidence_fingerprint,release_ref,
    proposal_sha256,occurred_at
  )
  values (
    p_event_id,p_admission_id,v_receipt.receipt_id,'admitted',
    'remediation-execution-admitted',
    v_receipt.action_key,v_receipt.incident_event_id,
    v_receipt.evidence_fingerprint,v_receipt.release_ref,
    v_receipt.proposal_sha256,p_requested_at
  );

  return jsonb_build_object(
    'foundationRemediationExecutionAdmissionResponse',
      'shine-foundation/remediation-execution-admission-response-v1',
    'schemaVersion','1.0.0',
    'admitted',true,
    'admissionId',p_admission_id,
    'approvalReceiptId',v_receipt.receipt_id,
    'approvalConsumptionEventId',v_consumption.event_id,
    'actionKey',v_receipt.action_key,
    'operationContract',v_operation.operation_contract,
    'targetAuthority',v_operation.target_authority,
    'mutationShape',v_operation.mutation_shape,
    'evidenceFingerprint',v_receipt.evidence_fingerprint,
    'releaseRef',v_receipt.release_ref,
    'proposalSha256',v_receipt.proposal_sha256,
    'expiresAt',v_expires_at,
    'admissionSha256',v_admission_hash,
    'mayAttemptExecution',true,
    'executesAction',false
  );
end;
$layer40_issue$;

revoke all on function foundation.issue_remediation_execution_admission_v1(
  uuid,uuid,uuid,text,uuid,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       foundation_remediation_approver,service_role;
grant execute on function foundation.issue_remediation_execution_admission_v1(
  uuid,uuid,uuid,text,uuid,text,timestamptz
) to foundation_remediation_executor;


create or replace function foundation.get_remediation_execution_admission_status_v1(
  p_admission_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer40_status$
declare
  v_admission foundation.remediation_execution_admissions%rowtype;
  v_current foundation.foundation_control_plane_incident_events%rowtype;
  v_projection jsonb;
  v_policy jsonb;
  v_operation foundation.remediation_execution_operations%rowtype;
  v_expected_hash text;
  v_status text;
begin
  select * into v_admission
  from foundation.remediation_execution_admissions
  where admission_id=p_admission_id;

  if v_admission.admission_id is null then
    return jsonb_build_object(
      'foundationRemediationExecutionAdmissionStatusResponse',
        'shine-foundation/remediation-execution-admission-status-response-v1',
      'schemaVersion','1.0.0',
      'admissionId',p_admission_id,
      'status','missing',
      'mayAttemptExecution',false,
      'executesAction',false
    );
  end if;

  v_expected_hash := encode(
    extensions.digest(
      convert_to(v_admission.admission::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  select * into v_current
  from foundation.current_foundation_control_plane_incident_state
  where incident_key=v_admission.incident_key;

  v_projection :=
    foundation.get_foundation_release_projection_health_v1(
      v_admission.environment,now()
    );

  v_policy :=
    foundation.evaluate_control_plane_incident_response_v1(
      v_admission.action_key,v_admission.environment
    );

  select * into v_operation
  from foundation.remediation_execution_operations
  where action_key=v_admission.action_key;

  v_status := case
    when v_admission.admission_sha256 is distinct from v_expected_hash
      then 'invalid'
    when v_admission.admitted_at>now()
      then 'not-yet-valid'
    when v_admission.expires_at<=now()
      then 'expired'
    when v_operation.action_key is null
      or v_operation.lifecycle<>'active'
      then 'stale'
    when v_current.event_id is distinct from v_admission.incident_event_id
      or v_current.event_type not in ('opened','changed')
      then 'stale'
    when v_current.evidence_fingerprint is distinct from
         v_admission.evidence_fingerprint
      then 'stale'
    when lower(coalesce(v_projection->>'evidenceFingerprint',''))
         is distinct from v_admission.evidence_fingerprint
      then 'stale'
    when coalesce(
           v_projection#>>'{binding,releaseRef}',
           v_projection#>>'{registry,readinessReleaseRef}'
         ) is distinct from v_admission.release_ref
      then 'stale'
    when v_policy->>'decision'<>'approval-required'
      or v_policy->>'requiredControl'<>'external-approval'
      or v_policy->>'policyVersion' is distinct from v_admission.policy_version
      then 'stale'
    else 'active'
  end;

  return jsonb_build_object(
    'foundationRemediationExecutionAdmissionStatusResponse',
      'shine-foundation/remediation-execution-admission-status-response-v1',
    'schemaVersion','1.0.0',
    'admissionId',v_admission.admission_id,
    'status',v_status,
    'approvalReceiptId',v_admission.approval_receipt_id,
    'approvalConsumptionEventId',v_admission.approval_consumption_event_id,
    'environment',v_admission.environment,
    'incidentEventId',v_admission.incident_event_id,
    'actionKey',v_admission.action_key,
    'operationContract',v_admission.operation_contract,
    'targetAuthority',v_admission.target_authority,
    'mutationShape',v_admission.mutation_shape,
    'policyVersion',v_admission.policy_version,
    'evidenceFingerprint',v_admission.evidence_fingerprint,
    'releaseRef',v_admission.release_ref,
    'proposalSha256',v_admission.proposal_sha256,
    'admittedAt',v_admission.admitted_at,
    'expiresAt',v_admission.expires_at,
    'integrityVerified',
      v_admission.admission_sha256 is not distinct from v_expected_hash,
    'singleUse',true,
    'mayAttemptExecution',v_status='active',
    'executesAction',false
  );
end;
$layer40_status$;

revoke all on function foundation.get_remediation_execution_admission_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor;
grant execute on function foundation.get_remediation_execution_admission_status_v1(uuid)
  to foundation_runtime,service_role;


create or replace function foundation.get_remediation_execution_admission_control_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer40_health$
declare
  v_executor_exists boolean := false;
  v_service_member boolean := false;
  v_approver_member boolean := false;
  v_service_can_issue boolean := false;
  v_approver_can_issue boolean := false;
  v_executor_can_issue boolean := false;
  v_service_direct_admission_insert boolean := false;
  v_service_direct_event_insert boolean := false;
  v_operation_count integer := 0;
  v_state text := 'pass';
begin
  select exists(
    select 1 from pg_roles
    where rolname='foundation_remediation_executor'
      and not rolcanlogin
  ) into v_executor_exists;

  v_service_member := pg_has_role(
    'service_role','foundation_remediation_executor','MEMBER'
  );

  v_approver_member := pg_has_role(
    'foundation_remediation_approver',
    'foundation_remediation_executor',
    'MEMBER'
  );

  v_service_can_issue := has_function_privilege(
    'service_role',
    'foundation.issue_remediation_execution_admission_v1(uuid,uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  );

  v_approver_can_issue := has_function_privilege(
    'foundation_remediation_approver',
    'foundation.issue_remediation_execution_admission_v1(uuid,uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  );

  v_executor_can_issue := has_function_privilege(
    'foundation_remediation_executor',
    'foundation.issue_remediation_execution_admission_v1(uuid,uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  );

  v_service_direct_admission_insert := has_table_privilege(
    'service_role',
    'foundation.remediation_execution_admissions',
    'INSERT'
  );

  v_service_direct_event_insert := has_table_privilege(
    'service_role',
    'foundation.remediation_execution_admission_events',
    'INSERT'
  );

  select count(*) into v_operation_count
  from foundation.remediation_execution_operations
  where lifecycle='active';

  if not v_executor_exists
     or v_service_member
     or v_approver_member
     or v_service_can_issue
     or v_approver_can_issue
     or not v_executor_can_issue
     or v_service_direct_admission_insert
     or v_service_direct_event_insert
     or v_operation_count<>3 then
    v_state := 'fail';
  end if;

  return jsonb_build_object(
    'foundationRemediationExecutionAdmissionControlHealthResponse',
      'shine-foundation/remediation-execution-admission-control-health-response-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'executorRoleExists',v_executor_exists,
    'serviceRoleIsExecutorMember',v_service_member,
    'approverRoleIsExecutorMember',v_approver_member,
    'serviceRoleCanIssueAdmission',v_service_can_issue,
    'approverRoleCanIssueAdmission',v_approver_can_issue,
    'executorRoleCanIssueAdmission',v_executor_can_issue,
    'serviceRoleCanInsertAdmissionsDirectly',v_service_direct_admission_insert,
    'serviceRoleCanInsertAdmissionEventsDirectly',v_service_direct_event_insert,
    'activeExecutionOperationCount',v_operation_count,
    'executesAction',false
  );
end;
$layer40_health$;

revoke all on function foundation.get_remediation_execution_admission_control_health_v1()
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,foundation_remediation_executor;
grant execute on function foundation.get_remediation_execution_admission_control_health_v1()
  to foundation_runtime,service_role;
