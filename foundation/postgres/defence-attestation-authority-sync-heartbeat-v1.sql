-- Shine Defence attestation-authority sync heartbeat v1.
-- Successful signed Core->Foundation authority assertions emit append-only
-- receipts. Freshness is observable independently from authority activation history.

create table foundation.defence_attestation_authority_sync_receipts (
  receipt_sequence bigint generated always as identity primary key,
  receipt_id uuid not null unique default gen_random_uuid(),
  lineage_sequence bigint not null check (lineage_sequence>=1),
  authority_sha text not null check (authority_sha ~ '^[a-fA-F0-9]{40}$'),
  authority_ref text not null
    check (length(authority_ref) between 1 and 1024 and authority_ref !~ '[[:cntrl:]]'),
  workflow_blob_sha text not null check (workflow_blob_sha ~ '^[a-fA-F0-9]{40}$'),
  publisher_commit_sha text not null check (publisher_commit_sha ~ '^[a-fA-F0-9]{40}$'),
  lineage_blob_sha text not null check (lineage_blob_sha ~ '^[a-fA-F0-9]{40}$'),
  authority_contract_blob_sha text not null
    check (authority_contract_blob_sha ~ '^[a-fA-F0-9]{40}$'),
  sync_outcome text not null
    check (sync_outcome in ('asserted-current','recorded','replayed')),
  github_run_id text not null check (github_run_id ~ '^[0-9]{1,32}$'),
  github_run_attempt text not null check (github_run_attempt ~ '^[0-9]{1,16}$'),
  github_event text not null check (github_event in ('push','workflow_dispatch','schedule')),
  observed_at timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default clock_timestamp(),
  check (right(lower(authority_ref),41)='@'||lower(authority_sha))
);

alter table foundation.defence_attestation_authority_sync_receipts enable row level security;

create policy shine_defence_runtime_authority_sync_receipt_select
on foundation.defence_attestation_authority_sync_receipts
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_attestation_authority_sync_receipts
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant select on foundation.defence_attestation_authority_sync_receipts
  to shine_defence_runtime,service_role;

create index defence_attestation_authority_sync_receipts_time_idx
  on foundation.defence_attestation_authority_sync_receipts(
    observed_at desc,receipt_sequence desc
  );

