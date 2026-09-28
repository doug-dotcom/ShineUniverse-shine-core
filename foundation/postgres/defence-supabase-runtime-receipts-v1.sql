-- Shine Defence credential-free Supabase runtime receipts v1.
-- Each protected Supabase project exposes a tiny public receipt function.
-- Defence validates project identity, the platform-assigned function ID/version,
-- region, and database reachability before refreshing estate freshness.

create table foundation.defence_supabase_runtime_receipt_observations (
  observation_id uuid primary key default gen_random_uuid(),
  target_id text not null references foundation.defence_estate_targets(target_id),
  project_ref text not null check (project_ref ~ '^[a-z]{20}$'),
  function_deployment_id text not null,
  function_id uuid not null,
  function_version integer not null check (function_version >= 1),
  region text not null check (region ~ '^[a-z]{2}-[a-z]+-[0-9]+$'),
  execution_id uuid,
  database_reachable boolean not null,
  database_server_version text,
  database_name text,
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (valid_until > observed_at),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_supabase_runtime_receipt_observations enable row level security;

create policy shine_defence_runtime_supabase_receipts_select
on foundation.defence_supabase_runtime_receipt_observations
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_supabase_runtime_receipt_observations
  from public,anon,authenticated;
grant select on foundation.defence_supabase_runtime_receipt_observations
  to shine_defence_runtime,service_role;
grant insert on foundation.defence_supabase_runtime_receipt_observations
  to service_role;

create index defence_supabase_runtime_receipts_target_time_idx
  on foundation.defence_supabase_runtime_receipt_observations(
    target_id,observed_at desc,recorded_at desc
  );

create trigger defence_supabase_runtime_receipts_append_only
before update or delete on foundation.defence_supabase_runtime_receipt_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_supabase_runtime_receipts
with (security_invoker=true)
as
select distinct on (target_id)
  observation_id,target_id,project_ref,function_deployment_id,function_id,
  function_version,region,execution_id,database_reachable,
  database_server_version,database_name,observed_at,valid_until,
  evidence_ref,metadata,recorded_at
from foundation.defence_supabase_runtime_receipt_observations
order by target_id,observed_at desc,recorded_at desc,observation_id desc;

revoke all on foundation.current_defence_supabase_runtime_receipts
  from public,anon,authenticated;
grant select on foundation.current_defence_supabase_runtime_receipts
  to shine_defence_runtime,service_role;


update foundation.defence_estate_targets
set metadata = metadata || case target_id
  when 'supabase:sjpxqeyewahraxvidvcc' then jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',now(),
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','d4ab1238-d400-4ea3-9b13-0dac202d19c6',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256','9fed72a756b40a0cea1987f844b1d531d76c3923cca16246ec09d1bb24618d13',
    'projectRegion','ap-southeast-2'
  )
  when 'supabase:raxfwycrnviwxxzykhfq' then jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',now(),
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','fb65fb06-2e8b-48ac-a801-1f3154c041ef',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256','9fed72a756b40a0cea1987f844b1d531d76c3923cca16246ec09d1bb24618d13',
    'projectRegion','ap-south-1'
  )
  when 'supabase:isluulaquwvtzlwkakyq' then jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',now(),
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','4428c2de-971c-48e7-aba5-93a1c67634cb',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256','9fed72a756b40a0cea1987f844b1d531d76c3923cca16246ec09d1bb24618d13',
    'projectRegion','ap-southeast-2'
  )
  when 'supabase:lqicznkysqqxbrmtxmms' then jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',now(),
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','f8549fee-49ca-4eb4-af0f-b63bf17ae1d3',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256','9fed72a756b40a0cea1987f844b1d531d76c3923cca16246ec09d1bb24618d13',
    'projectRegion','ap-southeast-2'
  )
  when 'supabase:ojpfpgikbqzsmuukljad' then jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',now(),
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','9c623e9e-b3d8-4cc2-a785-096bc3c3f17e',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256','9fed72a756b40a0cea1987f844b1d531d76c3923cca16246ec09d1bb24618d13',
    'projectRegion','ap-southeast-2'
  )
  when 'supabase:kkdgibknfcnoyondnmdb' then jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',now(),
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','5736b175-ffb2-40ff-a74f-90fae0d14471',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256','9fed72a756b40a0cea1987f844b1d531d76c3923cca16246ec09d1bb24618d13',
    'projectRegion','ap-southeast-2'
  )
  else '{}'::jsonb
