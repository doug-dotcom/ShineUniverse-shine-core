-- Shine Defence external attestation dispatcher v1.
-- Supabase-driven trigger plane for GitHub workflow_dispatch.
-- Triggering is not evidence: repo-bound GitHub Actions OIDC remains authoritative.

create table if not exists foundation.defence_external_dispatch_leases (
  lease_id uuid primary key,
  token_sha256 text not null unique
    check (token_sha256 ~ '^[a-f0-9]{64}$'),
  issued_at timestamptz not null,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claim_execution_id text,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (expires_at > issued_at),
  check (metadata is not null and jsonb_typeof(metadata)='object')
);

create index if not exists defence_external_dispatch_leases_expiry_idx
  on foundation.defence_external_dispatch_leases(expires_at);


create table if not exists foundation.defence_external_dispatch_events (
  event_sequence bigint generated always as identity primary key,
  event_id uuid not null unique,
  dispatch_kind text not null
    check (dispatch_kind in ('authority_refresh','rollback_refresh')),
  target_id text,
  repository text not null
    check (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  workflow_path text not null
    check (workflow_path ~ '^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$'),
  requested_ref text not null
    check (requested_ref ~ '^[A-Za-z0-9._/-]{1,128}$'),
  reason_code text not null
    check (reason_code ~ '^[a-z0-9][a-z0-9-]{1,127}$'),
  outcome text not null
    check (outcome in ('dispatched','disabled','failed','skipped')),
  github_run_id text,
  http_status integer,
  observed_at timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (
    (dispatch_kind='authority_refresh' and target_id is null)
    or
    (dispatch_kind='rollback_refresh' and target_id ~ '^railway:[a-z0-9][a-z0-9-]*$')
  ),
  check (github_run_id is null or github_run_id ~ '^[0-9]{1,32}$'),
  check (http_status is null or http_status between 100 and 599),
  check (metadata is not null and jsonb_typeof(metadata)='object')
);

create index if not exists defence_external_dispatch_events_target_time_idx
  on foundation.defence_external_dispatch_events(target_id,observed_at desc);

create index if not exists defence_external_dispatch_events_kind_time_idx
  on foundation.defence_external_dispatch_events(dispatch_kind,observed_at desc);


create table if not exists foundation.defence_external_dispatcher_heartbeats (
  heartbeat_sequence bigint generated always as identity primary key,
  heartbeat_id uuid not null unique,
  credentials_ready boolean not null,
  outcome text not null
    check (outcome in ('ready_idle','ready_dispatched','ready_partial_failure','disabled_missing_credentials','failed')),
  observed_at timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (metadata is not null and jsonb_typeof(metadata)='object')
);

create index if not exists defence_external_dispatcher_heartbeats_time_idx
  on foundation.defence_external_dispatcher_heartbeats(observed_at desc);


create or replace function foundation.issue_defence_external_dispatch_lease_v1(
  p_as_of timestamptz default now(),
  p_ttl_seconds integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,foundation,extensions
as $issue_dispatch_lease$
declare
  v_lease_id uuid := gen_random_uuid();
  v_token text;
  v_token_sha256 text;
  v_expires_at timestamptz;
begin
  if p_as_of is null
     or p_ttl_seconds<30
     or p_ttl_seconds>300 then
    raise exception 'invalid-defence-external-dispatch-lease-policy'
      using errcode='22023';
  end if;

  v_token := encode(extensions.gen_random_bytes(32),'hex');
  v_token_sha256 := encode(
    extensions.digest(convert_to(v_token,'UTF8'),'sha256'),
    'hex'
  );
  v_expires_at := p_as_of + make_interval(secs=>p_ttl_seconds);

  insert into foundation.defence_external_dispatch_leases(
    lease_id,token_sha256,issued_at,expires_at,metadata
  ) values (
    v_lease_id,v_token_sha256,p_as_of,v_expires_at,
    jsonb_build_object(
      'contract','shine-defence/external-dispatch-lease-v1',
      'tokenStored',false
    )
  );

  return jsonb_build_object(
    'contract','shine-defence/external-dispatch-lease-v1',
    'schemaVersion','1.0.0',
    'leaseId',v_lease_id,
    'leaseToken',v_token,
    'issuedAt',p_as_of,
    'expiresAt',v_expires_at,
    'singleUse',true
  );
end;
$issue_dispatch_lease$;


create or replace function foundation.claim_defence_external_dispatch_lease_v1(
  p_lease_id uuid,
  p_lease_token text,
  p_execution_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,foundation,extensions
as $claim_dispatch_lease$
declare
  v_token_sha256 text;
  v_claimed foundation.defence_external_dispatch_leases%rowtype;
begin
  if p_lease_id is null
     or p_lease_token is null
     or p_lease_token !~ '^[a-f0-9]{64}$'
     or p_execution_id is null
     or char_length(p_execution_id)<1
     or char_length(p_execution_id)>256
     or p_execution_id ~ '[[:cntrl:]]'
     or p_as_of is null then
    raise exception 'invalid-defence-external-dispatch-lease-claim'
      using errcode='22023';
  end if;

  v_token_sha256 := encode(
    extensions.digest(convert_to(p_lease_token,'UTF8'),'sha256'),
    'hex'
  );

  update foundation.defence_external_dispatch_leases
  set
    claimed_at=p_as_of,
    claim_execution_id=p_execution_id
  where lease_id=p_lease_id
    and token_sha256=v_token_sha256
    and claimed_at is null
    and issued_at<=p_as_of
    and expires_at>p_as_of
  returning * into v_claimed;

  if v_claimed.lease_id is null then
    return jsonb_build_object(
      'contract','shine-defence/external-dispatch-lease-claim-v1',
      'schemaVersion','1.0.0',
      'status','rejected',
      'leaseId',p_lease_id,
      'reasonCode','lease-invalid-expired-or-used'
    );
  end if;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatch-lease-claim-v1',
    'schemaVersion','1.0.0',
    'status','accepted',
    'leaseId',v_claimed.lease_id,
    'claimedAt',v_claimed.claimed_at,
    'expiresAt',v_claimed.expires_at,
    'executionId',v_claimed.claim_execution_id
  );
end;
$claim_dispatch_lease$;


create or replace function foundation.record_defence_external_dispatch_event_v1(
  p_event_id uuid,
  p_dispatch_kind text,
  p_target_id text,
  p_repository text,
  p_workflow_path text,
  p_requested_ref text,
  p_reason_code text,
  p_outcome text,
  p_github_run_id text,
  p_http_status integer,
  p_observed_at timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,foundation
as $record_external_dispatch_event$
declare
  v_sequence bigint;
begin
  if p_event_id is null
     or p_dispatch_kind not in ('authority_refresh','rollback_refresh')
     or p_repository is null
     or p_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
     or p_workflow_path is null
     or p_workflow_path !~ '^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$'
     or p_requested_ref is null
     or p_requested_ref !~ '^[A-Za-z0-9._/-]{1,128}$'
     or p_reason_code is null
     or p_reason_code !~ '^[a-z0-9][a-z0-9-]{1,127}$'
     or p_outcome not in ('dispatched','disabled','failed','skipped')
     or (p_dispatch_kind='authority_refresh' and p_target_id is not null)
     or (p_dispatch_kind='rollback_refresh' and (p_target_id is null or p_target_id !~ '^railway:[a-z0-9][a-z0-9-]*$'))
     or (p_github_run_id is not null and p_github_run_id !~ '^[0-9]{1,32}$')
     or (p_http_status is not null and (p_http_status<100 or p_http_status>599))
     or p_observed_at is null
     or p_evidence_ref is null
     or char_length(p_evidence_ref)>1024
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-defence-external-dispatch-event'
      using errcode='22023';
  end if;

  insert into foundation.defence_external_dispatch_events(
    event_id,dispatch_kind,target_id,repository,workflow_path,requested_ref,
    reason_code,outcome,github_run_id,http_status,observed_at,evidence_ref,metadata
  ) values (
    p_event_id,p_dispatch_kind,p_target_id,p_repository,p_workflow_path,p_requested_ref,
    p_reason_code,p_outcome,p_github_run_id,p_http_status,p_observed_at,p_evidence_ref,
    p_metadata
  )
  on conflict (evidence_ref) do nothing
  returning event_sequence into v_sequence;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatch-event-v1',
    'schemaVersion','1.0.0',
    'status',case when v_sequence is null then 'replayed' else 'recorded' end,
    'eventSequence',v_sequence,
    'eventId',p_event_id,
    'dispatchKind',p_dispatch_kind,
    'targetId',p_target_id,
    'outcome',p_outcome,
    'githubRunId',p_github_run_id
  );
end;
$record_external_dispatch_event$;


create or replace function foundation.record_defence_external_dispatcher_heartbeat_v1(
  p_heartbeat_id uuid,
  p_credentials_ready boolean,
  p_outcome text,
  p_observed_at timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,foundation
as $record_external_dispatcher_heartbeat$
declare
  v_sequence bigint;
begin
  if p_heartbeat_id is null
     or p_credentials_ready is null
     or p_outcome not in (
       'ready_idle','ready_dispatched','ready_partial_failure',
       'disabled_missing_credentials','failed'
     )
     or p_observed_at is null
     or p_evidence_ref is null
     or char_length(p_evidence_ref)>1024
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-defence-external-dispatcher-heartbeat'
      using errcode='22023';
  end if;

  insert into foundation.defence_external_dispatcher_heartbeats(
    heartbeat_id,credentials_ready,outcome,observed_at,evidence_ref,metadata
  ) values (
    p_heartbeat_id,p_credentials_ready,p_outcome,p_observed_at,p_evidence_ref,p_metadata
  )
  on conflict (evidence_ref) do nothing
  returning heartbeat_sequence into v_sequence;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatcher-heartbeat-v1',
    'schemaVersion','1.0.0',
    'status',case when v_sequence is null then 'replayed' else 'recorded' end,
    'heartbeatSequence',v_sequence,
    'heartbeatId',p_heartbeat_id,
    'credentialsReady',p_credentials_ready,
    'outcome',p_outcome
  );
end;
$record_external_dispatcher_heartbeat$;


create or replace function foundation.get_defence_external_dispatch_plan_v1(
  p_as_of timestamptz default now(),
  p_refresh_margin_seconds integer default 3600,
  p_dispatch_cooldown_seconds integer default 900
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $external_dispatch_plan$
declare
  v_authority jsonb;
  v_authority_age integer;
  v_authority_due boolean := false;
  v_authority_recent boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
begin
  if p_as_of is null
     or p_refresh_margin_seconds<600
     or p_refresh_margin_seconds>4800
     or p_dispatch_cooldown_seconds<300
     or p_dispatch_cooldown_seconds>3600 then
    raise exception 'invalid-defence-external-dispatch-plan-policy'
      using errcode='22023';
  end if;

  v_authority :=
    foundation.get_defence_attestation_authority_sync_summary_v1(
      p_as_of,5400
    );
  v_authority_age := nullif(v_authority->>'receiptAgeSeconds','')::integer;

  select exists(
    select 1
    from foundation.defence_external_dispatch_events e
    where e.dispatch_kind='authority_refresh'
      and e.outcome='dispatched'
      and e.observed_at>p_as_of-make_interval(secs=>p_dispatch_cooldown_seconds)
  ) into v_authority_recent;

  v_authority_due :=
    not v_authority_recent
    and (
      v_authority->>'state'<>'pass'
      or v_authority_age is null
      or v_authority_age >= greatest(0,5400-p_refresh_margin_seconds)
    );

  if v_authority_due then
    return jsonb_build_object(
      'contract','shine-defence/external-dispatch-plan-v1',
      'schemaVersion','1.0.0',
      'phase','authority_first',
      'itemCount',1,
      'items',jsonb_build_array(
        jsonb_build_object(
          'dispatchKind','authority_refresh',
          'targetId',null,
          'repository','doug-dotcom/ShineUniverse-shine-core',
          'repositoryId','1072897952',
          'workflowPath','.github/workflows/shine-defence-authority-state.yml',
          'ref','main',
          'reasonCode',case
            when v_authority->>'state'<>'pass'
              then 'authority-heartbeat-not-current'
            else 'authority-heartbeat-refresh-margin'
          end
        )
      ),
      'authorityState',v_authority->>'state',
      'authorityReceiptAgeSeconds',v_authority_age,
      'authorityFirst',true,
      'triggerIsEvidence',false,
      'evaluatedAt',p_as_of
    );
  end if;

  with candidates as (
    select
      t.target_id,
      t.metadata->>'sourceRepository' as repository,
      t.metadata->>'sourceRepositoryId' as repository_id,
      a.rollback_commit_sha,
      proof.observation_id,
      proof.source_available,
      proof.valid_until,
      recent.recent_dispatch
    from foundation.defence_estate_targets t
    join foundation.current_defence_release_admission a
      using(target_id)
    left join lateral (
      select
        r.observation_id,
        r.source_available,
        r.valid_until
      from foundation.defence_rollback_source_attestations r
      where r.target_id=t.target_id
        and a.rollback_commit_sha is not null
        and (
          (
            r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
          )
          or (
            r.canonical_commit_sha=a.rollback_commit_sha
            and r.canonical_source_available is true
          )
        )
      order by
        case
          when r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
            then 0
          else 1
        end,
        r.observed_at desc,
        r.recorded_at desc,
        r.observation_id desc
      limit 1
    ) proof on true
    left join lateral (
      select exists(
        select 1
        from foundation.defence_external_dispatch_events e
        where e.dispatch_kind='rollback_refresh'
          and e.target_id=t.target_id
          and e.outcome='dispatched'
          and e.observed_at>p_as_of-make_interval(secs=>p_dispatch_cooldown_seconds)
      ) as recent_dispatch
    ) recent on true
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
      and a.rollback_commit_sha is not null
  ),
  due as (
    select *,
      case
        when observation_id is null then 'rollback-source-proof-missing'
        when not coalesce(source_available,false) then 'rollback-source-proof-unavailable'
        when valid_until<=p_as_of then 'rollback-source-proof-stale'
        else 'rollback-source-proof-refresh-margin'
      end as reason_code
    from candidates
    where not recent_dispatch
      and (
        observation_id is null
        or not coalesce(source_available,false)
        or valid_until<=p_as_of+make_interval(secs=>p_refresh_margin_seconds)
      )
      and repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
      and repository_id ~ '^[0-9]{1,20}$'
  )
  select
    count(*)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'dispatchKind','rollback_refresh',
          'targetId',target_id,
          'repository',repository,
          'repositoryId',repository_id,
          'workflowPath','.github/workflows/shine-defence-release-head.yml',
          'ref','main',
          'reasonCode',reason_code,
          'proofValidUntil',valid_until
        )
        order by target_id
      ),
      '[]'::jsonb
    )
  into v_count,v_items
  from due;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatch-plan-v1',
    'schemaVersion','1.0.0',
    'phase',case when v_count>0 then 'rollback_refresh' else 'idle' end,
    'itemCount',v_count,
    'items',v_items,
    'authorityState',v_authority->>'state',
    'authorityReceiptAgeSeconds',v_authority_age,
    'authorityFirst',true,
    'triggerIsEvidence',false,
    'evaluatedAt',p_as_of
  );