create trigger defence_attestation_authority_sync_receipts_append_only
before update or delete on foundation.defence_attestation_authority_sync_receipts
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.record_defence_attestation_authority_sync_receipt_v1(
  p_lineage_sequence bigint,
  p_authority_sha text,
  p_authority_ref text,
  p_workflow_blob_sha text,
  p_publisher_commit_sha text,
  p_lineage_blob_sha text,
  p_authority_contract_blob_sha text,
  p_sync_outcome text,
  p_github_run_id text,
  p_github_run_attempt text,
  p_github_event text,
  p_observed_at timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $authority_sync_receipt$
declare
  v_current foundation.defence_attestation_authority_activations%rowtype;
  v_current_lineage_sequence bigint;
  v_existing foundation.defence_attestation_authority_sync_receipts%rowtype;
  v_receipt_id uuid;
begin
  if p_lineage_sequence is null or p_lineage_sequence<1
     or p_authority_sha !~ '^[a-fA-F0-9]{40}$'
     or p_workflow_blob_sha !~ '^[a-fA-F0-9]{40}$'
     or p_publisher_commit_sha !~ '^[a-fA-F0-9]{40}$'
     or p_lineage_blob_sha !~ '^[a-fA-F0-9]{40}$'
     or p_authority_contract_blob_sha !~ '^[a-fA-F0-9]{40}$'
     or p_sync_outcome not in ('asserted-current','recorded','replayed')
     or p_github_run_id !~ '^[0-9]{1,32}$'
     or p_github_run_attempt !~ '^[0-9]{1,16}$'
     or p_github_event not in ('push','workflow_dispatch','schedule')
     or p_observed_at is null
     or p_observed_at>clock_timestamp()+interval '5 minutes'
     or p_evidence_ref is null
     or length(p_evidence_ref) not between 1 and 1024
     or p_evidence_ref ~ '[[:cntrl:]]'
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-attestation-authority-sync-receipt' using errcode='22023';
  end if;

  select * into v_current
  from foundation.defence_attestation_authority_activations
  order by activated_at desc,activation_sequence desc
  limit 1;

  if v_current.activation_sequence is null then
    return jsonb_build_object('status','rejected','reasonCode','active-authority-missing');
  end if;

  v_current_lineage_sequence := case
    when v_current.activation_kind='bootstrap' then 1
    when coalesce(v_current.metadata->>'lineageSequence','') ~ '^[0-9]{1,18}$'
      then (v_current.metadata->>'lineageSequence')::bigint
    else null
  end;

  if v_current_lineage_sequence is null
     or p_lineage_sequence<>v_current_lineage_sequence
     or lower(p_authority_sha)<>lower(v_current.authority_sha)
     or p_authority_ref<>v_current.authority_ref
     or lower(p_workflow_blob_sha)<>lower(v_current.workflow_blob_sha) then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','authority-sync-receipt-current-state-mismatch',
      'expectedLineageSequence',v_current_lineage_sequence,
      'expectedAuthoritySha',lower(v_current.authority_sha)
    );
  end if;

  select * into v_existing
  from foundation.defence_attestation_authority_sync_receipts
  where evidence_ref=p_evidence_ref
  limit 1;

  if v_existing.receipt_sequence is not null then
    if v_existing.lineage_sequence=p_lineage_sequence
       and lower(v_existing.authority_sha)=lower(p_authority_sha)
       and v_existing.authority_ref=p_authority_ref
       and lower(v_existing.workflow_blob_sha)=lower(p_workflow_blob_sha)
       and lower(v_existing.publisher_commit_sha)=lower(p_publisher_commit_sha)
       and lower(v_existing.lineage_blob_sha)=lower(p_lineage_blob_sha)
       and lower(v_existing.authority_contract_blob_sha)=lower(p_authority_contract_blob_sha)
       and v_existing.sync_outcome=p_sync_outcome
       and v_existing.github_run_id=p_github_run_id
       and v_existing.github_run_attempt=p_github_run_attempt
       and v_existing.github_event=p_github_event
       and v_existing.observed_at=p_observed_at then
      return jsonb_build_object(
        'status','replayed',
        'receiptId',v_existing.receipt_id,
        'receiptSequence',v_existing.receipt_sequence
      );
    end if;
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','authority-sync-receipt-evidence-conflict'
    );
  end if;

  insert into foundation.defence_attestation_authority_sync_receipts(
    lineage_sequence,authority_sha,authority_ref,workflow_blob_sha,
    publisher_commit_sha,lineage_blob_sha,authority_contract_blob_sha,
    sync_outcome,github_run_id,github_run_attempt,github_event,
    observed_at,evidence_ref,metadata
  ) values (
    p_lineage_sequence,lower(p_authority_sha),p_authority_ref,lower(p_workflow_blob_sha),
    lower(p_publisher_commit_sha),lower(p_lineage_blob_sha),lower(p_authority_contract_blob_sha),
    p_sync_outcome,p_github_run_id,p_github_run_attempt,p_github_event,
    p_observed_at,p_evidence_ref,p_metadata
  )
  returning receipt_id into v_receipt_id;

  return jsonb_build_object(
    'status','recorded',
    'receiptId',v_receipt_id,
    'lineageSequence',p_lineage_sequence,
    'authoritySha',lower(p_authority_sha),
    'observedAt',p_observed_at
  );
end;
$authority_sync_receipt$;

