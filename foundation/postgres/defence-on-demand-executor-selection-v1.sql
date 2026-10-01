-- Shine Defence on-demand executor selection v1.
-- Choose a viable executor before execution admission is consumed.

create table foundation.defence_on_demand_executor_profiles (
  profile_sequence bigint generated always as identity primary key,
  target_id text not null references foundation.defence_estate_targets(target_id),
  direct_railway_enabled boolean not null default true,
  native_git_enabled boolean not null default false,
  native_git_repository text,
  native_git_branch text,
  native_git_trigger_path_prefix text,
  native_git_proof_commit_sha text,
  native_git_proof_deployment_id uuid,
  native_git_proven_at timestamptz,
  effective_at timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default now(),
  check (
    not native_git_enabled
    or (
      native_git_repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
      and native_git_branch is not null
      and length(native_git_branch) between 1 and 200
      and native_git_trigger_path_prefix is not null
      and native_git_trigger_path_prefix like 'security/shine-defence/%'
      and native_git_proof_commit_sha ~ '^[a-f0-9]{40}$'
      and native_git_proof_deployment_id is not null
      and native_git_proven_at is not null
    )
  )
);

alter table foundation.defence_on_demand_executor_profiles
  enable row level security;

create policy shine_defence_runtime_executor_profiles_select
on foundation.defence_on_demand_executor_profiles
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_executor_profiles
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;
grant select on foundation.defence_on_demand_executor_profiles
  to foundation_runtime,shine_defence_runtime,service_role,
     shine_defence_on_demand_approver,shine_defence_on_demand_executor;

create index defence_on_demand_executor_profiles_target_idx
  on foundation.defence_on_demand_executor_profiles(
    target_id,effective_at desc,profile_sequence desc
  );

create trigger defence_on_demand_executor_profiles_append_only
before update or delete
on foundation.defence_on_demand_executor_profiles
for each row execute function foundation.reject_append_only_mutation();


create table foundation.defence_on_demand_executor_readiness_receipts (
  receipt_sequence bigint generated always as identity primary key,
  executor_mode text not null
    check (executor_mode in ('direct_railway')),
  credential_ready boolean not null,
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default now(),
  check (valid_until>observed_at),
  check (valid_until<=observed_at+interval '2 hours')
);

alter table foundation.defence_on_demand_executor_readiness_receipts
  enable row level security;

create policy shine_defence_runtime_executor_readiness_select
on foundation.defence_on_demand_executor_readiness_receipts
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_executor_readiness_receipts
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;
grant select on foundation.defence_on_demand_executor_readiness_receipts
  to foundation_runtime,shine_defence_runtime,service_role,
     shine_defence_on_demand_approver,shine_defence_on_demand_executor;

create index defence_on_demand_executor_readiness_idx
  on foundation.defence_on_demand_executor_readiness_receipts(
    executor_mode,observed_at desc,receipt_sequence desc
  );

create trigger defence_on_demand_executor_readiness_append_only
before update or delete
on foundation.defence_on_demand_executor_readiness_receipts
for each row execute function foundation.reject_append_only_mutation();


insert into foundation.defence_on_demand_executor_profiles(
  target_id,direct_railway_enabled,native_git_enabled,
  native_git_repository,native_git_branch,native_git_trigger_path_prefix,
  native_git_proof_commit_sha,native_git_proof_deployment_id,
  native_git_proven_at,effective_at,evidence_ref,metadata
)
select
  'railway:dnd',true,true,
  'doug-dotcom/shine-D-D','build/layer-001-foundation',
  'security/shine-defence/revalidation-triggers/',
  '9c6c116e589e360e3d48468dfe1e5be1c75235ca',
  '8e95bb92-e5ea-46bf-9be1-0ecba30205f4'::uuid,
  '2026-10-01T03:25:04.211823Z'::timestamptz,
  '2026-10-01T03:25:04.211823Z'::timestamptz,
  'github:doug-dotcom/shine-D-D:9c6c116e589e360e3d48468dfe1e5be1c75235ca:native-git-executor-proof',
  jsonb_build_object(
    'proof','exact-commit Railway SUCCESS + health provenance + source attestation',
    'railwayDeploymentStatus','SUCCESS',
    'runtimeCodeChanged',false
  )
where exists (
  select 1 from foundation.defence_estate_targets
  where target_id='railway:dnd'
)
and not exists (
  select 1 from foundation.defence_on_demand_executor_profiles
  where evidence_ref='github:doug-dotcom/shine-D-D:9c6c116e589e360e3d48468dfe1e5be1c75235ca:native-git-executor-proof'
);


