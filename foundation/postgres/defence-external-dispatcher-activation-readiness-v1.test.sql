begin;

do $activation_required_repos$
declare
  r jsonb;
begin
  select foundation.get_defence_external_dispatcher_required_repositories_v1()
  into r;

  if r->>'contract'<>'shine-defence/external-dispatcher-required-repositories-v1'
     or r->>'schemaVersion'<>'1.0.0'
     or (r->>'requiredRepositoryCount')::integer<1
     or jsonb_typeof(r->'repositories')<>'array'
     or not exists (
       select 1
       from jsonb_array_elements(r->'repositories') x
       where x->>'repository'='doug-dotcom/ShineUniverse-shine-core'
         and x->>'repositoryId'='1072897952'
         and x->>'targetId'='core'
     ) then
    raise exception 'Dispatcher required repository contract invalid: %',r;
  end if;
end;
$activation_required_repos$;


do $activation_lease$
declare
  issued jsonb;
  accepted jsonb;
  replay jsonb;
begin
  select foundation.issue_defence_external_dispatcher_readiness_lease_v1(
    clock_timestamp(),120
  ) into issued;

  if issued->>'contract'<>'shine-defence/external-dispatcher-readiness-lease-v1'
     or issued->>'purpose'<>'activation_readiness'
     or issued->>'singleUse'<>'true'
     or issued->>'leaseToken' !~ '^[a-f0-9]{64}$' then
    raise exception 'Dispatcher readiness lease invalid: %',issued;
  end if;

  select foundation.claim_defence_external_dispatcher_readiness_lease_v1(
    (issued->>'leaseId')::uuid,
    issued->>'leaseToken',
    'activation-test-1',
    clock_timestamp()
  ) into accepted;

  if accepted->>'status'<>'accepted'
     or accepted->>'executionId'<>'activation-test-1' then
    raise exception 'Dispatcher readiness lease claim failed: %',accepted;
  end if;

  select foundation.claim_defence_external_dispatcher_readiness_lease_v1(
    (issued->>'leaseId')::uuid,
    issued->>'leaseToken',
    'activation-test-2',
    clock_timestamp()
  ) into replay;

  if replay->>'status'<>'rejected' then
    raise exception 'Dispatcher readiness lease replay accepted: %',replay;
  end if;
end;
$activation_lease$;


do $activation_receipts$
declare
  required jsonb;
  required_count integer;
  missing jsonb;
  summary jsonb;
  ready jsonb;