revoke all on function foundation.record_defence_attestation_authority_sync_receipt_v1(
  bigint,text,text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_attestation_authority_sync_receipt_v1(
  bigint,text,text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb
) to service_role;


create or replace function foundation.get_defence_attestation_authority_sync_summary_v1(
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 5400
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $authority_sync_summary$
declare
  v_current foundation.defence_attestation_authority_activations%rowtype;
  v_current_lineage_sequence bigint;
  v_latest foundation.defence_attestation_authority_sync_receipts%rowtype;
  v_age_seconds bigint;
  v_state text;
  v_reason text;
begin
  if p_as_of is null or p_max_age_seconds<300 or p_max_age_seconds>86400 then
    raise exception 'invalid-attestation-authority-sync-summary-window' using errcode='22023';
  end if;

  select * into v_current
  from foundation.defence_attestation_authority_activations
  order by activated_at desc,activation_sequence desc
  limit 1;

  select * into v_latest
  from foundation.defence_attestation_authority_sync_receipts
  where observed_at<=p_as_of
  order by observed_at desc,receipt_sequence desc
  limit 1;

  v_current_lineage_sequence := case
    when v_current.activation_kind='bootstrap' then 1
    when coalesce(v_current.metadata->>'lineageSequence','') ~ '^[0-9]{1,18}$'
      then (v_current.metadata->>'lineageSequence')::bigint
    else null
  end;

  v_age_seconds := case
    when v_latest.receipt_sequence is null then null
    else greatest(0,floor(extract(epoch from (p_as_of-v_latest.observed_at)))::bigint)
  end;

  if v_current.activation_sequence is null then
    v_state := 'warning';
    v_reason := 'active-attestation-authority-missing';
  elsif v_latest.receipt_sequence is null then
    v_state := 'warning';
    v_reason := 'attestation-authority-sync-receipt-missing';
  elsif v_latest.lineage_sequence<>v_current_lineage_sequence
     or lower(v_latest.authority_sha)<>lower(v_current.authority_sha)
     or v_latest.authority_ref<>v_current.authority_ref
     or lower(v_latest.workflow_blob_sha)<>lower(v_current.workflow_blob_sha) then
    v_state := 'warning';
    v_reason := 'attestation-authority-sync-receipt-mismatch';
  elsif v_age_seconds>p_max_age_seconds then
    v_state := 'warning';
    v_reason := 'attestation-authority-sync-receipt-stale';
  else
    v_state := 'pass';
    v_reason := 'attestation-authority-sync-current';
  end if;

  return jsonb_build_object(
    'defenceAttestationAuthoritySync','shine-defence/attestation-authority-sync-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'reasonCode',v_reason,
    'maxAgeSeconds',p_max_age_seconds,
    'receiptAgeSeconds',v_age_seconds,
    'currentAuthority',case
      when v_current.activation_sequence is null then null
      else jsonb_build_object(
        'lineageSequence',v_current_lineage_sequence,
        'authoritySha',lower(v_current.authority_sha),
        'authorityRef',v_current.authority_ref,
        'workflowBlobSha',lower(v_current.workflow_blob_sha),
        'activationKind',v_current.activation_kind,
        'activatedAt',v_current.activated_at
      )
    end,
    'latestReceipt',case
      when v_latest.receipt_sequence is null then null
      else jsonb_build_object(
        'receiptId',v_latest.receipt_id,
        'lineageSequence',v_latest.lineage_sequence,
        'authoritySha',lower(v_latest.authority_sha),
        'publisherCommitSha',lower(v_latest.publisher_commit_sha),
        'lineageBlobSha',lower(v_latest.lineage_blob_sha),
        'authorityContractBlobSha',lower(v_latest.authority_contract_blob_sha),
        'syncOutcome',v_latest.sync_outcome,
        'githubRunId',v_latest.github_run_id,
        'githubRunAttempt',v_latest.github_run_attempt,
        'githubEvent',v_latest.github_event,
        'observedAt',v_latest.observed_at
      )
    end,
    'evaluatedAt',p_as_of
  );
end;
$authority_sync_summary$;

revoke all on function foundation.get_defence_attestation_authority_sync_summary_v1(
  timestamptz,integer
) from public,anon,authenticated;
grant execute on function foundation.get_defence_attestation_authority_sync_summary_v1(
  timestamptz,integer
) to foundation_runtime,shine_defence_runtime,service_role;