end;
$external_dispatch_plan$;


create or replace function foundation.get_defence_external_dispatcher_summary_v1(
  p_as_of timestamptz default now(),
  p_fresh_seconds integer default 1800
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $external_dispatcher_summary$
declare
  v_latest foundation.defence_external_dispatcher_heartbeats%rowtype;
  v_state text;
  v_age integer;
begin
  if p_as_of is null
     or p_fresh_seconds<300
     or p_fresh_seconds>7200 then
    raise exception 'invalid-defence-external-dispatcher-summary-policy'
      using errcode='22023';
  end if;

  select * into v_latest
  from foundation.defence_external_dispatcher_heartbeats
  where observed_at<=p_as_of
  order by observed_at desc,heartbeat_sequence desc
  limit 1;

  if v_latest.heartbeat_id is null then
    v_state := 'missing';
    v_age := null;
  else
    v_age := greatest(
      0,
      floor(extract(epoch from (p_as_of-v_latest.observed_at)))
    )::integer;
    v_state := case
      when v_age>p_fresh_seconds then 'stale'
      when not v_latest.credentials_ready then 'disabled'
      when v_latest.outcome='failed' then 'warning'
      when v_latest.outcome='ready_partial_failure' then 'warning'
      else 'pass'
    end;
  end if;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatcher-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'freshSeconds',p_fresh_seconds,
    'latestHeartbeat',case
      when v_latest.heartbeat_id is null then null
      else jsonb_build_object(
        'heartbeatId',v_latest.heartbeat_id,
        'credentialsReady',v_latest.credentials_ready,
        'outcome',v_latest.outcome,
        'observedAt',v_latest.observed_at,
        'ageSeconds',v_age,
        'metadata',v_latest.metadata
      )
    end,
    'dispatcherCanMintProof',false,
    'dispatcherCanExtendProofTtl',false,
    'workflowOidcRemainsAuthoritative',true,
    'evaluatedAt',p_as_of
  );
