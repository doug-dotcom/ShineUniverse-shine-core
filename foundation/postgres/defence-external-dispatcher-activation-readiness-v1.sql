-- Shine Defence external dispatcher activation readiness v1.
-- Extend the existing dispatcher heartbeat vocabulary so credentials may be
-- present while activation readiness remains blocked.
alter table foundation.defence_external_dispatcher_heartbeats
  drop constraint if exists defence_external_dispatcher_heartbeats_outcome_check;

alter table foundation.defence_external_dispatcher_heartbeats
  add constraint defence_external_dispatcher_heartbeats_outcome_check
  check (
    outcome in (
      'ready_idle','ready_dispatched','ready_partial_failure',
      'disabled_missing_credentials','disabled_activation_not_ready','failed'
    )
  );

-- Validates GitHub App identity, installation permissions and repository coverage
-- without dispatching any workflow.

create table if not exists foundation.defence_external_dispatcher_readiness_receipts (
  receipt_sequence bigint generated always as identity primary key,
  receipt_id uuid not null unique,
  app_id text,
  installation_id text,
  credentials_present boolean not null,
  app_identity_verified boolean not null,
  installation_token_issued boolean not null,
  actions_write_confirmed boolean not null,
  repository_coverage_complete boolean not null,
  required_repository_count integer not null check (required_repository_count between 1 and 100),
  covered_repository_count integer not null check (covered_repository_count between 0 and 100),
  missing_repository_ids jsonb not null default '[]'::jsonb
    check (jsonb_typeof(missing_repository_ids)='array'),
  outcome text not null check (
    outcome in (
      'ready',
      'missing_credentials',
      'invalid_app_identity',
      'installation_token_failed',
      'permission_gap',
      'repository_gap',
      'failed'
    )
  ),
  token_expires_at timestamptz,
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default now(),
  check (valid_until>observed_at),
  check (app_id is null or app_id ~ '^[0-9]{1,20}$'),
  check (installation_id is null or installation_id ~ '^[0-9]{1,20}$')
);

create index if not exists defence_external_dispatcher_readiness_time_idx
  on foundation.defence_external_dispatcher_readiness_receipts(observed_at desc);


create or replace function foundation.issue_defence_external_dispatcher_readiness_lease_v1(
  p_as_of timestamptz default now(),
  p_ttl_seconds integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,foundation,extensions
as $issue_dispatcher_readiness_lease$
declare
  v_lease_id uuid := gen_random_uuid();
  v_token text;
  v_token_sha256 text;
  v_expires_at timestamptz;
begin
  if p_as_of is null
     or p_ttl_seconds<30
     or p_ttl_seconds>300 then
    raise exception 'invalid-defence-dispatcher-readiness-lease-policy'
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
      'contract','shine-defence/external-dispatcher-readiness-lease-v1',
      'purpose','activation_readiness',
      'tokenStored',false
    )
  );

  return jsonb_build_object(
    'contract','shine-defence/external-dispatcher-readiness-lease-v1',
    'schemaVersion','1.0.0',
    'leaseId',v_lease_id,
    'leaseToken',v_token,
    'issuedAt',p_as_of,
    'expiresAt',v_expires_at,
    'singleUse',true,
    'purpose','activation_readiness'
  );
end;
$issue_dispatcher_readiness_lease$;


create or replace function foundation.claim_defence_external_dispatcher_readiness_lease_v1(
  p_lease_id uuid,
  p_lease_token text,
  p_execution_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,foundation,extensions
as $claim_dispatcher_readiness_lease$
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
    raise exception 'invalid-defence-dispatcher-readiness-lease-claim'
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
    and metadata->>'purpose'='activation_readiness'
  returning * into v_claimed;

  if v_claimed.lease_id is null then
    return jsonb_build_object(
      'contract','shine-defence/external-dispatcher-readiness-lease-claim-v1',
      'schemaVersion','1.0.0',
      'status','rejected',
      'leaseId',p_lease_id,
      'reasonCode','lease-invalid-expired-used-or-wrong-purpose'
    );
  end if;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatcher-readiness-lease-claim-v1',
    'schemaVersion','1.0.0',
    'status','accepted',
    'leaseId',v_claimed.lease_id,
    'claimedAt',v_claimed.claimed_at,
    'expiresAt',v_claimed.expires_at,
    'executionId',v_claimed.claim_execution_id
  );
end;
$claim_dispatcher_readiness_lease$;