begin
  select foundation.get_defence_external_dispatcher_required_repositories_v1()
  into required;
  required_count := (required->>'requiredRepositoryCount')::integer;

  select foundation.record_defence_external_dispatcher_readiness_v1(
    gen_random_uuid(),
    null,
    null,
    false,
    false,
    false,
    false,
    false,
    required_count,
    0,
    (
      select coalesce(jsonb_agg(x->>'repositoryId'),'[]'::jsonb)
      from jsonb_array_elements(required->'repositories') x
    ),
    'missing_credentials',
    null,
    clock_timestamp(),
    clock_timestamp()+interval '1 hour',
    'test:dispatcher-activation:missing',
    jsonb_build_object(
      'credentialValueExposed',false,
      'readinessCheckDispatchesWorkflow',false
    )
  ) into missing;

  if missing->>'status'<>'recorded'
     or missing->>'ready'<>'false' then
    raise exception 'Missing-credential readiness receipt invalid: %',missing;
  end if;

  select foundation.get_defence_external_dispatcher_activation_readiness_v1(
    clock_timestamp(),3600
  ) into summary;

  if summary->>'state'<>'not_configured'
     or summary->>'credentialValueExposed'<>'false'
     or summary->>'readinessCheckDispatchesWorkflow'<>'false'
     or summary->>'workflowOidcRemainsAuthoritative'<>'true' then
    raise exception 'Dispatcher activation summary missing-credential state invalid: %',summary;
  end if;

  select foundation.record_defence_external_dispatcher_readiness_v1(
    gen_random_uuid(),
    '12345',
    '67890',
    true,
    true,
    true,
    true,
    true,
    required_count,
    required_count,
    '[]'::jsonb,
    'ready',
    clock_timestamp()+interval '55 minutes',
    clock_timestamp(),
    clock_timestamp()+interval '1 hour',
    'test:dispatcher-activation:ready',
    jsonb_build_object(
      'credentialValueExposed',false,
      'installationTokenStored',false,
      'appJwtStored',false,
      'workflowAccessComplete',true
    )
  ) into ready;

  if ready->>'status'<>'recorded'
     or ready->>'ready'<>'true' then
    raise exception 'Ready dispatcher receipt invalid: %',ready;
  end if;

  select foundation.get_defence_external_dispatcher_activation_readiness_v1(
    clock_timestamp(),3600
  ) into summary;

  if summary->>'state'<>'ready'
     or summary#>>'{latestReceipt,appIdentityVerified}'<>'true'
     or summary#>>'{latestReceipt,installationTokenIssued}'<>'true'
     or summary#>>'{latestReceipt,actionsWriteConfirmed}'<>'true'
     or summary#>>'{latestReceipt,repositoryCoverageComplete}'<>'true'
     or summary#>>'{latestReceipt,coveredRepositoryCount}'<>
        summary#>>'{latestReceipt,requiredRepositoryCount}' then
    raise exception 'Dispatcher activation ready state invalid: %',summary;
  end if;
end;
$activation_receipts$;


do $activation_ready_fail_closed$
declare
  required jsonb;
  required_count integer;
begin
  select foundation.get_defence_external_dispatcher_required_repositories_v1()
  into required;
  required_count := (required->>'requiredRepositoryCount')::integer;

  begin
    perform foundation.record_defence_external_dispatcher_readiness_v1(
      gen_random_uuid(),
      '12345',
      '67890',
      true,
      true,
      true,
      false,
      true,
      required_count,
      required_count,
      '[]'::jsonb,
      'ready',
      clock_timestamp()+interval '55 minutes',
      clock_timestamp(),
      clock_timestamp()+interval '1 hour',
      'test:dispatcher-activation:invalid-ready',
      '{}'::jsonb
    );
    raise exception 'Dispatcher readiness accepted ready without Actions write';
  exception
    when sqlstate '22023' then null;
  end;
end;
$activation_ready_fail_closed$;


do $activation_blocked_heartbeat$
declare
  r jsonb;
begin
  select foundation.record_defence_external_dispatcher_heartbeat_v1(
    gen_random_uuid(),
    true,
    'disabled_activation_not_ready',
    clock_timestamp(),
    'test:dispatcher-activation:blocked-heartbeat',
    jsonb_build_object(
      'activationState','not_configured',
      'credentialValueExposed',false
    )
  ) into r;

  if r->>'status'<>'recorded'
     or r->>'credentialsReady'<>'true'
     or r->>'outcome'<>'disabled_activation_not_ready' then
    raise exception 'Activation-blocked heartbeat invalid: %',r;
  end if;
end;
$activation_blocked_heartbeat$;


do $activation_security$
begin
  if has_table_privilege(
       'anon',
       'foundation.defence_external_dispatcher_readiness_receipts',
       'SELECT'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.issue_defence_external_dispatcher_readiness_lease_v1(timestamp with time zone,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.record_defence_external_dispatcher_readiness_v1(uuid,text,text,boolean,boolean,boolean,boolean,boolean,integer,integer,jsonb,text,timestamp with time zone,timestamp with time zone,timestamp with time zone,text,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_external_dispatcher_activation_readiness_v1(timestamp with time zone,integer)',
       'EXECUTE'
     ) then
    raise exception 'Dispatcher activation readiness privilege boundary invalid';
  end if;
end;
$activation_security$;

rollback;
