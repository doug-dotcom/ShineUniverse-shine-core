begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,target_role,
  required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'supabase:abcdefghijklmnopqrst',
  'Supabase Receipt Test',
  'supabase',
  'abcdefghijklmnopqrst',
  'shared_backend',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',(now()-interval '1 hour')::text,
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','11111111-1111-4111-8111-111111111111',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256',repeat('a',64),
    'projectRegion','ap-southeast-2'
  )
);

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_supabase_runtime_receipt_v1(
    'supabase:abcdefghijklmnopqrst',
    jsonb_build_object(
      'contract','shine-defence/supabase-runtime-receipt-v1',
      'schemaVersion','1.0.0',
      'provider','supabase',
      'projectRef','abcdefghijklmnopqrst',
      'function',jsonb_build_object(
        'deploymentId','abcdefghijklmnopqrst_11111111-1111-4111-8111-111111111111_1',
        'functionId','11111111-1111-4111-8111-111111111111',
        'version',1,
        'region','ap-southeast-2',
        'executionId','22222222-2222-4222-8222-222222222222'
      ),
      'database',jsonb_build_object(
        'reachable',true,
        'serverVersion','17.6',
        'databaseName','postgres',
        'errorCode',null
      ),
      'identityOk',true
    ),
    200,
    now()
  ) into v;

  if v->>'status'<>'recorded'
     or v->>'projectRef'<>'abcdefghijklmnopqrst'
     or v->>'deploymentId'<>'abcdefghijklmnopqrst_11111111-1111-4111-8111-111111111111_1'
     or (v->>'databaseReachable')::boolean is not true then
    raise exception 'valid Supabase runtime receipt not recorded: %',v;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from foundation.current_defence_supabase_runtime_receipts
    where target_id='supabase:abcdefghijklmnopqrst'
      and project_ref='abcdefghijklmnopqrst'
      and function_id='11111111-1111-4111-8111-111111111111'::uuid
      and function_version=1
      and database_reachable
  ) then
    raise exception 'current Supabase runtime receipt missing';
  end if;

  if not exists (
    select 1
    from foundation.current_defence_estate_observations
    where target_id='supabase:abcdefghijklmnopqrst'
      and evidence_kind='runtime-self-report'
      and runtime_state='active'
      and health_state='healthy'
  ) then
    raise exception 'Supabase receipt did not refresh estate observation';
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_supabase_runtime_receipt_v1(
    'supabase:abcdefghijklmnopqrst',
    jsonb_build_object(
      'contract','shine-defence/supabase-runtime-receipt-v1',
      'schemaVersion','1.0.0',
      'provider','supabase',
      'projectRef','abcdefghijklmnopqrst',
      'function',jsonb_build_object(
        'deploymentId','abcdefghijklmnopqrst_11111111-1111-4111-8111-111111111111_2',
        'functionId','11111111-1111-4111-8111-111111111111',
        'version',2,
        'region','ap-southeast-2',
        'executionId','22222222-2222-4222-8222-222222222222'
      ),
      'database',jsonb_build_object(
        'reachable',true,
        'serverVersion','17.6',
        'databaseName','postgres'
      ),
      'identityOk',true
    ),
    200,
    now()+interval '1 second'
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'supabase-runtime-receipt-identity-mismatch' then
    raise exception 'unapproved receipt version should be rejected: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_supabase_runtime_receipt_v1(
    'supabase:abcdefghijklmnopqrst',
    jsonb_build_object(
      'contract','shine-defence/supabase-runtime-receipt-v1',
      'schemaVersion','1.0.0',
      'provider','supabase',
      'projectRef','abcdefghijklmnopqrst',
      'function',jsonb_build_object(
        'deploymentId','abcdefghijklmnopqrst_11111111-1111-4111-8111-111111111111_1',
        'functionId','11111111-1111-4111-8111-111111111111',
        'version',1,
        'region','ap-southeast-2',
        'executionId','33333333-3333-4333-8333-333333333333'
      ),
      'database',jsonb_build_object(
        'reachable',false,
        'serverVersion',null,
        'databaseName',null,
        'errorCode','08006'
      ),
      'identityOk',true
    ),
    503,
    now()+interval '2 seconds'
  ) into v;

  if v->>'status'<>'recorded'
     or (v->>'databaseReachable')::boolean is not false then
    raise exception 'unreachable database receipt should record unhealthy evidence: %',v;
  end if;

  if not exists (
    select 1
    from foundation.current_defence_estate_observations
    where target_id='supabase:abcdefghijklmnopqrst'
      and health_state='unhealthy'
  ) then
    raise exception 'unreachable database receipt did not mark estate unhealthy';
  end if;
end;
$$;

-- A second transaction-only target proves missing receipt warnings.
insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,target_role,
  required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'supabase:bcdefghijklmnopqrstu',
  'Supabase Receipt Gap Test',
  'supabase',
  'bcdefghijklmnopqrstu',
  'shared_backend',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'runtimeReceiptRequired',true,
    'runtimeReceiptContract','shine-defence/supabase-runtime-receipt-v1',
    'runtimeReceiptEffectiveAt',(now()-interval '1 hour')::text,
    'receiptFunction','defence-runtime-receipt',
    'receiptFunctionId','44444444-4444-4444-8444-444444444444',
    'approvedReceiptVersion',1,
    'receiptArtifactSha256',repeat('b',64),
    'projectRegion','ap-southeast-2'
  )
);

do $$
declare
  v jsonb;
begin
  select foundation.run_defence_supabase_runtime_receipt_sentinel_v1(
    now()+interval '3 seconds'
  ) into v;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where target_id='supabase:bcdefghijklmnopqrstu'
      and incident_key='supabase:bcdefghijklmnopqrstu:supabase-runtime-receipt'
      and state='warning'
      and reason_code='supabase-runtime-receipt-missing'
  ) then
    raise exception 'missing Supabase receipt must create warning: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.get_defence_full_estate_summary_v1() into v;
  if v->>'state' not in ('warning','fail') then
    raise exception 'full estate summary must include Supabase receipt state: %',v;
  end if;
end;
$$;

do $$
begin
  if has_table_privilege(
       'anon',
       'foundation.defence_supabase_runtime_receipt_observations',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'foundation.defence_supabase_runtime_receipt_requests',
       'SELECT'
     ) then
    raise exception 'public roles must not read Supabase runtime receipt controls';
  end if;

  if has_function_privilege(
       'authenticated',
       'foundation.record_defence_supabase_runtime_receipt_v1(text,jsonb,integer,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'public role unexpectedly records Supabase receipts';
  end if;

  begin
    update foundation.defence_supabase_runtime_receipt_observations
       set region='ap-south-1';
    raise exception 'Supabase receipt history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
