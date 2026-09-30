begin;

do $$
declare
  v_first jsonb;
  v_replay jsonb;
  v_conflict jsonb;
  v_other_operation jsonb;
  v_other_attempt jsonb;
begin
  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/test-app',
    'refs/heads/main',
    'doug-dotcom/test-app/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '123456789',
    '1',
    'schedule',
    'shine-defence-release-head',
    'release-head-snapshot',
    'railway:test-replay',
    '{"contract":"shine-defence/release-head-snapshot-v1","value":1}'::jsonb
  ) into v_first;

  if v_first->>'status'<>'accepted-new' then
    raise exception 'first OIDC operation was not accepted-new: %',v_first;
  end if;

  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/test-app',
    'refs/heads/main',
    'doug-dotcom/test-app/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '123456789',
    '1',
    'schedule',
    'shine-defence-release-head',
    'release-head-snapshot',
    'railway:test-replay',
    '{"value":1,"contract":"shine-defence/release-head-snapshot-v1"}'::jsonb
  ) into v_replay;

  if v_replay->>'status'<>'replayed-exact'
     or v_replay->>'requestSha256'<>v_first->>'requestSha256' then
    raise exception 'semantic JSON retry was not replayed-exact: %',v_replay;
  end if;

  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/test-app',
    'refs/heads/main',
    'doug-dotcom/test-app/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '123456789',
    '1',
    'schedule',
    'shine-defence-release-head',
    'release-head-snapshot',
    'railway:test-replay',
    '{"contract":"shine-defence/release-head-snapshot-v1","value":2}'::jsonb
  ) into v_conflict;

  if v_conflict->>'status'<>'rejected-conflict'
     or v_conflict->>'requestSha256'=v_conflict->>'originalRequestSha256' then
    raise exception 'changed payload did not fail closed: %',v_conflict;
  end if;

  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/test-app',
    'refs/heads/main',
    'doug-dotcom/test-app/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '123456789',
    '1',
    'schedule',
    'shine-defence-rollback-readiness',
    'rollback-claim',
    'railway:test-replay',
    '{"action":"claim","targetId":"railway:test-replay"}'::jsonb
  ) into v_other_operation;

  if v_other_operation->>'status'<>'accepted-new' then
    raise exception 'legitimate cross-audience operation was blocked: %',v_other_operation;
  end if;

  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/test-app',
    'refs/heads/main',
    'doug-dotcom/test-app/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '123456789',
    '2',
    'schedule',
    'shine-defence-release-head',
    'release-head-snapshot',
    'railway:test-replay',
    '{"contract":"shine-defence/release-head-snapshot-v1","value":2}'::jsonb
  ) into v_other_attempt;

  if v_other_attempt->>'status'<>'accepted-new' then
    raise exception 'new GitHub run attempt was not independently accepted: %',v_other_attempt;
  end if;

  if (
    select count(*)
    from foundation.github_oidc_operation_bindings
    where repository='doug-dotcom/test-app'
      and run_id='123456789'
  )<>3 then
    raise exception 'OIDC operation binding count mismatch';
  end if;

  if (
    select count(*)
    from foundation.github_oidc_operation_events e
    join foundation.github_oidc_operation_bindings b using(binding_id)
    where b.repository='doug-dotcom/test-app'
      and b.run_id='123456789'
      and e.outcome='replayed-exact'
  )<>1 then
    raise exception 'exact replay event missing';
  end if;

  if (
    select count(*)
    from foundation.github_oidc_operation_events e
    join foundation.github_oidc_operation_bindings b using(binding_id)
    where b.repository='doug-dotcom/test-app'
      and b.run_id='123456789'
      and e.outcome='rejected-conflict'
  )<>1 then
    raise exception 'replay conflict event missing';
  end if;
end;
$$;


do $$
begin
  begin
    perform foundation.bind_github_oidc_operation_v1(
      'doug-dotcom/test-app',
      'refs/heads/main',
      'doug-dotcom/test-app/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
      '999',
      '1',
      'schedule',
      'shine-defence-release-head',
      'rollback-attest',
      'railway:test-replay',
      '{"x":1}'::jsonb
    );
    raise exception 'cross-purpose operation unexpectedly accepted';
  exception
    when sqlstate '22023' then
      null;
  end;
end;
$$;


do $authority_sync_test$
declare
  v jsonb;
begin
  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/ShineUniverse-shine-core',
    'refs/heads/main',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-authority-state.yml@refs/heads/main',
    '777777777',
    '1',
    'push',
    'shine-defence-authority-state',
    'attestation-authority-sync',
    'authority:1:7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '{"contract":"shine-defence/attestation-authority-activation-v1","schemaVersion":"1.0.0"}'::jsonb
  ) into v;

  if v->>'status'<>'accepted-new'
     or v->>'audience'<>'shine-defence-authority-state'
     or v->>'operation'<>'attestation-authority-sync' then
    raise exception 'authority-state sync purpose was not accepted: %',v;
  end if;
end;
$authority_sync_test$;


insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-oidc-provider',
  'OIDC Provider Replay Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object('serviceName','test-oidc-provider')
);

do $$
declare
  v_first uuid;
  v_replay uuid;
  v_observed timestamptz := '2026-09-30T03:00:00Z'::timestamptz;
  v_valid timestamptz := '2026-09-30T05:00:00Z'::timestamptz;
begin
  select foundation.record_defence_estate_observation_v1(
    'railway:test-oidc-provider',
    'active',
    'healthy',
    'deployment-1',
    'version-1',
    'artifact-1',
    v_observed,
    v_valid,
    'railway-api',
    'github-oidc:railway:test-oidc-provider:run:1',
    '{"collector":"test"}'::jsonb
  ) into v_first;

  select foundation.record_defence_estate_observation_v1(
    'railway:test-oidc-provider',
    'active',
    'healthy',
    'deployment-1',
    'version-1',
    'artifact-1',
    v_observed,
    v_valid,
    'railway-api',
    'github-oidc:railway:test-oidc-provider:run:1',
    '{"collector":"test"}'::jsonb
  ) into v_replay;

  if v_replay<>v_first then
    raise exception 'exact provider observation retry did not return original id';
  end if;

  if (
    select count(*)
    from foundation.defence_estate_observations
    where evidence_ref='github-oidc:railway:test-oidc-provider:run:1'
  )<>1 then
    raise exception 'provider observation retry duplicated evidence';
  end if;

  begin
    perform foundation.record_defence_estate_observation_v1(
      'railway:test-oidc-provider',
      'failed',
      'unhealthy',
      'deployment-1',
      'version-1',
      'artifact-1',
      v_observed,
      v_valid,
      'railway-api',
      'github-oidc:railway:test-oidc-provider:run:1',
      '{"collector":"test"}'::jsonb
    );
    raise exception 'conflicting provider evidence unexpectedly accepted';
  exception
    when sqlstate '23505' then
      null;
  end;
end;
$$;


do $$
begin
  if has_table_privilege('anon','foundation.github_oidc_operation_bindings','SELECT')
     or has_table_privilege('authenticated','foundation.github_oidc_operation_events','SELECT')
     or has_function_privilege(
       'authenticated',
       'foundation.bind_github_oidc_operation_v1(text,text,text,text,text,text,text,text,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'public roles unexpectedly access OIDC replay controls';
  end if;

  begin
    update foundation.github_oidc_operation_bindings
       set event_name='push';
    raise exception 'OIDC binding history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;

  begin
    delete from foundation.github_oidc_operation_events;
    raise exception 'OIDC replay event history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
