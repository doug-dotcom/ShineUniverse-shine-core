begin;

do $dispatcher_lease$
declare
  issued jsonb;
  accepted jsonb;
  replay jsonb;
  wrong jsonb;
begin
  select foundation.issue_defence_external_dispatch_lease_v1(
    clock_timestamp(),120
  ) into issued;

  if issued->>'contract'<>'shine-defence/external-dispatch-lease-v1'
     or issued->>'schemaVersion'<>'1.0.0'
     or issued->>'singleUse'<>'true'
     or issued->>'leaseId' is null
     or issued->>'leaseToken' !~ '^[a-f0-9]{64}$' then
    raise exception 'External dispatcher lease issue invalid: %',issued;
  end if;

  select foundation.claim_defence_external_dispatch_lease_v1(
    (issued->>'leaseId')::uuid,
    issued->>'leaseToken',
    'test-execution-1',
    clock_timestamp()
  ) into accepted;

  if accepted->>'status'<>'accepted'
     or accepted->>'executionId'<>'test-execution-1' then
    raise exception 'External dispatcher lease claim invalid: %',accepted;
  end if;

  select foundation.claim_defence_external_dispatch_lease_v1(
    (issued->>'leaseId')::uuid,
    issued->>'leaseToken',
    'test-execution-2',
    clock_timestamp()
  ) into replay;

  if replay->>'status'<>'rejected'
     or replay->>'reasonCode'<>'lease-invalid-expired-or-used' then
    raise exception 'External dispatcher lease replay not rejected: %',replay;
  end if;

  select foundation.claim_defence_external_dispatch_lease_v1(
    gen_random_uuid(),
    repeat('0',64),
    'test-execution-wrong',
    clock_timestamp()
  ) into wrong;

  if wrong->>'status'<>'rejected' then
    raise exception 'External dispatcher wrong lease not rejected: %',wrong;
  end if;
end;
$dispatcher_lease$;


do $dispatcher_audit$
declare
  event_id uuid := gen_random_uuid();
  recorded jsonb;
  replay jsonb;
  heartbeat jsonb;
  summary jsonb;
begin
  select foundation.record_defence_external_dispatch_event_v1(
    event_id,
    'rollback_refresh',
    'railway:test-dispatch',
    'doug-dotcom/test-dispatch',
    '.github/workflows/shine-defence-release-head.yml',
    'main',
    'rollback-source-proof-refresh-margin',
    'disabled',
    null,
    null,
    clock_timestamp(),
    'test:external-dispatch:event:1',
    jsonb_build_object(
      'triggerIsEvidence',false,
      'credentialsReady',false
    )
  ) into recorded;

  if recorded->>'status'<>'recorded'
     or recorded->>'dispatchKind'<>'rollback_refresh'
     or recorded->>'outcome'<>'disabled' then
    raise exception 'External dispatch event record invalid: %',recorded;
  end if;

  select foundation.record_defence_external_dispatch_event_v1(
    event_id,
    'rollback_refresh',
    'railway:test-dispatch',
    'doug-dotcom/test-dispatch',
    '.github/workflows/shine-defence-release-head.yml',
    'main',
    'rollback-source-proof-refresh-margin',
    'disabled',
    null,
    null,
    clock_timestamp(),
    'test:external-dispatch:event:1',
    '{}'::jsonb
  ) into replay;

  if replay->>'status'<>'replayed' then
    raise exception 'External dispatch event replay invalid: %',replay;
  end if;

  select foundation.record_defence_external_dispatcher_heartbeat_v1(
    gen_random_uuid(),
    false,
    'disabled_missing_credentials',
    clock_timestamp(),
    'test:external-dispatch:heartbeat:1',
    jsonb_build_object(
      'githubAppIdPresent',false,
      'githubInstallationIdPresent',false,
      'githubPrivateKeyPresent',false,
      'credentialValueExposed',false
    )
  ) into heartbeat;

  if heartbeat->>'status'<>'recorded'
     or heartbeat->>'credentialsReady'<>'false'
     or heartbeat->>'outcome'<>'disabled_missing_credentials' then
    raise exception 'External dispatcher heartbeat invalid: %',heartbeat;
  end if;

  select foundation.get_defence_external_dispatcher_summary_v1(
    clock_timestamp(),1800
  ) into summary;

  if summary->>'state'<>'disabled'
     or summary->>'dispatcherCanMintProof'<>'false'
     or summary->>'dispatcherCanExtendProofTtl'<>'false'
     or summary->>'workflowOidcRemainsAuthoritative'<>'true' then
    raise exception 'External dispatcher summary invariants invalid: %',summary;
  end if;
end;
$dispatcher_audit$;


do $dispatcher_plan$
declare
  plan jsonb;
begin
  select foundation.get_defence_external_dispatch_plan_v1(
    clock_timestamp(),3600,900
  ) into plan;

  if plan->>'contract'<>'shine-defence/external-dispatch-plan-v1'
     or plan->>'schemaVersion'<>'1.0.0'
     or plan->>'phase' not in ('authority_first','rollback_refresh','idle')
     or plan->>'authorityFirst'<>'true'
     or plan->>'triggerIsEvidence'<>'false'
     or jsonb_typeof(plan->'items')<>'array'
     or (plan->>'itemCount')::integer<>jsonb_array_length(plan->'items') then
    raise exception 'External dispatch plan contract invalid: %',plan;
  end if;

  if plan->>'phase'='authority_first' then
    if jsonb_array_length(plan->'items')<>1
       or plan#>>'{items,0,dispatchKind}'<>'authority_refresh'
       or plan#>>'{items,0,targetId}' is not null then
      raise exception 'Authority-first plan invalid: %',plan;
    end if;
  end if;
end;
$dispatcher_plan$;


do $dispatcher_invalid$
begin
  begin
    perform foundation.issue_defence_external_dispatch_lease_v1(
      clock_timestamp(),10
    );
    raise exception 'Invalid short dispatcher lease TTL accepted';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform foundation.claim_defence_external_dispatch_lease_v1(
      gen_random_uuid(),'bad-token','bad',clock_timestamp()
    );
    raise exception 'Invalid dispatcher lease token accepted';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform foundation.record_defence_external_dispatch_event_v1(
      gen_random_uuid(),
      'authority_refresh',
      'railway:should-not-exist',
      'doug-dotcom/test',
      '.github/workflows/test.yml',
      'main',
      'bad-authority-target',
      'dispatched',
      null,
      200,
      clock_timestamp(),
      'test:invalid-authority-dispatch',
      '{}'::jsonb
    );
    raise exception 'Authority dispatch accepted target id';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform foundation.get_defence_external_dispatch_plan_v1(
      clock_timestamp(),100,900
    );
    raise exception 'Invalid dispatch plan refresh margin accepted';
  exception
    when sqlstate '22023' then null;
  end;
end;
$dispatcher_invalid$;


do $dispatcher_security$
begin
  if has_table_privilege(
       'anon',
       'foundation.defence_external_dispatch_leases',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'foundation.defence_external_dispatch_events',
       'SELECT'
     )
     or has_function_privilege(
       'anon',
       'foundation.issue_defence_external_dispatch_lease_v1(timestamp with time zone,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.record_defence_external_dispatch_event_v1(uuid,text,text,text,text,text,text,text,text,integer,timestamp with time zone,text,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_external_dispatch_plan_v1(timestamp with time zone,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'External dispatcher privilege boundary invalid';
  end if;
end;
$dispatcher_security$;

rollback;
