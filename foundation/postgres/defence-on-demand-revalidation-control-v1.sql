-- Shine Defence on-demand revalidation control v1.
-- Append-only request -> approval -> execution-admission -> ordered evidence.
-- This database layer never performs the Railway mutation itself.

do $roles$
begin
  if not exists (
    select 1 from pg_catalog.pg_roles
    where rolname='shine_defence_on_demand_approver'
  ) then
    create role shine_defence_on_demand_approver nologin noinherit;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_roles
    where rolname='shine_defence_on_demand_executor'
  ) then
    create role shine_defence_on_demand_executor nologin noinherit;
  end if;
end;
$roles$;

alter role shine_defence_on_demand_approver nologin noinherit;
alter role shine_defence_on_demand_executor nologin noinherit;
grant shine_defence_on_demand_approver to postgres;
grant shine_defence_on_demand_executor to postgres;
grant usage on schema foundation
  to shine_defence_on_demand_approver,shine_defence_on_demand_executor;


create table foundation.defence_on_demand_revalidation_requests (
  request_sequence bigint generated always as identity primary key,
  request_id uuid not null unique,
  target_id text not null references foundation.defence_estate_targets(target_id),
  requested_by text not null
    check (requested_by ~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$'),
  requested_at timestamptz not null,
  expires_at timestamptz not null,
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  scope_snapshot jsonb not null
    check (jsonb_typeof(scope_snapshot)='object'),
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  request jsonb not null
    check (jsonb_typeof(request)='object'),
  request_sha256 text not null
    check (request_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default now(),
  check (expires_at>requested_at),
  check (expires_at<=requested_at+interval '60 minutes')
);

alter table foundation.defence_on_demand_revalidation_requests
  enable row level security;

create policy shine_defence_runtime_revalidation_requests_select
on foundation.defence_on_demand_revalidation_requests
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_revalidation_requests
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor,
       service_role;
grant select on foundation.defence_on_demand_revalidation_requests
  to foundation_runtime,shine_defence_runtime,service_role;

create index defence_on_demand_revalidation_requests_target_idx
  on foundation.defence_on_demand_revalidation_requests(
    target_id,requested_at desc,request_sequence desc
  );

create trigger defence_on_demand_revalidation_requests_append_only
before update or delete
on foundation.defence_on_demand_revalidation_requests
for each row execute function foundation.reject_append_only_mutation();


create table foundation.defence_on_demand_revalidation_approvals (
  approval_sequence bigint generated always as identity primary key,
  approval_id uuid not null unique,
  request_id uuid not null unique
    references foundation.defence_on_demand_revalidation_requests(request_id),
  request_sha256 text not null
    check (request_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  approved_by text not null
    check (approved_by ~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$'),
  approval_method text not null
    check (approval_method in ('explicit-human','external-governance')),
  approved_at timestamptz not null,
  expires_at timestamptz not null,
  approval jsonb not null
    check (jsonb_typeof(approval)='object'),
  approval_sha256 text not null
    check (approval_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default now(),
  check (expires_at>approved_at),
  check (expires_at<=approved_at+interval '15 minutes')
);

alter table foundation.defence_on_demand_revalidation_approvals
  enable row level security;

create policy shine_defence_runtime_revalidation_approvals_select
on foundation.defence_on_demand_revalidation_approvals
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_revalidation_approvals
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor,
       service_role;
grant select on foundation.defence_on_demand_revalidation_approvals
  to foundation_runtime,shine_defence_runtime,service_role;

create trigger defence_on_demand_revalidation_approvals_append_only
before update or delete
on foundation.defence_on_demand_revalidation_approvals
for each row execute function foundation.reject_append_only_mutation();


create table foundation.defence_on_demand_revalidation_admissions (
  admission_sequence bigint generated always as identity primary key,
  execution_id uuid not null unique,
  request_id uuid not null unique
    references foundation.defence_on_demand_revalidation_requests(request_id),
  approval_id uuid not null unique
    references foundation.defence_on_demand_revalidation_approvals(approval_id),
  admitted_at timestamptz not null,
  expires_at timestamptz not null,
  evidence_fingerprint text not null
    check (evidence_fingerprint ~ '^[a-f0-9]{64}$'),
  execution_envelope jsonb not null
    check (jsonb_typeof(execution_envelope)='object'),
  envelope_sha256 text not null
    check (envelope_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default now(),
  check (expires_at>admitted_at),
  check (expires_at<=admitted_at+interval '10 minutes')
);

alter table foundation.defence_on_demand_revalidation_admissions
  enable row level security;

create policy shine_defence_runtime_revalidation_admissions_select
on foundation.defence_on_demand_revalidation_admissions
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_revalidation_admissions
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor,
       service_role;
grant select on foundation.defence_on_demand_revalidation_admissions
  to foundation_runtime,shine_defence_runtime,service_role;

create trigger defence_on_demand_revalidation_admissions_append_only
before update or delete
on foundation.defence_on_demand_revalidation_admissions
for each row execute function foundation.reject_append_only_mutation();


create table foundation.defence_on_demand_revalidation_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique,
  execution_id uuid not null
    references foundation.defence_on_demand_revalidation_admissions(execution_id),
  step_type text not null
    check (step_type in (
      'redeploy_started',
      'deployment_verified',
      'health_probe_queued',
      'health_verified',
      'attestation_verified',
      'release_reconciled',
      'completed',
      'failed'
    )),
  evidence jsonb not null
    check (jsonb_typeof(evidence)='object'),
  occurred_at timestamptz not null,
  evidence_sha256 text not null
    check (evidence_sha256 ~ '^[a-f0-9]{64}$'),
  recorded_at timestamptz not null default now(),
  unique(execution_id,step_type)
);

alter table foundation.defence_on_demand_revalidation_events
  enable row level security;

create policy shine_defence_runtime_revalidation_events_select
on foundation.defence_on_demand_revalidation_events
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_revalidation_events
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor,
       service_role;
grant select on foundation.defence_on_demand_revalidation_events
  to foundation_runtime,shine_defence_runtime,service_role;

create index defence_on_demand_revalidation_events_execution_idx
  on foundation.defence_on_demand_revalidation_events(
    execution_id,event_sequence
  );

create trigger defence_on_demand_revalidation_events_append_only
before update or delete
on foundation.defence_on_demand_revalidation_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.get_defence_on_demand_revalidation_snapshot_v1(
  p_target_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $snapshot$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_posture jsonb;
  v_authority record;
begin
  if p_target_id is null
     or length(btrim(p_target_id))=0
     or p_as_of is null then
    raise exception 'invalid-on-demand-revalidation-snapshot-input'
      using errcode='22023';
  end if;

  select * into v_target
  from foundation.defence_estate_targets
  where target_id=p_target_id
    and provider='railway'
    and lifecycle='active'
    and required_for_estate;

  if v_target.target_id is null then
    return jsonb_build_object(
      'eligible',false,
      'targetId',p_target_id,
      'reasonCode','target-not-eligible'
    );
  end if;

  v_posture :=
    foundation.get_defence_on_demand_sleep_posture_v1(
      p_target_id,p_as_of
    );

  select
    lower(a.authority_sha) as authority_sha,
    a.authority_ref
  into v_authority
  from foundation.current_defence_attestation_authority a;

  return jsonb_build_object(
    'eligible',
      v_posture->>'state'='revalidation_required',
    'targetId',p_target_id,
    'postureState',v_posture->>'state',
    'postureReasonCode',v_posture->>'reasonCode',
    'postureNextAction',v_posture->>'nextAction',
    'railway',jsonb_build_object(
      'projectId',v_target.provider_project_ref,
      'environmentId',v_target.environment_ref,
      'serviceId',v_target.service_ref
    ),
    'source',jsonb_build_object(
      'repository',v_target.metadata->>'sourceRepository',
      'branch',v_target.metadata->>'sourceBranch',
      'headSha',v_posture#>>'{evidence,sourceHeadSha}'
    ),
    'serving',jsonb_build_object(
      'deploymentId',v_posture#>>'{serving,deploymentId}',
      'commitSha',v_posture#>>'{serving,commitSha}'
    ),
    'canonical',jsonb_build_object(
      'deploymentId',v_posture#>>'{canonical,deploymentId}',
      'commitSha',v_posture#>>'{canonical,commitSha}'
    ),
    'authority',jsonb_build_object(
      'sha',v_authority.authority_sha,
      'ref',v_authority.authority_ref
    ),
    'releaseAdmission',v_posture->'releaseAdmission',
    'evidence',jsonb_build_object(
      'sourceAhead',
        coalesce((v_posture#>>'{evidence,sourceAhead}')::boolean,false),
      'sourceAuthorityCurrent',
        coalesce((v_posture#>>'{evidence,sourceAuthorityCurrent}')::boolean,false),
      'sourceIdentityOk',
        coalesce((v_posture#>>'{evidence,sourceIdentityOk}')::boolean,false),
      'latestTransitionState',
        v_posture#>>'{evidence,latestTransitionState}',
      'onDemandCanonicalUnchanged',
        coalesce((v_posture#>>'{evidence,onDemandCanonicalUnchanged}')::boolean,false)
    )
  );
end;
$snapshot$;

revoke all on function foundation.get_defence_on_demand_revalidation_snapshot_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_on_demand_revalidation_snapshot_v1(
  text,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;


create or replace function foundation.get_defence_on_demand_revalidation_fingerprint_v1(
  p_snapshot jsonb
)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $fingerprint$
begin
  if p_snapshot is null
     or jsonb_typeof(p_snapshot)<>'object'
     or pg_column_size(p_snapshot)>32768 then
    raise exception 'invalid-on-demand-revalidation-snapshot';
  end if;

  return encode(
    extensions.digest(
      convert_to(p_snapshot::text,'UTF8'),'sha256'
    ),
    'hex'
  );
end;
$fingerprint$;

revoke all on function foundation.get_defence_on_demand_revalidation_fingerprint_v1(jsonb)
  from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_on_demand_revalidation_fingerprint_v1(jsonb)
  to foundation_runtime,shine_defence_runtime,service_role,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;


create or replace function foundation.request_defence_on_demand_revalidation_v1(
  p_request_id uuid,
  p_target_id text,
  p_requested_by text,
  p_requested_at timestamptz default now(),
  p_expires_at timestamptz default now()+interval '30 minutes'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $request$
declare
  v_snapshot jsonb;
  v_fingerprint text;
  v_request jsonb;
  v_request_hash text;
begin
  if p_request_id is null
     or p_target_id is null
     or p_requested_at is null
     or p_expires_at is null then
    raise exception 'on-demand-revalidation-request-fields-missing';
  end if;

  if p_requested_by is null
     or p_requested_by !~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$' then
    raise exception 'on-demand-revalidation-requestor-invalid';
  end if;

  if p_expires_at<=p_requested_at
     or p_expires_at>p_requested_at+interval '60 minutes'
     or p_requested_at<now()-interval '5 minutes'
     or p_requested_at>now()+interval '5 minutes' then
    raise exception 'on-demand-revalidation-request-window-invalid';
  end if;

  if exists (
    select 1
    from foundation.defence_on_demand_revalidation_requests r
    where r.target_id=p_target_id
      and r.expires_at>p_requested_at
      and not exists (
        select 1
        from foundation.defence_on_demand_revalidation_events e
        join foundation.defence_on_demand_revalidation_admissions a
          on a.execution_id=e.execution_id
        where a.request_id=r.request_id
          and e.step_type in ('completed','failed')
      )
  ) then
    raise exception 'on-demand-revalidation-active-request-exists';
  end if;

  v_snapshot :=
    foundation.get_defence_on_demand_revalidation_snapshot_v1(
      p_target_id,p_requested_at
    );

  if coalesce((v_snapshot->>'eligible')::boolean,false)<>true
     or v_snapshot->>'postureState'<>'revalidation_required'
     or v_snapshot->>'postureNextAction'<>'wake_and_revalidate_on_demand_target' then
    raise exception 'on-demand-revalidation-target-not-requestable';
  end if;

  if v_snapshot#>>'{railway,projectId}' is null
     or v_snapshot#>>'{railway,environmentId}' is null
     or v_snapshot#>>'{railway,serviceId}' is null
     or v_snapshot#>>'{source,headSha}' !~ '^[a-f0-9]{40}$'
     or v_snapshot#>>'{authority,sha}' !~ '^[a-f0-9]{40}$' then
    raise exception 'on-demand-revalidation-scope-incomplete';
  end if;

  v_fingerprint :=
    foundation.get_defence_on_demand_revalidation_fingerprint_v1(
      v_snapshot
    );

  v_request := jsonb_build_object(
    'defenceOnDemandRevalidationRequest',
      'shine-defence/on-demand-revalidation-request-v1',
    'schemaVersion','1.0.0',
    'requestId',p_request_id,
    'targetId',p_target_id,
    'requestedBy',p_requested_by,
    'requestedAt',p_requested_at,
    'expiresAt',p_expires_at,
    'reasonCode',v_snapshot->>'postureReasonCode',
    'scopeSnapshot',v_snapshot,
    'evidenceFingerprint',v_fingerprint,
    'requiresExplicitApproval',true,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesExternalMutation',false
  );

  v_request_hash := encode(
    extensions.digest(
      convert_to(v_request::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  insert into foundation.defence_on_demand_revalidation_requests(
    request_id,target_id,requested_by,requested_at,expires_at,
    reason_code,scope_snapshot,evidence_fingerprint,
    request,request_sha256
  ) values (
    p_request_id,p_target_id,p_requested_by,p_requested_at,p_expires_at,
    v_snapshot->>'postureReasonCode',v_snapshot,v_fingerprint,
    v_request,v_request_hash
  );

  return jsonb_build_object(
    'status','requested',
    'requestId',p_request_id,
    'targetId',p_target_id,
    'evidenceFingerprint',v_fingerprint,
    'requestSha256',v_request_hash,
    'nextAction','approve_on_demand_revalidation_request',
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'executesExternalMutation',false
  );
end;
$request$;

revoke all on function foundation.request_defence_on_demand_revalidation_v1(
  uuid,text,text,timestamptz,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.request_defence_on_demand_revalidation_v1(
  uuid,text,text,timestamptz,timestamptz
) to service_role,shine_defence_runtime;


create or replace function foundation.approve_defence_on_demand_revalidation_v1(
  p_approval_id uuid,
  p_request_id uuid,
  p_approved_by text,
  p_approval_method text,
  p_approved_at timestamptz,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $approve$
declare
  v_request foundation.defence_on_demand_revalidation_requests%rowtype;
  v_snapshot jsonb;
  v_fingerprint text;
  v_request_hash text;
  v_approval jsonb;
  v_approval_hash text;
begin
  if p_approval_id is null
     or p_request_id is null
     or p_approved_at is null
     or p_expires_at is null then
    raise exception 'on-demand-revalidation-approval-fields-missing';
  end if;

  if p_approved_by is null
     or p_approved_by !~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$'
     or p_approval_method not in ('explicit-human','external-governance') then
    raise exception 'on-demand-revalidation-approver-invalid';
  end if;

  if p_expires_at<=p_approved_at
     or p_expires_at>p_approved_at+interval '15 minutes'
     or p_approved_at<now()-interval '5 minutes'
     or p_approved_at>now()+interval '5 minutes' then
    raise exception 'on-demand-revalidation-approval-window-invalid';
  end if;

  select * into v_request
  from foundation.defence_on_demand_revalidation_requests
  where request_id=p_request_id
  for update;

  if v_request.request_id is null then
    raise exception 'on-demand-revalidation-request-missing';
  end if;

  if v_request.expires_at<=p_approved_at then
    raise exception 'on-demand-revalidation-request-expired';
  end if;

  v_request_hash := encode(
    extensions.digest(
      convert_to(v_request.request::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  if v_request_hash is distinct from v_request.request_sha256 then
    raise exception 'on-demand-revalidation-request-integrity-failed';
  end if;

  v_snapshot :=
    foundation.get_defence_on_demand_revalidation_snapshot_v1(
      v_request.target_id,p_approved_at
    );
  v_fingerprint :=
    foundation.get_defence_on_demand_revalidation_fingerprint_v1(
      v_snapshot
    );

  if v_fingerprint is distinct from v_request.evidence_fingerprint then
    raise exception 'on-demand-revalidation-evidence-changed-before-approval';
  end if;

  v_approval := jsonb_build_object(
    'defenceOnDemandRevalidationApproval',
      'shine-defence/on-demand-revalidation-approval-v1',
    'schemaVersion','1.0.0',
    'approvalId',p_approval_id,
    'requestId',v_request.request_id,
    'targetId',v_request.target_id,
    'requestSha256',v_request.request_sha256,
    'evidenceFingerprint',v_request.evidence_fingerprint,
    'approvedBy',p_approved_by,
    'approvalMethod',p_approval_method,
    'approvedAt',p_approved_at,
    'expiresAt',p_expires_at,
    'singleUse',true,
    'mayIssueExecutionAdmission',true,
    'executionAuthorityGranted',false,
    'executesExternalMutation',false
  );

  v_approval_hash := encode(
    extensions.digest(
      convert_to(v_approval::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  insert into foundation.defence_on_demand_revalidation_approvals(
    approval_id,request_id,request_sha256,evidence_fingerprint,
    approved_by,approval_method,approved_at,expires_at,
    approval,approval_sha256
  ) values (
    p_approval_id,v_request.request_id,v_request.request_sha256,
    v_request.evidence_fingerprint,p_approved_by,p_approval_method,
    p_approved_at,p_expires_at,v_approval,v_approval_hash
  );

  return jsonb_build_object(
    'status','approved',
    'approvalId',p_approval_id,
    'requestId',v_request.request_id,
    'targetId',v_request.target_id,
    'approvalSha256',v_approval_hash,
    'nextAction','admit_on_demand_revalidation_execution',
    'executionAuthorityGranted',false,
    'executesExternalMutation',false
  );
end;
$approve$;

revoke all on function foundation.approve_defence_on_demand_revalidation_v1(
  uuid,uuid,text,text,timestamptz,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       service_role,shine_defence_runtime,shine_defence_on_demand_executor;
grant execute on function foundation.approve_defence_on_demand_revalidation_v1(
  uuid,uuid,text,text,timestamptz,timestamptz
) to shine_defence_on_demand_approver;


create or replace function foundation.admit_defence_on_demand_revalidation_execution_v1(
  p_execution_id uuid,
  p_approval_id uuid,
  p_admitted_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $admit$
declare
  v_approval foundation.defence_on_demand_revalidation_approvals%rowtype;
  v_request foundation.defence_on_demand_revalidation_requests%rowtype;
  v_snapshot jsonb;
  v_fingerprint text;
  v_approval_hash text;
  v_envelope jsonb;
  v_envelope_hash text;
  v_expires_at timestamptz;
begin
  if p_execution_id is null
     or p_approval_id is null
     or p_admitted_at is null then
    raise exception 'on-demand-revalidation-admission-fields-missing';
  end if;

  if p_admitted_at<now()-interval '5 minutes'
     or p_admitted_at>now()+interval '5 minutes' then
    raise exception 'on-demand-revalidation-admission-time-invalid';
  end if;

  select * into v_approval
  from foundation.defence_on_demand_revalidation_approvals
  where approval_id=p_approval_id
  for update;

  if v_approval.approval_id is null then
    raise exception 'on-demand-revalidation-approval-missing';
  end if;

  if v_approval.expires_at<=p_admitted_at
     or v_approval.approved_at>p_admitted_at then
    raise exception 'on-demand-revalidation-approval-not-active';
  end if;

  v_approval_hash := encode(
    extensions.digest(
      convert_to(v_approval.approval::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  if v_approval_hash is distinct from v_approval.approval_sha256 then
    raise exception 'on-demand-revalidation-approval-integrity-failed';
  end if;

  select * into v_request
  from foundation.defence_on_demand_revalidation_requests
  where request_id=v_approval.request_id;

  if v_request.request_id is null
     or v_request.expires_at<=p_admitted_at
     or v_request.request_sha256 is distinct from v_approval.request_sha256
     or v_request.evidence_fingerprint is distinct from
        v_approval.evidence_fingerprint then
    raise exception 'on-demand-revalidation-approval-request-scope-invalid';
  end if;

  v_snapshot :=
    foundation.get_defence_on_demand_revalidation_snapshot_v1(
      v_request.target_id,p_admitted_at
    );
  v_fingerprint :=
    foundation.get_defence_on_demand_revalidation_fingerprint_v1(
      v_snapshot
    );

  if v_fingerprint is distinct from v_request.evidence_fingerprint
     or coalesce((v_snapshot->>'eligible')::boolean,false)<>true
     or v_snapshot->>'postureState'<>'revalidation_required'
     or v_snapshot->>'postureNextAction'<>'wake_and_revalidate_on_demand_target' then
    raise exception 'on-demand-revalidation-live-scope-changed';
  end if;

  if exists (
    select 1
    from foundation.defence_on_demand_revalidation_admissions
    where approval_id=v_approval.approval_id
       or request_id=v_request.request_id
  ) then
    raise exception 'on-demand-revalidation-approval-already-consumed';
  end if;

  v_expires_at := least(
    v_approval.expires_at,
    p_admitted_at+interval '10 minutes'
  );

  v_envelope := jsonb_build_object(
    'defenceOnDemandRevalidationExecutionAdmission',
      'shine-defence/on-demand-revalidation-execution-admission-v1',
    'schemaVersion','1.0.0',
    'executionId',p_execution_id,
    'requestId',v_request.request_id,
    'approvalId',v_approval.approval_id,
    'targetId',v_request.target_id,
    'admittedAt',p_admitted_at,
    'expiresAt',v_expires_at,
    'evidenceFingerprint',v_request.evidence_fingerprint,
    'railway',v_snapshot->'railway',
    'source',v_snapshot->'source',
    'servingBefore',v_snapshot->'serving',
    'canonicalBefore',v_snapshot->'canonical',
    'authority',v_snapshot->'authority',
    'requiredSequence',jsonb_build_array(
      'redeploy_current_source',
      'verify_railway_deployment_success',
      'verify_deployed_commit',
      'enqueue_on_demand_health_probe',
      'verify_health_contract',
      'refresh_defence_attestations',
      'reconcile_release_admission'
    ),
    'constraints',jsonb_build_object(
      'expectedSourceHeadSha',v_snapshot#>>'{source,headSha}',
      'mustVerifyDeployedCommit',true,
      'mustVerifyHealthContract',true,
      'mustVerifyAttestationAuthority',true,
      'mustReconcileReleaseAdmission',true,
      'mayRollback',false,
      'mayChangeServiceConfiguration',false,
      'mayChangeTargetScope',false
    ),
    'singleUse',true,
    'executionAuthorityGranted',true,
    'executesExternalMutation',false
  );

  v_envelope_hash := encode(
    extensions.digest(
      convert_to(v_envelope::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  insert into foundation.defence_on_demand_revalidation_admissions(
    execution_id,request_id,approval_id,admitted_at,expires_at,
    evidence_fingerprint,execution_envelope,envelope_sha256
  ) values (
    p_execution_id,v_request.request_id,v_approval.approval_id,
    p_admitted_at,v_expires_at,v_request.evidence_fingerprint,
    v_envelope,v_envelope_hash
  );

  return jsonb_build_object(
    'status','admitted',
    'executionId',p_execution_id,
    'requestId',v_request.request_id,
    'approvalId',v_approval.approval_id,
    'executionEnvelope',v_envelope,
    'envelopeSha256',v_envelope_hash,
    'nextAction','redeploy_current_source',
    'executionAuthorityGranted',true,
    'executesExternalMutation',false
  );
end;
$admit$;

revoke all on function foundation.admit_defence_on_demand_revalidation_execution_v1(
  uuid,uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       service_role,shine_defence_runtime,shine_defence_on_demand_approver;
grant execute on function foundation.admit_defence_on_demand_revalidation_execution_v1(
  uuid,uuid,timestamptz
) to shine_defence_on_demand_executor;


create or replace function foundation.record_defence_on_demand_revalidation_step_v1(
  p_event_id uuid,
  p_execution_id uuid,
  p_step_type text,
  p_evidence jsonb,
  p_occurred_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $record_step$
declare
  v_admission foundation.defence_on_demand_revalidation_admissions%rowtype;
  v_envelope_hash text;
  v_evidence_hash text;
  v_expected_step text;
  v_expected_source_sha text;
  v_step_order text[] := array[
    'redeploy_started',
    'deployment_verified',
    'health_probe_queued',
    'health_verified',
    'attestation_verified',
    'release_reconciled',
    'completed'
  ];
  v_completed integer := 0;
begin
  if p_event_id is null
     or p_execution_id is null
     or p_occurred_at is null
     or p_step_type is null
     or p_evidence is null
     or jsonb_typeof(p_evidence)<>'object'
     or pg_column_size(p_evidence)>32768 then
    raise exception 'on-demand-revalidation-step-fields-invalid';
  end if;

  if p_step_type not in (
    'redeploy_started','deployment_verified','health_probe_queued',
    'health_verified','attestation_verified','release_reconciled',
    'completed','failed'
  ) then
    raise exception 'on-demand-revalidation-step-invalid';
  end if;

  select * into v_admission
  from foundation.defence_on_demand_revalidation_admissions
  where execution_id=p_execution_id
  for update;

  if v_admission.execution_id is null then
    raise exception 'on-demand-revalidation-execution-missing';
  end if;

  v_envelope_hash := encode(
    extensions.digest(
      convert_to(v_admission.execution_envelope::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  if v_envelope_hash is distinct from v_admission.envelope_sha256 then
    raise exception 'on-demand-revalidation-execution-integrity-failed';
  end if;

  if p_occurred_at<v_admission.admitted_at
     or p_occurred_at>v_admission.expires_at+interval '30 minutes' then
    raise exception 'on-demand-revalidation-step-time-invalid';
  end if;

  if exists (
    select 1
    from foundation.defence_on_demand_revalidation_events
    where execution_id=p_execution_id
      and step_type in ('completed','failed')
  ) then
    raise exception 'on-demand-revalidation-execution-terminal';
  end if;

  select count(*)::integer into v_completed
  from foundation.defence_on_demand_revalidation_events
  where execution_id=p_execution_id
    and step_type=any(v_step_order);

  if p_step_type<>'failed' then
    v_expected_step := v_step_order[v_completed+1];
    if v_expected_step is distinct from p_step_type then
      raise exception 'on-demand-revalidation-step-out-of-order';
    end if;
  end if;

  v_expected_source_sha :=
    v_admission.execution_envelope#>>'{constraints,expectedSourceHeadSha}';

  if p_step_type='redeploy_started' then
    if p_evidence->>'projectId' is distinct from
         v_admission.execution_envelope#>>'{railway,projectId}'
       or p_evidence->>'environmentId' is distinct from
         v_admission.execution_envelope#>>'{railway,environmentId}'
       or p_evidence->>'serviceId' is distinct from
         v_admission.execution_envelope#>>'{railway,serviceId}'
       or p_evidence->>'expectedSourceHeadSha' is distinct from
         v_expected_source_sha then
      raise exception 'on-demand-revalidation-redeploy-evidence-scope-mismatch';
    end if;
  elsif p_step_type='deployment_verified' then
    if p_evidence->>'status'<>'SUCCESS'
       or p_evidence->>'deployedCommitSha' is distinct from
          v_expected_source_sha
       or coalesce(p_evidence->>'deploymentId','')='' then
      raise exception 'on-demand-revalidation-deployment-verification-failed';
    end if;
  elsif p_step_type='health_probe_queued' then
    if p_evidence->>'targetId' is distinct from
         v_admission.execution_envelope->>'targetId'
       or coalesce(p_evidence->>'probeRequestId','')='' then
      raise exception 'on-demand-revalidation-probe-queue-evidence-invalid';
    end if;
  elsif p_step_type='health_verified' then
    if p_evidence->>'targetId' is distinct from
         v_admission.execution_envelope->>'targetId'
       or coalesce((p_evidence->>'contractOk')::boolean,false)<>true then
      raise exception 'on-demand-revalidation-health-verification-failed';
    end if;
  elsif p_step_type='attestation_verified' then
    if p_evidence->>'authoritySha' is distinct from
         v_admission.execution_envelope#>>'{authority,sha}'
       or p_evidence->>'sourceHeadSha' is distinct from
         v_expected_source_sha then
      raise exception 'on-demand-revalidation-attestation-verification-failed';
    end if;
  elsif p_step_type='release_reconciled' then
    if p_evidence->>'targetId' is distinct from
         v_admission.execution_envelope->>'targetId'
       or p_evidence->>'decision' not in ('admit','canonical')
       or p_evidence->>'admissionState' not in (
          'admitted','canonical','rollback-observed'
       ) then
      raise exception 'on-demand-revalidation-release-reconciliation-failed';
    end if;
  elsif p_step_type='completed' then
    if coalesce((p_evidence->>'verified')::boolean,false)<>true then
      raise exception 'on-demand-revalidation-completion-not-verified';
    end if;
  end if;

  v_evidence_hash := encode(
    extensions.digest(
      convert_to(p_evidence::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  insert into foundation.defence_on_demand_revalidation_events(
    event_id,execution_id,step_type,evidence,occurred_at,evidence_sha256
  ) values (
    p_event_id,p_execution_id,p_step_type,p_evidence,p_occurred_at,v_evidence_hash
  );

  return jsonb_build_object(
    'status','recorded',
    'executionId',p_execution_id,
    'stepType',p_step_type,
    'evidenceSha256',v_evidence_hash,
    'terminal',p_step_type in ('completed','failed')
  );
end;
$record_step$;

revoke all on function foundation.record_defence_on_demand_revalidation_step_v1(
  uuid,uuid,text,jsonb,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       service_role,shine_defence_runtime,shine_defence_on_demand_approver;
grant execute on function foundation.record_defence_on_demand_revalidation_step_v1(
  uuid,uuid,text,jsonb,timestamptz
) to shine_defence_on_demand_executor;


create or replace function foundation.get_defence_on_demand_revalidation_status_v1(
  p_target_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $status$
declare
  v_request foundation.defence_on_demand_revalidation_requests%rowtype;
  v_approval foundation.defence_on_demand_revalidation_approvals%rowtype;
  v_admission foundation.defence_on_demand_revalidation_admissions%rowtype;
  v_last_event foundation.defence_on_demand_revalidation_events%rowtype;
  v_state text;
  v_next_action text;
begin
  select * into v_request
  from foundation.defence_on_demand_revalidation_requests
  where target_id=p_target_id
    and requested_at<=p_as_of
  order by requested_at desc,request_sequence desc
  limit 1;

  if v_request.request_id is null then
    return jsonb_build_object(
      'defenceOnDemandRevalidationStatus',
        'shine-defence/on-demand-revalidation-status-v1',
      'schemaVersion','1.0.0',
      'targetId',p_target_id,
      'state','none',
      'nextAction','request_on_demand_revalidation',
      'evaluatedAt',p_as_of
    );
  end if;

  select * into v_approval
  from foundation.defence_on_demand_revalidation_approvals
  where request_id=v_request.request_id
  order by approved_at desc,approval_sequence desc
  limit 1;

  select * into v_admission
  from foundation.defence_on_demand_revalidation_admissions
  where request_id=v_request.request_id
  order by admitted_at desc,admission_sequence desc
  limit 1;

  if v_admission.execution_id is not null then
    select * into v_last_event
    from foundation.defence_on_demand_revalidation_events
    where execution_id=v_admission.execution_id
    order by event_sequence desc
    limit 1;
  end if;

  if v_last_event.step_type='completed' then
    v_state := 'completed';
    v_next_action := 'none';
  elsif v_last_event.step_type='failed' then
    v_state := 'failed';
    v_next_action := 'review_on_demand_revalidation_failure';
  elsif v_admission.execution_id is not null
     and v_admission.expires_at<=p_as_of
     and v_last_event.event_id is null then
    v_state := 'admission_expired';
    v_next_action := 'request_on_demand_revalidation';
  elsif v_admission.execution_id is not null
     and v_last_event.event_id is not null then
    v_state := 'in_progress';
    v_next_action := 'continue_on_demand_revalidation_execution';
  elsif v_admission.execution_id is not null then
    v_state := 'admitted';
    v_next_action := 'redeploy_current_source';
  elsif v_approval.approval_id is not null
     and v_approval.expires_at<=p_as_of then
    v_state := 'approval_expired';
    v_next_action := 'request_on_demand_revalidation';
  elsif v_approval.approval_id is not null then
    v_state := 'approved';
    v_next_action := 'admit_on_demand_revalidation_execution';
  elsif v_request.expires_at<=p_as_of then
    v_state := 'approval_expired';
    v_next_action := 'request_on_demand_revalidation';
  else
    v_state := 'pending_approval';
    v_next_action := 'approve_on_demand_revalidation_request';
  end if;

  return jsonb_build_object(
    'defenceOnDemandRevalidationStatus',
      'shine-defence/on-demand-revalidation-status-v1',
    'schemaVersion','1.0.0',
    'targetId',p_target_id,
    'state',v_state,
    'nextAction',v_next_action,
    'request',jsonb_build_object(
      'requestId',v_request.request_id,
      'reasonCode',v_request.reason_code,
      'requestedBy',v_request.requested_by,
      'requestedAt',v_request.requested_at,
      'expiresAt',v_request.expires_at,
      'evidenceFingerprint',v_request.evidence_fingerprint
    ),
    'approval',case
      when v_approval.approval_id is null then null
      else jsonb_build_object(
        'approvalId',v_approval.approval_id,
        'approvedBy',v_approval.approved_by,
        'approvalMethod',v_approval.approval_method,
        'approvedAt',v_approval.approved_at,
        'expiresAt',v_approval.expires_at
      )
    end,
    'execution',case
      when v_admission.execution_id is null then null
      else jsonb_build_object(
        'executionId',v_admission.execution_id,
        'admittedAt',v_admission.admitted_at,
        'expiresAt',v_admission.expires_at,
        'lastStep',v_last_event.step_type,
        'lastStepAt',v_last_event.occurred_at
      )
    end,
    'evaluatedAt',p_as_of
  );
end;
$status$;

revoke all on function foundation.get_defence_on_demand_revalidation_status_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_on_demand_revalidation_status_v1(
  text,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;