end;
$external_dispatcher_summary$;


revoke all on table foundation.defence_external_dispatch_leases
  from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;
revoke all on table foundation.defence_external_dispatch_events
  from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;
revoke all on table foundation.defence_external_dispatcher_heartbeats
  from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.issue_defence_external_dispatch_lease_v1(
  timestamptz,integer
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.claim_defence_external_dispatch_lease_v1(
  uuid,text,text,timestamptz
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.record_defence_external_dispatch_event_v1(
  uuid,text,text,text,text,text,text,text,text,integer,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.record_defence_external_dispatcher_heartbeat_v1(
  uuid,boolean,text,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.get_defence_external_dispatch_plan_v1(
  timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway;

revoke all on function foundation.get_defence_external_dispatcher_summary_v1(
  timestamptz,integer
) from public,anon,authenticated,foundation_gateway;

grant execute on function foundation.get_defence_external_dispatch_plan_v1(
  timestamptz,integer,integer
) to foundation_runtime,shine_defence_runtime,service_role;

grant execute on function foundation.get_defence_external_dispatcher_summary_v1(
  timestamptz,integer
) to foundation_runtime,shine_defence_runtime,service_role;

grant execute on function foundation.issue_defence_external_dispatch_lease_v1(
  timestamptz,integer
) to service_role;

grant execute on function foundation.claim_defence_external_dispatch_lease_v1(
  uuid,text,text,timestamptz
) to service_role;

grant execute on function foundation.record_defence_external_dispatch_event_v1(
  uuid,text,text,text,text,text,text,text,text,integer,timestamptz,text,jsonb
) to service_role;

grant execute on function foundation.record_defence_external_dispatcher_heartbeat_v1(
  uuid,boolean,text,timestamptz,text,jsonb
) to service_role;