create or replace function foundation.record_defence_on_demand_executor_readiness_v1(
  p_executor_mode text,
  p_credential_ready boolean,
  p_observed_at timestamptz,
  p_valid_until timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $readiness$
declare
  v_sequence bigint;
begin
  if p_executor_mode<>'direct_railway'
     or p_credential_ready is null
     or p_observed_at is null
     or p_valid_until is null
     or p_valid_until<=p_observed_at
     or p_valid_until>p_observed_at+interval '2 hours'
     or p_observed_at<now()-interval '10 minutes'
     or p_observed_at>now()+interval '5 minutes'
     or p_evidence_ref is null
     or length(p_evidence_ref) not between 1 and 512
     or p_evidence_ref ~ '[[:cntrl:]]'
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object'
     or pg_column_size(p_metadata)>16384 then
    raise exception 'invalid-on-demand-executor-readiness';
  end if;

  insert into foundation.defence_on_demand_executor_readiness_receipts(
    executor_mode,credential_ready,observed_at,valid_until,
    evidence_ref,metadata
  ) values (
    p_executor_mode,p_credential_ready,p_observed_at,p_valid_until,
    p_evidence_ref,p_metadata
  )
  on conflict (evidence_ref) do nothing
  returning receipt_sequence into v_sequence;

  return jsonb_build_object(
    'status',case when v_sequence is null then 'already-recorded' else 'recorded' end,
    'executorMode',p_executor_mode,
    'credentialReady',p_credential_ready,
    'observedAt',p_observed_at,
    'validUntil',p_valid_until,
    'receiptSequence',v_sequence
  );
end;
$readiness$;

revoke all on function foundation.record_defence_on_demand_executor_readiness_v1(
  text,boolean,timestamptz,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime,shine_defence_on_demand_approver,
       shine_defence_on_demand_executor;
grant execute on function foundation.record_defence_on_demand_executor_readiness_v1(
  text,boolean,timestamptz,timestamptz,text,jsonb
) to service_role;


create or replace function foundation.get_defence_on_demand_executor_selection_v1(
  p_target_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $selection$
declare
  v_profile foundation.defence_on_demand_executor_profiles%rowtype;
  v_readiness foundation.defence_on_demand_executor_readiness_receipts%rowtype;
  v_direct_ready boolean := false;
  v_native_ready boolean := false;
  v_mode text;
  v_reason text;
  v_state text;
begin
  if p_target_id is null
     or length(btrim(p_target_id))=0
     or p_as_of is null then
    raise exception 'invalid-on-demand-executor-selection-input'
      using errcode='22023';
  end if;

  select * into v_profile
  from foundation.defence_on_demand_executor_profiles
  where target_id=p_target_id
    and effective_at<=p_as_of
  order by effective_at desc,profile_sequence desc
  limit 1;

  select * into v_readiness
  from foundation.defence_on_demand_executor_readiness_receipts
  where executor_mode='direct_railway'
    and observed_at<=p_as_of
  order by observed_at desc,receipt_sequence desc
  limit 1;

  v_direct_ready := coalesce(v_profile.direct_railway_enabled,false)
    and coalesce(v_readiness.credential_ready,false)
    and v_readiness.valid_until>p_as_of;

  v_native_ready := coalesce(v_profile.native_git_enabled,false)
    and v_profile.native_git_repository is not null
    and v_profile.native_git_branch is not null
    and v_profile.native_git_trigger_path_prefix is not null
    and v_profile.native_git_proof_commit_sha ~ '^[a-f0-9]{40}$'
    and v_profile.native_git_proof_deployment_id is not null
    and v_profile.native_git_proven_at is not null;

  if v_direct_ready then
    v_state := 'ready';
    v_mode := 'direct_railway';
    v_reason := 'direct-railway-credential-ready';
  elsif v_native_ready then
    v_state := 'ready';
    v_mode := 'native_git';
    v_reason := case
      when v_readiness.receipt_sequence is null
        then 'native-git-selected-no-direct-readiness'
      when not v_readiness.credential_ready
        then 'native-git-selected-direct-credential-missing'
      else 'native-git-selected-direct-readiness-stale'
    end;
  else
    v_state := 'blocked';
    v_mode := null;
    v_reason := case
      when v_profile.profile_sequence is null then 'executor-profile-missing'
      when coalesce(v_profile.direct_railway_enabled,false)
        and v_readiness.receipt_sequence is null then 'direct-readiness-missing'
      when coalesce(v_profile.direct_railway_enabled,false)
        and v_readiness.valid_until<=p_as_of then 'direct-readiness-stale'
      else 'no-viable-executor'
    end;
  end if;

  return jsonb_build_object(
    'defenceOnDemandExecutorSelection',
      'shine-defence/on-demand-executor-selection-v1',
    'schemaVersion','1.0.0',
    'targetId',p_target_id,
    'state',v_state,
    'selectedMode',v_mode,
    'reasonCode',v_reason,
    'directRailway',jsonb_build_object(
      'enabled',coalesce(v_profile.direct_railway_enabled,false),
      'ready',v_direct_ready,
      'credentialReady',coalesce(v_readiness.credential_ready,false),
      'observedAt',v_readiness.observed_at,
      'validUntil',v_readiness.valid_until,
      'evidenceRef',v_readiness.evidence_ref
    ),
    'nativeGit',jsonb_build_object(
      'enabled',coalesce(v_profile.native_git_enabled,false),
      'ready',v_native_ready,
      'repository',v_profile.native_git_repository,
      'branch',v_profile.native_git_branch,
      'triggerPathPrefix',v_profile.native_git_trigger_path_prefix,
      'proofCommitSha',v_profile.native_git_proof_commit_sha,
      'proofDeploymentId',v_profile.native_git_proof_deployment_id,
      'provenAt',v_profile.native_git_proven_at,
      'evidenceRef',v_profile.evidence_ref
    ),
    'evaluatedAt',p_as_of
  );
end;
$selection$;

revoke all on function foundation.get_defence_on_demand_executor_selection_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_on_demand_executor_selection_v1(
  text,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;

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
  v_executor jsonb;
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

  v_executor :=
    foundation.get_defence_on_demand_executor_selection_v1(
      v_request.target_id,p_approved_at
    );

  if v_executor->>'state'<>'ready'
     or v_executor->>'selectedMode' is null then
    raise exception 'on-demand-revalidation-executor-unavailable';
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
    'executorSelection',v_executor,
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
    'selectedExecutorMode',v_executor->>'selectedMode',
    'nextAction',case
      when v_executor->>'selectedMode'='direct_railway'
        then 'admit_on_demand_revalidation_execution'
      else 'prepare_native_git_revalidation_candidate'
    end,
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
  v_executor jsonb;
  v_approved_mode text;
  v_current_mode text;
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

  v_executor :=
    foundation.get_defence_on_demand_executor_selection_v1(
      v_request.target_id,p_admitted_at
    );
  v_approved_mode := v_approval.approval#>>'{executorSelection,selectedMode}';
  v_current_mode := v_executor->>'selectedMode';

  if v_executor->>'state'<>'ready' or v_current_mode is null then
    raise exception 'on-demand-revalidation-executor-unavailable';
  end if;

  if v_approved_mode is distinct from v_current_mode then
    raise exception 'on-demand-revalidation-executor-changed-after-approval';
  end if;

  if v_current_mode='native_git' then
    raise exception 'on-demand-native-git-candidate-required';
  end if;

  if v_current_mode<>'direct_railway' then
    raise exception 'on-demand-revalidation-executor-mode-invalid';
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
    'executorSelection',v_executor,
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
      'executorMode',v_current_mode,
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
    'selectedExecutorMode',v_current_mode,
    'nextAction','execute_direct_railway_revalidation',
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
  v_executor_mode text;
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

  v_executor_mode := case
    when v_admission.execution_id is not null
      then v_admission.execution_envelope#>>'{executorSelection,selectedMode}'
    when v_approval.approval_id is not null
      then v_approval.approval#>>'{executorSelection,selectedMode}'
    else null
  end;

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
    v_next_action := case
      when v_executor_mode='direct_railway'
        then 'execute_direct_railway_revalidation'
      when v_executor_mode='native_git'
        then 'execute_native_git_revalidation'
      else 'review_on_demand_executor_selection'
    end;
  elsif v_approval.approval_id is not null
     and v_approval.expires_at<=p_as_of then
    v_state := 'approval_expired';
    v_next_action := 'request_on_demand_revalidation';
  elsif v_approval.approval_id is not null then
    v_state := 'approved';
    v_next_action := case
      when v_executor_mode='direct_railway'
        then 'admit_on_demand_revalidation_execution'
      when v_executor_mode='native_git'
        then 'prepare_native_git_revalidation_candidate'
      else 'review_on_demand_executor_selection'
    end;
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
        'expiresAt',v_approval.expires_at,
        'executorSelection',v_approval.approval->'executorSelection'
      )
    end,
    'execution',case
      when v_admission.execution_id is null then null
      else jsonb_build_object(
        'executionId',v_admission.execution_id,
        'admittedAt',v_admission.admitted_at,
        'expiresAt',v_admission.expires_at,
        'lastStep',v_last_event.step_type,
        'lastStepAt',v_last_event.occurred_at,
        'executorSelection',v_admission.execution_envelope->'executorSelection'
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
