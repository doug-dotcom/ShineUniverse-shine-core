-- Foundation Layer 39: scope-bound single-use remediation approval receipts.
-- Approval proves a separately-authorised action may be attempted. It never executes
-- the action and never expands the action authority defined by Layer 38.

do $layer39_roles$
begin
  if not exists (
    select 1 from pg_roles where rolname='foundation_remediation_approver'
  ) then
    create role foundation_remediation_approver nologin noinherit;
  end if;
end;
$layer39_roles$;

alter role foundation_remediation_approver nologin noinherit;
grant foundation_remediation_approver to postgres;
grant usage on schema foundation to foundation_remediation_approver;


create table foundation.remediation_approval_receipts (
  receipt_sequence bigint generated always as identity primary key,
  receipt_id uuid not null unique,
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  incident_event_id uuid not null
    references foundation.foundation_control_plane_incident_events(event_id),
  incident_key text not null
    check (incident_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  incident_state text not null
    check (incident_state in ('warning','critical')),
  severity text not null
    check (severity in ('warning','critical')),
  action_key text not null
    references foundation.control_plane_incident_response_actions(action_key),
  policy_version text not null,
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{32}$'),
  release_ref text not null
    check (release_ref ~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'),
  proposal_sha256 text not null
    check (proposal_sha256 ~ '^[a-f0-9]{64}$'),
  approved_by text not null
    check (approved_by ~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$'),
  approval_method text not null
    check (approval_method in ('explicit-human','external-governance')),
  approved_at timestamptz not null,
  expires_at timestamptz not null,
  receipt jsonb not null
    check (jsonb_typeof(receipt)='object'),
  receipt_sha256 text not null
    check (receipt_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default now(),
  check (expires_at>approved_at),
  check (expires_at<=approved_at+interval '15 minutes')
);

alter table foundation.remediation_approval_receipts enable row level security;

create policy foundation_runtime_remediation_approval_receipts_select
on foundation.remediation_approval_receipts
for select
to foundation_runtime
using (true);

revoke all on foundation.remediation_approval_receipts
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,service_role;
grant select on foundation.remediation_approval_receipts
  to foundation_runtime,service_role;

create index remediation_approval_receipts_incident_idx
  on foundation.remediation_approval_receipts(
    incident_event_id,approved_at desc,receipt_sequence desc
  );

create index remediation_approval_receipts_action_idx
  on foundation.remediation_approval_receipts(
    action_key,approved_at desc,receipt_sequence desc
  );

create trigger remediation_approval_receipts_append_only
before update or delete on foundation.remediation_approval_receipts
for each row execute function foundation.reject_append_only_mutation();


create table foundation.remediation_approval_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique,
  receipt_id uuid not null
    references foundation.remediation_approval_receipts(receipt_id),
  event_type text not null
    check (event_type in ('consumed','denied')),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  action_key text not null,
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
  )
);

alter table foundation.remediation_approval_events enable row level security;

create policy foundation_runtime_remediation_approval_events_select
on foundation.remediation_approval_events
for select
to foundation_runtime
using (true);

revoke all on foundation.remediation_approval_events
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver,service_role;
grant select on foundation.remediation_approval_events
  to foundation_runtime,service_role;

create index remediation_approval_events_receipt_idx
  on foundation.remediation_approval_events(
    receipt_id,occurred_at desc,event_sequence desc
  );

create trigger remediation_approval_events_append_only
before update or delete on foundation.remediation_approval_events
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_remediation_approval_status
with (security_invoker=true)
as
select
  r.receipt_sequence,
  r.receipt_id,
  r.environment,
  r.incident_event_id,
  r.incident_key,
  r.incident_state,
  r.severity,
  r.action_key,
  r.policy_version,
  r.evidence_fingerprint,
  r.release_ref,
  r.proposal_sha256,
  r.approved_by,
  r.approval_method,
  r.approved_at,
  r.expires_at,
  r.receipt,
  r.receipt_sha256,
  r.recorded_at,
  case
    when exists (
      select 1
      from foundation.remediation_approval_events e
      where e.receipt_id=r.receipt_id
        and e.event_type='consumed'
    ) then 'consumed'
    when r.expires_at<=now() then 'expired'
    else 'active'
  end as approval_status,
  (
    select e.occurred_at
    from foundation.remediation_approval_events e
    where e.receipt_id=r.receipt_id
      and e.event_type='consumed'
    order by e.occurred_at desc,e.event_sequence desc
    limit 1
  ) as consumed_at
from foundation.remediation_approval_receipts r;

revoke all on foundation.current_remediation_approval_status
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver;
grant select on foundation.current_remediation_approval_status
  to foundation_runtime,service_role;


create or replace function foundation.issue_remediation_approval_receipt_v1(
  p_receipt_id uuid,
  p_action_key text,
  p_incident_event_id uuid,
  p_proposal_sha256 text,
  p_approved_by text,
  p_approval_method text,
  p_approved_at timestamptz,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer39_issue$
declare
  v_incident foundation.foundation_control_plane_incident_events%rowtype;
  v_current foundation.foundation_control_plane_incident_events%rowtype;
  v_decision jsonb;
  v_release_ref text;
  v_receipt jsonb;
  v_receipt_sha256 text;
begin
  if p_receipt_id is null
     or p_incident_event_id is null
     or p_approved_at is null
     or p_expires_at is null then
    raise exception 'remediation-approval-required-fields-missing';
  end if;

  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'remediation-approval-action-invalid';
  end if;

  if p_proposal_sha256 is null
     or lower(p_proposal_sha256) !~ '^[a-f0-9]{64}$' then
    raise exception 'remediation-approval-proposal-hash-invalid';
  end if;

  if p_approved_by is null
     or p_approved_by !~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$' then
    raise exception 'remediation-approval-approver-invalid';
  end if;

  if p_approval_method not in ('explicit-human','external-governance') then
    raise exception 'remediation-approval-method-invalid';
  end if;

  if p_expires_at<=p_approved_at
     or p_expires_at>p_approved_at+interval '15 minutes' then
    raise exception 'remediation-approval-expiry-invalid';
  end if;

  if p_approved_at>now()+interval '5 minutes'
     or p_approved_at<now()-interval '1 day' then
    raise exception 'remediation-approval-approved-at-invalid';
  end if;

  select * into v_incident
  from foundation.foundation_control_plane_incident_events
  where event_id=p_incident_event_id;

  if v_incident.event_id is null then
    raise exception 'remediation-approval-incident-event-missing';
  end if;

  select * into v_current
  from foundation.current_foundation_control_plane_incident_state
  where incident_key=v_incident.incident_key;

  if v_current.event_id is distinct from v_incident.event_id
     or v_current.event_type not in ('opened','changed') then
    raise exception 'remediation-approval-incident-not-current';
  end if;

  if v_incident.environment<>'production'
     or v_incident.severity not in ('warning','critical') then
    raise exception 'remediation-approval-incident-not-approvable';
  end if;

  v_decision :=
    foundation.evaluate_control_plane_incident_response_v1(
      p_action_key,v_incident.environment
    );

  if v_decision->>'decision'<>'approval-required'
     or v_decision->>'requiredControl'<>'external-approval'
     or coalesce((v_decision->>'mutatesAuthoritativeTruth')::boolean,false)<>true then
    raise exception 'remediation-approval-action-not-approval-required';
  end if;

  v_release_ref := coalesce(
    v_incident.snapshot#>>'{binding,releaseRef}',
    v_incident.snapshot#>>'{registry,readinessReleaseRef}'
  );

  if v_release_ref is null
     or v_release_ref !~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$' then
    raise exception 'remediation-approval-release-scope-missing';
  end if;

  v_receipt := jsonb_build_object(
    'remediationApprovalReceipt',
      'shine-foundation/remediation-approval-receipt-v1',
    'schemaVersion','1.0.0',
    'receiptId',p_receipt_id,
    'environment',v_incident.environment,
    'incidentEventId',v_incident.event_id,
    'incidentKey',v_incident.incident_key,
    'incidentState',v_decision->>'incidentState',
    'severity',v_incident.severity,
    'actionKey',p_action_key,
    'policyVersion',v_decision->>'policyVersion',
    'evidenceFingerprint',v_incident.evidence_fingerprint,
    'releaseRef',v_release_ref,
    'proposalSha256',lower(p_proposal_sha256),
    'approvedBy',p_approved_by,
    'approvalMethod',p_approval_method,
    'approvedAt',p_approved_at,
    'expiresAt',p_expires_at,
    'singleUse',true,
    'executionAuthority',false,
    'executesAction',false
  );

  v_receipt_sha256 := encode(
    extensions.digest(
      convert_to(v_receipt::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.remediation_approval_receipts(
    receipt_id,environment,incident_event_id,incident_key,
    incident_state,severity,action_key,policy_version,
    evidence_fingerprint,release_ref,proposal_sha256,
    approved_by,approval_method,approved_at,expires_at,
    receipt,receipt_sha256
  )
  values (
    p_receipt_id,v_incident.environment,v_incident.event_id,
    v_incident.incident_key,v_decision->>'incidentState',
    v_incident.severity,p_action_key,v_decision->>'policyVersion',
    v_incident.evidence_fingerprint,v_release_ref,
    lower(p_proposal_sha256),p_approved_by,p_approval_method,
    p_approved_at,p_expires_at,v_receipt,v_receipt_sha256
  );

  return jsonb_build_object(
    'foundationRemediationApprovalIssueResponse',
      'shine-foundation/remediation-approval-issue-response-v1',
    'schemaVersion','1.0.0',
    'status','issued',
    'receiptId',p_receipt_id,
    'receipt',v_receipt,
    'receiptSha256',v_receipt_sha256,
    'approvalStatus','active',
    'executionAuthority',false,
    'executesAction',false
  );
end;
$layer39_issue$;

revoke all on function foundation.issue_remediation_approval_receipt_v1(
  uuid,text,uuid,text,text,text,timestamptz,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,service_role;
grant execute on function foundation.issue_remediation_approval_receipt_v1(
  uuid,text,uuid,text,text,text,timestamptz,timestamptz
) to foundation_remediation_approver;


create or replace function foundation.consume_remediation_approval_receipt_v1(
  p_event_id uuid,
  p_receipt_id uuid,
  p_action_key text,
  p_incident_event_id uuid,
  p_proposal_sha256 text,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer39_consume$
declare
  v_receipt foundation.remediation_approval_receipts%rowtype;
  v_current foundation.foundation_control_plane_incident_events%rowtype;
  v_decision jsonb;
  v_expected_hash text;
  v_reason text;
  v_already_consumed boolean := false;
begin
  if p_event_id is null
     or p_receipt_id is null
     or p_occurred_at is null then
    raise exception 'remediation-approval-consumption-fields-missing';
  end if;

  select * into v_receipt
  from foundation.remediation_approval_receipts
  where receipt_id=p_receipt_id
  for update;

  if v_receipt.receipt_id is null then
    return jsonb_build_object(
      'allowed',false,
      'approvalConsumed',false,
      'reasonCode','remediation-approval-receipt-not-found',
      'executeAction',false,
      'executionAuthority',false
    );
  end if;

  select exists (
    select 1
    from foundation.remediation_approval_events
    where receipt_id=v_receipt.receipt_id
      and event_type='consumed'
  ) into v_already_consumed;

  v_expected_hash := encode(
    extensions.digest(
      convert_to(v_receipt.receipt::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  v_reason := null;

  if v_already_consumed then
    v_reason := 'remediation-approval-already-consumed';
  elsif v_receipt.receipt_sha256 is distinct from v_expected_hash then
    v_reason := 'remediation-approval-integrity-failed';
  elsif v_receipt.expires_at<=p_occurred_at then
    v_reason := 'remediation-approval-expired';
  elsif v_receipt.action_key is distinct from p_action_key then
    v_reason := 'remediation-approval-action-mismatch';
  elsif v_receipt.incident_event_id is distinct from p_incident_event_id then
    v_reason := 'remediation-approval-incident-mismatch';
  elsif v_receipt.proposal_sha256 is distinct from lower(coalesce(p_proposal_sha256,'')) then
    v_reason := 'remediation-approval-proposal-mismatch';
  else
    select * into v_current
    from foundation.current_foundation_control_plane_incident_state
    where incident_key=v_receipt.incident_key;

    if v_current.event_id is distinct from v_receipt.incident_event_id
       or v_current.event_type not in ('opened','changed') then
      v_reason := 'remediation-approval-incident-no-longer-current';
    elsif v_current.evidence_fingerprint is distinct from
          v_receipt.evidence_fingerprint then
      v_reason := 'remediation-approval-evidence-mismatch';
    else
      v_decision :=
        foundation.evaluate_control_plane_incident_response_v1(
          v_receipt.action_key,v_receipt.environment
        );

      if v_decision->>'decision'<>'approval-required'
         or v_decision->>'requiredControl'<>'external-approval'
         or v_decision->>'policyVersion' is distinct from
            v_receipt.policy_version then
        v_reason := 'remediation-approval-policy-no-longer-valid';
      end if;
    end if;
  end if;

  if v_reason is not null then
    insert into foundation.remediation_approval_events(
      event_id,receipt_id,event_type,reason_code,action_key,
      incident_event_id,evidence_fingerprint,release_ref,
      proposal_sha256,occurred_at
    )
    values (
      p_event_id,v_receipt.receipt_id,'denied',v_reason,
      p_action_key,p_incident_event_id,
      v_current.evidence_fingerprint,
      coalesce(v_current.snapshot#>>'{binding,releaseRef}',
               v_current.snapshot#>>'{registry,readinessReleaseRef}'),
      lower(p_proposal_sha256),
      p_occurred_at
    );

    return jsonb_build_object(
      'foundationRemediationApprovalConsumeResponse',
        'shine-foundation/remediation-approval-consume-response-v1',
      'schemaVersion','1.0.0',
      'allowed',false,
      'approvalConsumed',false,
      'receiptId',v_receipt.receipt_id,
      'reasonCode',v_reason,
      'executeAction',false,
      'executionAuthority',false
    );
  end if;

  insert into foundation.remediation_approval_events(
    event_id,receipt_id,event_type,reason_code,action_key,
    incident_event_id,evidence_fingerprint,release_ref,
    proposal_sha256,occurred_at
  )
  values (
    p_event_id,v_receipt.receipt_id,'consumed',
    'remediation-approval-consumed',
    v_receipt.action_key,v_receipt.incident_event_id,
    v_receipt.evidence_fingerprint,v_receipt.release_ref,
    v_receipt.proposal_sha256,p_occurred_at
  );

  return jsonb_build_object(
    'foundationRemediationApprovalConsumeResponse',
      'shine-foundation/remediation-approval-consume-response-v1',
    'schemaVersion','1.0.0',
    'allowed',true,
    'approvalConsumed',true,
    'receiptId',v_receipt.receipt_id,
    'actionKey',v_receipt.action_key,
    'incidentEventId',v_receipt.incident_event_id,
    'evidenceFingerprint',v_receipt.evidence_fingerprint,
    'releaseRef',v_receipt.release_ref,
    'proposalSha256',v_receipt.proposal_sha256,
    'approvedBy',v_receipt.approved_by,
    'approvalMethod',v_receipt.approval_method,
    'reasonCode','remediation-approval-consumed',
    'executeAction',false,
    'executionAuthority',false
  );
end;
$layer39_consume$;

revoke all on function foundation.consume_remediation_approval_receipt_v1(
  uuid,uuid,text,uuid,text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       foundation_remediation_approver;
grant execute on function foundation.consume_remediation_approval_receipt_v1(
  uuid,uuid,text,uuid,text,timestamptz
) to service_role;


create or replace function foundation.get_remediation_approval_status_v1(
  p_receipt_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer39_status$
declare
  v_receipt foundation.remediation_approval_receipts%rowtype;
  v_current foundation.foundation_control_plane_incident_events%rowtype;
  v_consumed_at timestamptz;
  v_integrity_ok boolean := false;
  v_status text;
  v_current_incident boolean := false;
begin
  select * into v_receipt
  from foundation.remediation_approval_receipts
  where receipt_id=p_receipt_id;

  if v_receipt.receipt_id is null then
    return jsonb_build_object(
      'foundationRemediationApprovalStatusResponse',
        'shine-foundation/remediation-approval-status-response-v1',
      'schemaVersion','1.0.0',
      'receiptId',p_receipt_id,
      'status','missing'
    );
  end if;

  select max(occurred_at) into v_consumed_at
  from foundation.remediation_approval_events
  where receipt_id=v_receipt.receipt_id
    and event_type='consumed';

  v_integrity_ok :=
    v_receipt.receipt_sha256 = encode(
      extensions.digest(
        convert_to(v_receipt.receipt::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );

  select * into v_current
  from foundation.current_foundation_control_plane_incident_state
  where incident_key=v_receipt.incident_key;

  v_current_incident :=
    v_current.event_id is not distinct from v_receipt.incident_event_id
    and v_current.event_type in ('opened','changed');

  v_status := case
    when not v_integrity_ok then 'invalid'
    when v_consumed_at is not null then 'consumed'
    when v_receipt.expires_at<=now() then 'expired'
    when not v_current_incident then 'stale'
    else 'active'
  end;

  return jsonb_build_object(
    'foundationRemediationApprovalStatusResponse',
      'shine-foundation/remediation-approval-status-response-v1',
    'schemaVersion','1.0.0',
    'receiptId',v_receipt.receipt_id,
    'status',v_status,
    'environment',v_receipt.environment,
    'incidentEventId',v_receipt.incident_event_id,
    'incidentState',v_receipt.incident_state,
    'severity',v_receipt.severity,
    'actionKey',v_receipt.action_key,
    'policyVersion',v_receipt.policy_version,
    'evidenceFingerprint',v_receipt.evidence_fingerprint,
    'releaseRef',v_receipt.release_ref,
    'proposalSha256',v_receipt.proposal_sha256,
    'approvedBy',v_receipt.approved_by,
    'approvalMethod',v_receipt.approval_method,
    'approvedAt',v_receipt.approved_at,
    'expiresAt',v_receipt.expires_at,
    'consumedAt',v_consumed_at,
    'integrityVerified',v_integrity_ok,
    'incidentStillCurrent',v_current_incident,
    'singleUse',true,
    'executionAuthority',false,
    'executesAction',false
  );
end;
$layer39_status$;

revoke all on function foundation.get_remediation_approval_status_v1(uuid)
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver;
grant execute on function foundation.get_remediation_approval_status_v1(uuid)
  to foundation_runtime,service_role;


create or replace function foundation.get_remediation_approval_control_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer39_health$
declare
  v_approver_role_exists boolean := false;
  v_service_can_issue boolean := false;
  v_runtime_can_issue boolean := false;
  v_service_member_approver boolean := false;
  v_service_can_consume boolean := false;
  v_runtime_can_consume boolean := false;
  v_service_direct_receipt_insert boolean := false;
  v_service_direct_event_insert boolean := false;
  v_state text := 'pass';
begin
  select exists(
    select 1 from pg_roles
    where rolname='foundation_remediation_approver'
      and not rolcanlogin
  ) into v_approver_role_exists;

  v_service_can_issue := has_function_privilege(
    'service_role',
    'foundation.issue_remediation_approval_receipt_v1(uuid,text,uuid,text,text,text,timestamptz,timestamptz)',
    'EXECUTE'
  );

  v_runtime_can_issue := has_function_privilege(
    'foundation_runtime',
    'foundation.issue_remediation_approval_receipt_v1(uuid,text,uuid,text,text,text,timestamptz,timestamptz)',
    'EXECUTE'
  );

  v_service_member_approver := pg_has_role(
    'service_role','foundation_remediation_approver','MEMBER'
  );

  v_service_can_consume := has_function_privilege(
    'service_role',
    'foundation.consume_remediation_approval_receipt_v1(uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  );

  v_runtime_can_consume := has_function_privilege(
    'foundation_runtime',
    'foundation.consume_remediation_approval_receipt_v1(uuid,uuid,text,uuid,text,timestamptz)',
    'EXECUTE'
  );

  v_service_direct_receipt_insert := has_table_privilege(
    'service_role',
    'foundation.remediation_approval_receipts',
    'INSERT'
  );

  v_service_direct_event_insert := has_table_privilege(
    'service_role',
    'foundation.remediation_approval_events',
    'INSERT'
  );

  if not v_approver_role_exists
     or v_service_can_issue
     or v_runtime_can_issue
     or v_service_member_approver
     or not v_service_can_consume
     or v_runtime_can_consume
     or v_service_direct_receipt_insert
     or v_service_direct_event_insert then
    v_state := 'fail';
  end if;

  return jsonb_build_object(
    'foundationRemediationApprovalControlHealthResponse',
      'shine-foundation/remediation-approval-control-health-response-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'approverRoleExists',v_approver_role_exists,
    'serviceRoleCanIssue',v_service_can_issue,
    'foundationRuntimeCanIssue',v_runtime_can_issue,
    'serviceRoleIsApproverMember',v_service_member_approver,
    'serviceRoleCanConsume',v_service_can_consume,
    'foundationRuntimeCanConsume',v_runtime_can_consume,
    'serviceRoleCanInsertReceiptsDirectly',v_service_direct_receipt_insert,
    'serviceRoleCanInsertEventsDirectly',v_service_direct_event_insert,
    'executionAuthority',false
  );
end;
$layer39_health$;

revoke all on function foundation.get_remediation_approval_control_health_v1()
  from public,anon,authenticated,foundation_gateway,
       foundation_remediation_approver;
grant execute on function foundation.get_remediation_approval_control_health_v1()
  to foundation_runtime,service_role;
