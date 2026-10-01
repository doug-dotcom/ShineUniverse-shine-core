-- Shine Defence native Git bridge v1.
-- Durable receipt for the actual watched-branch fast-forward performed by the
-- OIDC-gated reusable workflow.

create table foundation.defence_on_demand_native_git_fast_forward_receipts (
  receipt_sequence bigint generated always as identity primary key,
  receipt_id uuid not null unique,
  execution_id uuid not null unique
    references foundation.defence_on_demand_revalidation_admissions(execution_id),
  candidate_id uuid not null unique
    references foundation.defence_on_demand_native_git_candidates(candidate_id),
  target_id text not null references foundation.defence_estate_targets(target_id),
  repository text not null
    check (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  branch text not null
    check (length(branch) between 1 and 200 and branch !~ '[[:cntrl:]]'),
  previous_head_sha text not null check (previous_head_sha ~ '^[a-f0-9]{40}$'),
  new_head_sha text not null check (new_head_sha ~ '^[a-f0-9]{40}$'),
  observed_after_sha text not null check (observed_after_sha ~ '^[a-f0-9]{40}$'),
  occurred_at timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default now(),
  check (new_head_sha=observed_after_sha),
  check (previous_head_sha<>new_head_sha)
);

alter table foundation.defence_on_demand_native_git_fast_forward_receipts
  enable row level security;

create policy shine_defence_runtime_native_git_fast_forward_receipts_select
on foundation.defence_on_demand_native_git_fast_forward_receipts
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_on_demand_native_git_fast_forward_receipts
  from public,anon,authenticated,foundation_gateway,
       shine_defence_on_demand_approver,shine_defence_on_demand_executor;
grant select on foundation.defence_on_demand_native_git_fast_forward_receipts
  to foundation_runtime,shine_defence_runtime,service_role,
     shine_defence_on_demand_approver,shine_defence_on_demand_executor;

create index defence_on_demand_native_git_fast_forward_target_idx
  on foundation.defence_on_demand_native_git_fast_forward_receipts(
    target_id,occurred_at desc,receipt_sequence desc
  );

create trigger defence_on_demand_native_git_fast_forward_receipts_append_only
before update or delete
on foundation.defence_on_demand_native_git_fast_forward_receipts
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.record_defence_on_demand_native_git_fast_forward_v1(
  p_receipt_id uuid,
  p_execution_id uuid,
  p_previous_head_sha text,
  p_new_head_sha text,
  p_observed_after_sha text,
  p_occurred_at timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fast_forward$
declare
  v_admission foundation.defence_on_demand_revalidation_admissions%rowtype;
  v_candidate foundation.defence_on_demand_native_git_candidates%rowtype;
  v_start foundation.defence_on_demand_revalidation_events%rowtype;
  v_envelope_hash text;
  v_receipt_sequence bigint;
begin
  if p_receipt_id is null
     or p_execution_id is null
     or lower(coalesce(p_previous_head_sha,'')) !~ '^[a-f0-9]{40}$'
     or lower(coalesce(p_new_head_sha,'')) !~ '^[a-f0-9]{40}$'
     or lower(coalesce(p_observed_after_sha,'')) !~ '^[a-f0-9]{40}$'
     or lower(p_new_head_sha)<>lower(p_observed_after_sha)
     or lower(p_previous_head_sha)=lower(p_new_head_sha)
     or p_occurred_at is null
     or p_occurred_at<now()-interval '10 minutes'
     or p_occurred_at>now()+interval '5 minutes'
     or p_evidence_ref is null
     or length(p_evidence_ref) not between 1 and 1024
     or p_evidence_ref ~ '[[:cntrl:]]'
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object'
     or pg_column_size(p_metadata)>32768 then
    raise exception 'invalid-native-git-fast-forward-receipt'
      using errcode='22023';
  end if;

  select * into v_admission
  from foundation.defence_on_demand_revalidation_admissions
  where execution_id=p_execution_id
  for update;

  if v_admission.execution_id is null then
    raise exception 'native-git-fast-forward-execution-missing';
  end if;

  v_envelope_hash := encode(
    extensions.digest(
      convert_to(v_admission.execution_envelope::text,'UTF8'),'sha256'
    ),
    'hex'
  );

  if v_envelope_hash is distinct from v_admission.envelope_sha256
     or v_admission.execution_envelope#>>'{constraints,executorMode}'<>'native_git' then
    raise exception 'native-git-fast-forward-admission-invalid';
  end if;

  select * into v_candidate
  from foundation.defence_on_demand_native_git_candidates
  where approval_id=v_admission.approval_id
    and request_id=v_admission.request_id;

  if v_candidate.candidate_id is null
     or lower(v_candidate.base_head_sha) is distinct from
        lower(v_admission.execution_envelope#>>'{constraints,requiredBranchBaseSha}')
     or lower(v_candidate.candidate_commit_sha) is distinct from
        lower(v_admission.execution_envelope#>>'{constraints,expectedSourceHeadSha}')
     or lower(p_previous_head_sha) is distinct from lower(v_candidate.base_head_sha)
     or lower(p_new_head_sha) is distinct from lower(v_candidate.candidate_commit_sha)
     or lower(p_observed_after_sha) is distinct from lower(v_candidate.candidate_commit_sha)
     or v_candidate.repository is distinct from
        v_admission.execution_envelope#>>'{sourceCandidate,repository}'
     or v_candidate.branch is distinct from
        v_admission.execution_envelope#>>'{sourceCandidate,branch}' then
    raise exception 'native-git-fast-forward-scope-mismatch';
  end if;

  select * into v_start
  from foundation.defence_on_demand_revalidation_events
  where execution_id=p_execution_id
    and step_type='redeploy_started'
  order by event_sequence desc
  limit 1;

  if v_start.event_id is null
     or v_start.evidence->>'executorMode'<>'native_git'
     or lower(v_start.evidence->>'observedBranchHeadSha') is distinct from
        lower(v_candidate.base_head_sha)
     or lower(v_start.evidence->>'candidateCommitSha') is distinct from
        lower(v_candidate.candidate_commit_sha) then
    raise exception 'native-git-fast-forward-start-evidence-missing';
  end if;

  if exists (
    select 1
    from foundation.defence_on_demand_revalidation_events
    where execution_id=p_execution_id
      and step_type in ('completed','failed')
  ) then
    raise exception 'native-git-fast-forward-execution-terminal';
  end if;

  insert into foundation.defence_on_demand_native_git_fast_forward_receipts(
    receipt_id,execution_id,candidate_id,target_id,repository,branch,
    previous_head_sha,new_head_sha,observed_after_sha,
    occurred_at,evidence_ref,metadata
  ) values (
    p_receipt_id,p_execution_id,v_candidate.candidate_id,
    v_admission.execution_envelope->>'targetId',
    v_candidate.repository,v_candidate.branch,
    lower(p_previous_head_sha),lower(p_new_head_sha),lower(p_observed_after_sha),
    p_occurred_at,p_evidence_ref,p_metadata
  )
  returning receipt_sequence into v_receipt_sequence;

  return jsonb_build_object(
    'status','recorded',
    'receiptId',p_receipt_id,
    'receiptSequence',v_receipt_sequence,
    'executionId',p_execution_id,
    'candidateId',v_candidate.candidate_id,
    'targetId',v_admission.execution_envelope->>'targetId',
    'repository',v_candidate.repository,
    'branch',v_candidate.branch,
    'previousHeadSha',lower(p_previous_head_sha),
    'newHeadSha',lower(p_new_head_sha),
    'observedAfterSha',lower(p_observed_after_sha),
    'externalMutationVerified',true,
    'nextAction','verify_railway_deployment_success'
  );
end;
$fast_forward$;

revoke all on function foundation.record_defence_on_demand_native_git_fast_forward_v1(
  uuid,uuid,text,text,text,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       service_role,shine_defence_runtime,shine_defence_on_demand_approver;
grant execute on function foundation.record_defence_on_demand_native_git_fast_forward_v1(
  uuid,uuid,text,text,text,timestamptz,text,jsonb
) to shine_defence_on_demand_executor;
