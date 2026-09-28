begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values
(
  'railway:test-rollback-ready',
  'Rollback Ready Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active']::text[],'active',
  '{"sourceRepository":"doug-dotcom/test-rollback-ready","sourceBranch":"main"}'::jsonb
),
(
  'railway:test-rollback-history',
  'Rollback History Test',
  'railway',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666',
  'primary_service',true,array['active']::text[],'active',
  '{"sourceRepository":"doug-dotcom/test-rollback-history","sourceBranch":"main"}'::jsonb
),
(
  'railway:test-rollback-unavailable',
  'Rollback Unavailable Test',
  'railway',
  '77777777-7777-4777-8777-777777777777',
  '88888888-8888-4888-8888-888888888888',
  '99999999-9999-4999-8999-999999999999',
  'primary_service',true,array['active']::text[],'active',
  '{"sourceRepository":"doug-dotcom/test-rollback-unavailable","sourceBranch":"main"}'::jsonb
);

insert into foundation.defence_release_admission_events(
  target_id,admission_state,reason_code,
  serving_deployment_id,serving_commit_sha,
  canonical_deployment_id,canonical_commit_sha,
  rollback_deployment_id,rollback_commit_sha,
  observed_at,evidence,evidence_ref
) values
(
  'railway:test-rollback-ready','admitted','candidate-evidence-clear',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',repeat('a',40),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',repeat('a',40),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('b',40),
  now(),'{}'::jsonb,'test:rollback-ready:admission'
),
(
  'railway:test-rollback-history','admitted','baseline-evidence-clear',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',repeat('c',40),
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',repeat('c',40),
  null,null,
  now(),'{}'::jsonb,'test:rollback-history:admission'
),
(
  'railway:test-rollback-unavailable','admitted','candidate-evidence-clear',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',repeat('d',40),
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',repeat('d',40),
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',repeat('e',40),
  now(),'{}'::jsonb,'test:rollback-unavailable:admission'
);

do $rollback$
declare
  v jsonb;
begin
  select foundation.get_defence_rollback_claim_v1('railway:test-rollback-ready') into v;
  if v->>'status'<>'work'
     or v->>'rollbackCommitSha'<>repeat('b',40)
     or v->>'canonicalCommitSha'<>repeat('a',40)
     or v->>'repository'<>'doug-dotcom/test-rollback-ready' then
    raise exception 'rollback work claim incorrect: %',v;
  end if;

  select foundation.get_defence_rollback_claim_v1('railway:test-rollback-history') into v;
  if v->>'status'<>'history-building'
     or v->>'canonicalCommitSha'<>repeat('c',40) then
    raise exception 'history-building claim incorrect: %',v;
  end if;
end;
$rollback$;

do $rollback$
declare
  v jsonb;
begin
  select foundation.record_defence_rollback_source_attestation_v1(
    'railway:test-rollback-ready',
    'doug-dotcom/test-rollback-ready',
    repeat('b',40),
    repeat('a',40),
    true,
    now(),
    now()+interval '2 hours',
    'test:rollback-ready:attestation',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status'<>'recorded'
     or (v->>'sourceAvailable')::boolean is not true then
    raise exception 'source-ready attestation not recorded: %',v;
  end if;

  select foundation.record_defence_rollback_source_attestation_v1(
    'railway:test-rollback-unavailable',
    'doug-dotcom/test-rollback-unavailable',
    repeat('e',40),
    repeat('d',40),
    false,
    now(),
    now()+interval '2 hours',
    'test:rollback-unavailable:attestation',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status'<>'recorded'
     or (v->>'sourceAvailable')::boolean is not false then
    raise exception 'source-unavailable attestation not recorded: %',v;
  end if;
end;
$rollback$;

do $rollback$
declare
  v jsonb;
begin
  select foundation.record_defence_rollback_source_attestation_v1(
    'railway:test-rollback-ready',
    'doug-dotcom/test-rollback-ready',
    repeat('f',40),
    repeat('a',40),
    true,
    now(),
    now()+interval '2 hours',
    'test:rollback-ready:mismatch',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'rollback-attestation-binding-mismatch' then
    raise exception 'rollback binding mismatch should be rejected: %',v;
  end if;
end;
$rollback$;

do $rollback$
declare
  v jsonb;
begin
  select foundation.get_defence_rollback_readiness_summary_v1() into v;

  if (v->>'sourceReadyTargets')::integer<1
     or (v->>'historyBuildingTargets')::integer<1
     or (v->>'sourceUnavailableTargets')::integer<1
     or v->>'state'<>'warning' then
    raise exception 'rollback readiness summary incorrect: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'targets') x
    where x->>'targetId'='railway:test-rollback-ready'
      and x->>'state'='source-ready'
  ) then
    raise exception 'source-ready target missing from summary: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'targets') x
    where x->>'targetId'='railway:test-rollback-history'
      and x->>'state'='history-building'
  ) then
    raise exception 'history-building target missing from summary: %',v;
  end if;
end;
$rollback$;

do $rollback$
begin
  if has_table_privilege(
       'anon','foundation.defence_rollback_source_attestations','SELECT'
     )
     or has_table_privilege(
       'authenticated','foundation.current_defence_rollback_source_attestations','SELECT'
     ) then
    raise exception 'public roles must not read rollback readiness evidence';
  end if;

  if has_function_privilege(
       'authenticated',
       'foundation.record_defence_rollback_source_attestation_v1(text,text,text,text,boolean,timestamptz,timestamptz,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'public role unexpectedly records rollback source evidence';
  end if;

  begin
    update foundation.defence_rollback_source_attestations
       set source_available=false;
    raise exception 'rollback source attestations unexpectedly mutated';
  exception
    when sqlstate '55000' then null;
  end;
end;
$rollback$;

rollback;