end,
updated_at=now()
where provider='supabase'
  and lifecycle='active'
  and target_id in (
    'supabase:sjpxqeyewahraxvidvcc',
    'supabase:raxfwycrnviwxxzykhfq',
    'supabase:isluulaquwvtzlwkakyq',
    'supabase:lqicznkysqqxbrmtxmms',
    'supabase:ojpfpgikbqzsmuukljad',
    'supabase:kkdgibknfcnoyondnmdb'
  );


create table foundation.defence_supabase_runtime_receipt_requests (
  request_id uuid primary key default gen_random_uuid(),
  target_id text not null references foundation.defence_estate_targets(target_id),
  external_request_id bigint unique,
  target_url text not null check (target_url ~ '^https://'),
  queued_at timestamptz not null default now(),
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_supabase_runtime_receipt_requests enable row level security;

create policy shine_defence_runtime_supabase_receipt_requests_select
on foundation.defence_supabase_runtime_receipt_requests
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_supabase_runtime_receipt_requests
  from public,anon,authenticated;
grant select on foundation.defence_supabase_runtime_receipt_requests
  to shine_defence_runtime,service_role;
grant insert on foundation.defence_supabase_runtime_receipt_requests
  to service_role;

create index defence_supabase_runtime_receipt_requests_target_idx
  on foundation.defence_supabase_runtime_receipt_requests(target_id,queued_at desc);

create trigger defence_supabase_runtime_receipt_requests_append_only
before update or delete on foundation.defence_supabase_runtime_receipt_requests
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.record_defence_supabase_runtime_receipt_v1(
  p_target_id text,
  p_payload jsonb,
  p_http_status integer,
  p_observed_at timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_project_ref text;
  v_deployment_id text;
  v_function_id uuid;
  v_function_version integer;
  v_region text;
  v_execution_id uuid;
  v_database_reachable boolean;
  v_server_version text;
  v_database_name text;
  v_expected_function_id uuid;
  v_expected_version integer;
  v_expected_region text;
  v_valid_until timestamptz;
  v_evidence_ref text;
  v_receipt_id uuid;
  v_estate_id uuid;
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','supabase-runtime-receipt-invalid-json',
      'targetId',p_target_id
    );
  end if;

  select * into v_target
  from foundation.defence_estate_targets
  where target_id=p_target_id
    and provider='supabase'
    and lifecycle='active';

  if v_target.target_id is null then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','supabase-runtime-receipt-target-invalid',
      'targetId',p_target_id
    );
  end if;

  if p_payload->>'contract'<>'shine-defence/supabase-runtime-receipt-v1'
     or p_payload->>'schemaVersion'<>'1.0.0'
     or p_payload->>'provider'<>'supabase'
     or coalesce((p_payload->>'identityOk')::boolean,false) is not true then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','supabase-runtime-receipt-contract-mismatch',
      'targetId',p_target_id
    );
  end if;

  v_project_ref := p_payload->>'projectRef';
  v_deployment_id := p_payload#>>'{function,deploymentId}';
  v_function_id := nullif(p_payload#>>'{function,functionId}','')::uuid;
  v_function_version := nullif(p_payload#>>'{function,version}','')::integer;
  v_region := p_payload#>>'{function,region}';
  v_execution_id := nullif(p_payload#>>'{function,executionId}','')::uuid;
  v_database_reachable := coalesce((p_payload#>>'{database,reachable}')::boolean,false);
  v_server_version := nullif(p_payload#>>'{database,serverVersion}','');
  v_database_name := nullif(p_payload#>>'{database,databaseName}','');
  v_expected_function_id := nullif(v_target.metadata->>'receiptFunctionId','')::uuid;
  v_expected_version := nullif(v_target.metadata->>'approvedReceiptVersion','')::integer;
  v_expected_region := v_target.metadata->>'projectRegion';

  if v_project_ref is null
     or v_project_ref<>v_target.provider_project_ref
     or v_deployment_id is null
     or v_deployment_id !~ (
       '^' || v_target.provider_project_ref ||
       '_[0-9a-fA-F-]{36}_[0-9]+$'
     )
     or v_function_id is null
     or v_function_id<>v_expected_function_id
     or v_function_version is null
     or v_function_version<>v_expected_version
     or v_region is null
     or v_region<>v_expected_region then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','supabase-runtime-receipt-identity-mismatch',
      'targetId',p_target_id
    );
  end if;

  if split_part(v_deployment_id,'_',1)<>v_project_ref
     or split_part(v_deployment_id,'_',2)<>v_function_id::text
     or split_part(v_deployment_id,'_',3)<>v_function_version::text then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','supabase-runtime-receipt-deployment-mismatch',
      'targetId',p_target_id
    );
  end if;

  if v_database_reachable and p_http_status<>200 then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','supabase-runtime-receipt-status-mismatch',
      'targetId',p_target_id
    );
  end if;

  if not v_database_reachable and p_http_status<>503 then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','supabase-runtime-receipt-status-mismatch',
      'targetId',p_target_id
    );
  end if;

  v_valid_until := p_observed_at + interval '15 minutes';
  v_evidence_ref :=
    'supabase-runtime-receipt:' || p_target_id || ':' ||
    v_deployment_id || ':' || extract(epoch from p_observed_at)::bigint::text;

  insert into foundation.defence_supabase_runtime_receipt_observations(
    target_id,project_ref,function_deployment_id,function_id,function_version,
    region,execution_id,database_reachable,database_server_version,database_name,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    p_target_id,v_project_ref,v_deployment_id,v_function_id,v_function_version,
    v_region,v_execution_id,v_database_reachable,v_server_version,v_database_name,
    p_observed_at,v_valid_until,v_evidence_ref,
    jsonb_build_object(
      'contract','shine-defence/supabase-runtime-receipt-v1',
      'httpStatus',p_http_status,
      'receiptFunction',v_target.metadata->>'receiptFunction',
      'receiptArtifactSha256',v_target.metadata->>'receiptArtifactSha256'
    )
  )
  on conflict (evidence_ref) do nothing
  returning observation_id into v_receipt_id;

  if v_receipt_id is null then
    return jsonb_build_object(
      'status','already-recorded',
      'targetId',p_target_id,
      'deploymentId',v_deployment_id
    );
  end if;

  v_estate_id := foundation.record_defence_estate_observation_v1(
    p_target_id,
    'active',
    case when v_database_reachable then 'healthy' else 'unhealthy' end,
    v_deployment_id,
    v_function_version::text,
    null,
    p_observed_at,
    v_valid_until,
    'runtime-self-report',
    v_evidence_ref,
    jsonb_build_object(
      'collector','shine-defence/supabase-runtime-receipt-v1',
      'projectRef',v_project_ref,
      'region',v_region,
      'functionId',v_function_id,
      'databaseServerVersion',v_server_version,
      'databaseName',v_database_name
    )
  );

  return jsonb_build_object(
    'status','recorded',
    'targetId',p_target_id,
    'projectRef',v_project_ref,
    'deploymentId',v_deployment_id,
    'functionId',v_function_id,
    'functionVersion',v_function_version,
    'region',v_region,
    'databaseReachable',v_database_reachable,
    'validUntil',v_valid_until,
    'receiptObservationId',v_receipt_id,
    'estateObservationId',v_estate_id
  );
end;
$$;

revoke all on function foundation.record_defence_supabase_runtime_receipt_v1(
  text,jsonb,integer,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_supabase_runtime_receipt_v1(
  text,jsonb,integer,timestamptz
) to service_role;


alter table foundation.defence_estate_incident_events
  drop constraint if exists defence_estate_incident_events_reason_code_check;

alter table foundation.defence_estate_incident_events
  add constraint defence_estate_incident_events_reason_code_check
  check (reason_code in (
    'healthy',
    'missing-observation',
    'stale-observation',
    'runtime-failure',
    'unexpected-runtime-state',
    'health-coverage-missing',
    'health-degraded',
    'health-unhealthy',
    'health-observation-missing',
    'health-observation-stale',
    'runtime-provenance-coverage-missing',
    'runtime-provenance-missing',
    'runtime-provenance-stale',
    'supabase-runtime-receipt-coverage-missing',
    'supabase-runtime-receipt-missing',
    'supabase-runtime-receipt-stale'
  ));
