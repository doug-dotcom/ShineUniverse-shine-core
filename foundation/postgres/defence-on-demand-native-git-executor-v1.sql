-- Shine Defence native Git on-demand executor v1.
-- Prepare and pin an immutable Git candidate before native-Git execution admission.

create table foundation.defence_on_demand_native_git_candidates (
  candidate_sequence bigint generated always as identity primary key,
  candidate_id uuid not null unique,
  approval_id uuid not null unique
    references foundation.defence_on_demand_revalidation_approvals(approval_id),
  request_id uuid not null unique
    references foundation.defence_on_demand_revalidation_requests(request_id),
  target_id text not null references foundation.defence_estate_targets(target_id),
  repository text not null
    check (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  branch text not null
    check (length(branch) between 1 and 200 and branch !~ '[[:cntrl:]]'),
  base_head_sha text not null check (base_head_sha ~ '^[a-f0-9]{40}$'),
  candidate_commit_sha text not null check (candidate_commit_sha ~ '^[a-f0-9]{40}$'),
  trigger_path text not null
    check (
      length(trigger_path) between 1 and 512
      and trigger_path !~ '[[:cntrl:]]'
      and trigger_path not like '%..%'
    ),
  marker_sha256 text not null check (marker_sha256 ~ '^[a-f0-9]{64}$'),
  prepared_by text not null
    check (prepared_by ~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$'),
  prepared_at timestamptz not null,
  expires_at timestamptz not null,
  candidate jsonb not null check (jsonb_typeof(candidate)='object'),
  candidate_sha256 text not null check (candidate_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default now(),
  check (candidate_commit_sha<>base_head_sha),
  check (expires_at>prepared_at),
  check (expires_at<=prepared_at+interval '15 minutes')
);

alter table foundation.defence_on_demand_native_git_candidates
  enable row level security;

create policy shine_defence_runtime_native_git_candidates_select
on foundation.defence_on_demand_native_git_candidates
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_native_git_candidates
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;
grant select on foundation.defence_on_demand_native_git_candidates
  to foundation_runtime,shine_defence_runtime,service_role,
     shine_defence_on_demand_approver,shine_defence_on_demand_executor;

create index defence_on_demand_native_git_candidates_target_idx
  on foundation.defence_on_demand_native_git_candidates(
    target_id,prepared_at desc,candidate_sequence desc
  );

create trigger defence_on_demand_native_git_candidates_append_only
before update or delete
on foundation.defence_on_demand_native_git_candidates
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.record_defence_on_demand_native_git_candidate_v1(
  p_candidate_id uuid,
  p_approval_id uuid,
  p_repository text,
  p_branch text,
  p_base_head_sha text,
  p_candidate_commit_sha text,
  p_trigger_path text,
  p_marker_sha256 text,
  p_prepared_by text,
  p_prepared_at timestamptz,
  p_expires_at timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $record_candidate$
declare
  v_approval foundation.defence_on_demand_revalidation_approvals%rowtype;
  v_request foundation.defence_on_demand_revalidation_requests%rowtype;
  v_snapshot jsonb;
  v_fingerprint text;
  v_selection jsonb;
  v_candidate jsonb;
  v_candidate_hash text;
begin
  if p_candidate_id is null
     or p_approval_id is null
     or p_prepared_at is null
     or p_expires_at is null
     or p_expires_at<=p_prepared_at
     or p_expires_at>p_prepared_at+interval '15 minutes'
     or p_prepared_at<now()-interval '5 minutes'
     or p_prepared_at>now()+interval '5 minutes'
     or p_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
     or p_branch is null
     or length(p_branch) not between 1 and 200
     or p_branch ~ '[[:cntrl:]]'
     or lower(coalesce(p_base_head_sha,'')) !~ '^[a-f0-9]{40}$'
     or lower(coalesce(p_candidate_commit_sha,'')) !~ '^[a-f0-9]{40}$'
     or lower(p_candidate_commit_sha)=lower(p_base_head_sha)
     or p_trigger_path is null
     or length(p_trigger_path) not between 1 and 512
     or p_trigger_path ~ '[[:cntrl:]]'
     or p_trigger_path like '%..%'
     or lower(coalesce(p_marker_sha256,'')) !~ '^[a-f0-9]{64}$'
     or p_prepared_by is null
     or p_prepared_by !~ '^[A-Za-z0-9][A-Za-z0-9._:@+-]{0,127}$'
     or p_evidence_ref is null
     or length(p_evidence_ref) not between 1 and 1024
     or p_evidence_ref ~ '[[:cntrl:]]'
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object'
     or pg_column_size(p_metadata)>16384 then
    raise exception 'on-demand-native-git-candidate-fields-invalid'
      using errcode='22023';
  end if;

  select * into v_approval
  from foundation.defence_on_demand_revalidation_approvals
  where approval_id=p_approval_id
  for update;

  if v_approval.approval_id is null then
    raise exception 'on-demand-native-git-approval-missing';
  end if;

  if v_approval.expires_at<=p_prepared_at
     or v_approval.approved_at>p_prepared_at then
    raise exception 'on-demand-native-git-approval-not-active';
  end if;

  if v_approval.approval#>>'{executorSelection,selectedMode}'<>'native_git' then
    raise exception 'on-demand-native-git-not-approved-executor';
  end if;

  select * into v_request
  from foundation.defence_on_demand_revalidation_requests
  where request_id=v_approval.request_id;

  if v_request.request_id is null
     or v_request.expires_at<=p_prepared_at then
    raise exception 'on-demand-native-git-request-not-active';
  end if;

  v_snapshot :=
    foundation.get_defence_on_demand_revalidation_snapshot_v1(
      v_request.target_id,p_prepared_at
    );
  v_fingerprint :=
    foundation.get_defence_on_demand_revalidation_fingerprint_v1(v_snapshot);
  v_selection :=
    foundation.get_defence_on_demand_executor_selection_v1(
      v_request.target_id,p_prepared_at
    );

  if v_fingerprint is distinct from v_request.evidence_fingerprint
     or coalesce((v_snapshot->>'eligible')::boolean,false)<>true
     or v_snapshot->>'postureState'<>'revalidation_required'
     or v_selection->>'state'<>'ready'
     or v_selection->>'selectedMode'<>'native_git' then
    raise exception 'on-demand-native-git-live-scope-changed';
  end if;

  if lower(p_base_head_sha) is distinct from lower(v_snapshot#>>'{source,headSha}')
     or p_repository is distinct from v_selection#>>'{nativeGit,repository}'
     or p_branch is distinct from v_selection#>>'{nativeGit,branch}'
     or position(
       coalesce(v_selection#>>'{nativeGit,triggerPathPrefix}','')
       in p_trigger_path
     )<>1 then
    raise exception 'on-demand-native-git-candidate-scope-mismatch';
  end if;

  if p_expires_at>v_approval.expires_at then
    raise exception 'on-demand-native-git-candidate-outlives-approval';
  end if;

  if exists (
    select 1
    from foundation.defence_on_demand_native_git_candidates
    where approval_id=p_approval_id
       or request_id=v_request.request_id
  ) then
    raise exception 'on-demand-native-git-candidate-already-prepared';
  end if;

  v_candidate := jsonb_build_object(
    'defenceOnDemandNativeGitCandidate',
      'shine-defence/on-demand-native-git-candidate-v1',
    'schemaVersion','1.0.0',
    'candidateId',p_candidate_id,
    'approvalId',p_approval_id,
    'requestId',v_request.request_id,
    'targetId',v_request.target_id,
    'repository',p_repository,
    'branch',p_branch,
    'baseHeadSha',lower(p_base_head_sha),
    'candidateCommitSha',lower(p_candidate_commit_sha),
    'triggerPath',p_trigger_path,
    'markerSha256',lower(p_marker_sha256),
    'preparedBy',p_prepared_by,
    'preparedAt',p_prepared_at,
    'expiresAt',p_expires_at,
    'executorSelection',v_selection,
    'externalMutationPerformed',false,
    'watchedBranchChanged',false
  );

  v_candidate_hash := encode(
    extensions.digest(convert_to(v_candidate::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.defence_on_demand_native_git_candidates(
    candidate_id,approval_id,request_id,target_id,repository,branch,
    base_head_sha,candidate_commit_sha,trigger_path,marker_sha256,
    prepared_by,prepared_at,expires_at,candidate,candidate_sha256,
    evidence_ref,metadata
  ) values (
    p_candidate_id,p_approval_id,v_request.request_id,v_request.target_id,
    p_repository,p_branch,lower(p_base_head_sha),lower(p_candidate_commit_sha),
    p_trigger_path,lower(p_marker_sha256),p_prepared_by,p_prepared_at,p_expires_at,
    v_candidate,v_candidate_hash,p_evidence_ref,p_metadata
  );

  return jsonb_build_object(
    'status','candidate-prepared',
    'candidateId',p_candidate_id,
    'requestId',v_request.request_id,
    'approvalId',p_approval_id,
    'targetId',v_request.target_id,
    'candidateCommitSha',lower(p_candidate_commit_sha),
    'candidateSha256',v_candidate_hash,
    'nextAction','admit_on_demand_revalidation_execution',
    'executionAuthorityGranted',false,
    'externalMutationPerformed',false
  );
end;
$record_candidate$;

revoke all on function foundation.record_defence_on_demand_native_git_candidate_v1(
  uuid,uuid,text,text,text,text,text,text,text,timestamptz,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       service_role,shine_defence_runtime,shine_defence_on_demand_approver;
grant execute on function foundation.record_defence_on_demand_native_git_candidate_v1(
  uuid,uuid,text,text,text,text,text,text,text,timestamptz,timestamptz,text,jsonb
) to shine_defence_on_demand_executor;

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
  v_candidate foundation.defence_on_demand_native_git_candidates%rowtype;
  v_candidate_hash text;
  v_expected_source_sha text;
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
    select * into v_candidate
    from foundation.defence_on_demand_native_git_candidates
    where approval_id=v_approval.approval_id
      and request_id=v_request.request_id
    for update;

    if v_candidate.candidate_id is null then
      raise exception 'on-demand-native-git-candidate-required';
    end if;

    if v_candidate.expires_at<=p_admitted_at then
      raise exception 'on-demand-native-git-candidate-expired';
    end if;

    v_candidate_hash := encode(
      extensions.digest(
        convert_to(v_candidate.candidate::text,'UTF8'),'sha256'
      ),
      'hex'
    );

    if v_candidate_hash is distinct from v_candidate.candidate_sha256
       or lower(v_candidate.base_head_sha) is distinct from
          lower(v_snapshot#>>'{source,headSha}')
       or v_candidate.repository is distinct from
          v_executor#>>'{nativeGit,repository}'
       or v_candidate.branch is distinct from
          v_executor#>>'{nativeGit,branch}'
       or position(
          coalesce(v_executor#>>'{nativeGit,triggerPathPrefix}','')
          in v_candidate.trigger_path
       )<>1 then
      raise exception 'on-demand-native-git-candidate-integrity-failed';
    end if;

    v_expected_source_sha := lower(v_candidate.candidate_commit_sha);
  elsif v_current_mode='direct_railway' then
    v_expected_source_sha := lower(v_snapshot#>>'{source,headSha}');
  else
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
    'sourceBefore',v_snapshot->'source',
    'sourceCandidate',case when v_current_mode='native_git' then v_candidate.candidate else null end,
    'servingBefore',v_snapshot->'serving',
    'canonicalBefore',v_snapshot->'canonical',
    'authority',v_snapshot->'authority',
    'executorSelection',v_executor,
    'requiredSequence',case
      when v_current_mode='native_git' then jsonb_build_array(
        'fast_forward_native_git_candidate',
        'verify_railway_deployment_success',
        'verify_deployed_commit',
        'enqueue_on_demand_health_probe',
        'verify_health_contract',
        'refresh_defence_attestations',
        'reconcile_release_admission'
      )
      else jsonb_build_array(
        'redeploy_current_source',
        'verify_railway_deployment_success',
        'verify_deployed_commit',
        'enqueue_on_demand_health_probe',
        'verify_health_contract',
        'refresh_defence_attestations',
        'reconcile_release_admission'
      )
    end,
    'constraints',jsonb_build_object(
      'executorMode',v_current_mode,
      'expectedSourceHeadSha',v_expected_source_sha,
      'requiredBranchBaseSha',case when v_current_mode='native_git' then lower(v_candidate.base_head_sha) else null end,
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
    'nextAction',case
      when v_current_mode='native_git'
        then 'execute_native_git_fast_forward'
      else 'execute_direct_railway_revalidation'
    end,
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
  v_candidate foundation.defence_on_demand_native_git_candidates%rowtype;
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

  select * into v_candidate
  from foundation.defence_on_demand_native_git_candidates
  where request_id=v_request.request_id
  order by prepared_at desc,candidate_sequence desc
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
        then 'execute_native_git_fast_forward'
      else 'review_on_demand_executor_selection'
    end;
  elsif v_approval.approval_id is not null
     and v_approval.expires_at<=p_as_of then
    v_state := 'approval_expired';
    v_next_action := 'request_on_demand_revalidation';
  elsif v_approval.approval_id is not null
     and v_executor_mode='native_git'
     and v_candidate.candidate_id is not null
     and v_candidate.expires_at>p_as_of then
    v_state := 'candidate_prepared';
    v_next_action := 'admit_on_demand_revalidation_execution';
  elsif v_approval.approval_id is not null
     and v_executor_mode='native_git'
     and v_candidate.candidate_id is not null
     and v_candidate.expires_at<=p_as_of then
    v_state := 'candidate_expired';
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
    'candidate',case
      when v_candidate.candidate_id is null then null
      else jsonb_build_object(
        'candidateId',v_candidate.candidate_id,
        'repository',v_candidate.repository,
        'branch',v_candidate.branch,
        'baseHeadSha',v_candidate.base_head_sha,
        'candidateCommitSha',v_candidate.candidate_commit_sha,
        'triggerPath',v_candidate.trigger_path,
        'preparedAt',v_candidate.prepared_at,
        'expiresAt',v_candidate.expires_at,
        'candidateSha256',v_candidate.candidate_sha256
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