create or replace function foundation.get_defence_external_dispatcher_required_repositories_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog,foundation
as $required_dispatcher_repositories$
  with repos as (
    select
      'core'::text as target_id,
      'doug-dotcom/ShineUniverse-shine-core'::text as repository,
      '1072897952'::text as repository_id,
      0 as sort_order
    union all
    select
      t.target_id,
      t.metadata->>'sourceRepository' as repository,
      t.metadata->>'sourceRepositoryId' as repository_id,
      1 as sort_order
    from foundation.defence_estate_targets t
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select jsonb_build_object(
    'contract','shine-defence/external-dispatcher-required-repositories-v1',
    'schemaVersion','1.0.0',
    'requiredRepositoryCount',count(*)::integer,
    'repositories',
      jsonb_agg(
        jsonb_build_object(
          'targetId',target_id,
          'repository',repository,
          'repositoryId',repository_id
        )
        order by sort_order,target_id
      )
  )
  from repos
  where repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
    and repository_id ~ '^[0-9]{1,20}$';
$required_dispatcher_repositories$;


create or replace function foundation.record_defence_external_dispatcher_readiness_v1(
  p_receipt_id uuid,
  p_app_id text,
  p_installation_id text,
  p_credentials_present boolean,
  p_app_identity_verified boolean,
  p_installation_token_issued boolean,
  p_actions_write_confirmed boolean,
  p_repository_coverage_complete boolean,
  p_required_repository_count integer,
  p_covered_repository_count integer,
  p_missing_repository_ids jsonb,
  p_outcome text,
  p_token_expires_at timestamptz,
  p_observed_at timestamptz,
  p_valid_until timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,foundation
as $record_dispatcher_readiness$
declare
  v_sequence bigint;
begin
  if p_receipt_id is null
     or (p_app_id is not null and p_app_id !~ '^[0-9]{1,20}$')
     or (p_installation_id is not null and p_installation_id !~ '^[0-9]{1,20}$')
     or p_credentials_present is null
     or p_app_identity_verified is null
     or p_installation_token_issued is null
     or p_actions_write_confirmed is null
     or p_repository_coverage_complete is null
     or p_required_repository_count<1
     or p_required_repository_count>100
     or p_covered_repository_count<0
     or p_covered_repository_count>p_required_repository_count
     or p_missing_repository_ids is null
     or jsonb_typeof(p_missing_repository_ids)<>'array'
     or p_outcome not in (
       'ready',
       'missing_credentials',
       'invalid_app_identity',
       'installation_token_failed',
       'permission_gap',
       'repository_gap',
       'failed'
     )
     or p_observed_at is null
     or p_valid_until is null
     or p_valid_until<=p_observed_at
     or p_evidence_ref is null
     or char_length(p_evidence_ref)>1024
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-defence-external-dispatcher-readiness'
      using errcode='22023';
  end if;

  if p_outcome='ready' and (
    not p_credentials_present
    or not p_app_identity_verified
    or not p_installation_token_issued
    or not p_actions_write_confirmed
    or not p_repository_coverage_complete
    or p_covered_repository_count<>p_required_repository_count
    or jsonb_array_length(p_missing_repository_ids)<>0
    or p_metadata->>'workflowAccessComplete' is distinct from 'true'
  ) then
    raise exception 'invalid-ready-dispatcher-readiness'
      using errcode='22023';
  end if;

  insert into foundation.defence_external_dispatcher_readiness_receipts(
    receipt_id,app_id,installation_id,credentials_present,
    app_identity_verified,installation_token_issued,
    actions_write_confirmed,repository_coverage_complete,
    required_repository_count,covered_repository_count,
    missing_repository_ids,outcome,token_expires_at,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    p_receipt_id,p_app_id,p_installation_id,p_credentials_present,
    p_app_identity_verified,p_installation_token_issued,
    p_actions_write_confirmed,p_repository_coverage_complete,
    p_required_repository_count,p_covered_repository_count,
    p_missing_repository_ids,p_outcome,p_token_expires_at,
    p_observed_at,p_valid_until,p_evidence_ref,p_metadata
  )
  on conflict (evidence_ref) do nothing
  returning receipt_sequence into v_sequence;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatcher-readiness-receipt-v1',
    'schemaVersion','1.0.0',
    'status',case when v_sequence is null then 'replayed' else 'recorded' end,
    'receiptSequence',v_sequence,
    'receiptId',p_receipt_id,
    'outcome',p_outcome,
    'ready',p_outcome='ready'
  );
end;
$record_dispatcher_readiness$;


create or replace function foundation.get_defence_external_dispatcher_activation_readiness_v1(
  p_as_of timestamptz default now(),
  p_fresh_seconds integer default 3600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $dispatcher_activation_readiness$
declare
  v_latest foundation.defence_external_dispatcher_readiness_receipts%rowtype;
  v_state text;
  v_age integer;
begin
  if p_as_of is null
     or p_fresh_seconds<600
     or p_fresh_seconds>7200 then
    raise exception 'invalid-defence-dispatcher-activation-readiness-policy'
      using errcode='22023';
  end if;

  select * into v_latest
  from foundation.defence_external_dispatcher_readiness_receipts
  where observed_at<=p_as_of
  order by observed_at desc,receipt_sequence desc
  limit 1;

  if v_latest.receipt_id is null then
    v_state := 'missing';
    v_age := null;
  else
    v_age := greatest(
      0,
      floor(extract(epoch from (p_as_of-v_latest.observed_at)))
    )::integer;

    v_state := case
      when v_age>p_fresh_seconds then 'stale'
      when v_latest.outcome='ready' then 'ready'
      when v_latest.outcome='missing_credentials' then 'not_configured'
      else 'blocked'
    end;
  end if;

  return jsonb_build_object(
    'contract','shine-defence/external-dispatcher-activation-readiness-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'freshSeconds',p_fresh_seconds,
    'requiredRepositories',
      foundation.get_defence_external_dispatcher_required_repositories_v1(),
    'latestReceipt',case
      when v_latest.receipt_id is null then null
      else jsonb_build_object(
        'receiptId',v_latest.receipt_id,
        'appId',v_latest.app_id,
        'installationId',v_latest.installation_id,
        'credentialsPresent',v_latest.credentials_present,
        'appIdentityVerified',v_latest.app_identity_verified,
        'installationTokenIssued',v_latest.installation_token_issued,
        'actionsWriteConfirmed',v_latest.actions_write_confirmed,
        'repositoryCoverageComplete',v_latest.repository_coverage_complete,
        'requiredRepositoryCount',v_latest.required_repository_count,
        'coveredRepositoryCount',v_latest.covered_repository_count,
        'missingRepositoryIds',v_latest.missing_repository_ids,
        'outcome',v_latest.outcome,
        'tokenExpiresAt',v_latest.token_expires_at,
        'observedAt',v_latest.observed_at,
        'validUntil',v_latest.valid_until,
        'ageSeconds',v_age,
        'metadata',v_latest.metadata
      )
    end,
    'activationRequiresState','ready',
    'credentialValueExposed',false,
    'readinessCheckDispatchesWorkflow',false,
    'workflowOidcRemainsAuthoritative',true,
    'evaluatedAt',p_as_of
  );
end;
$dispatcher_activation_readiness$;


revoke all on table foundation.defence_external_dispatcher_readiness_receipts
  from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.issue_defence_external_dispatcher_readiness_lease_v1(
  timestamptz,integer
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.claim_defence_external_dispatcher_readiness_lease_v1(
  uuid,text,text,timestamptz
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.record_defence_external_dispatcher_readiness_v1(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,integer,integer,jsonb,text,timestamptz,timestamptz,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

revoke all on function foundation.get_defence_external_dispatcher_required_repositories_v1()
  from public,anon,authenticated,foundation_gateway;

revoke all on function foundation.get_defence_external_dispatcher_activation_readiness_v1(
  timestamptz,integer
) from public,anon,authenticated,foundation_gateway;

grant execute on function foundation.issue_defence_external_dispatcher_readiness_lease_v1(
  timestamptz,integer
) to service_role;

grant execute on function foundation.claim_defence_external_dispatcher_readiness_lease_v1(
  uuid,text,text,timestamptz
) to service_role;

grant execute on function foundation.record_defence_external_dispatcher_readiness_v1(
  uuid,text,text,boolean,boolean,boolean,boolean,boolean,integer,integer,jsonb,text,timestamptz,timestamptz,timestamptz,text,jsonb
) to service_role;

grant execute on function foundation.get_defence_external_dispatcher_required_repositories_v1()
  to foundation_runtime,shine_defence_runtime,service_role;

grant execute on function foundation.get_defence_external_dispatcher_activation_readiness_v1(
  timestamptz,integer
) to foundation_runtime,shine_defence_runtime,service_role;
