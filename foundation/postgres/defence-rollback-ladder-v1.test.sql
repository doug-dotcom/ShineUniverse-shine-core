begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values
(
  'railway:test-ladder-degraded','Rollback Ladder Degraded Test','railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active']::text[],'active',
  '{"sourceRepository":"doug-dotcom/test-ladder-degraded","sourceBranch":"main"}'::jsonb
),
(
  'railway:test-ladder-soak','Rollback Ladder Soak Test','railway',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666',
  'primary_service',true,array['active']::text[],'active',
  '{"sourceRepository":"doug-dotcom/test-ladder-soak","sourceBranch":"main"}'::jsonb
),
(
  'railway:test-ladder-history','Rollback Ladder History Test','railway',
  '77777777-7777-4777-8777-777777777777',
  '88888888-8888-4888-8888-888888888888',
  '99999999-9999-4999-8999-999999999999',
  'primary_service',true,array['active']::text[],'active',
  '{"sourceRepository":"doug-dotcom/test-ladder-history","sourceBranch":"main"}'::jsonb
);

insert into foundation.defence_release_admission_events(
  target_id,admission_state,reason_code,
  serving_deployment_id,serving_commit_sha,
  canonical_deployment_id,canonical_commit_sha,
  rollback_deployment_id,rollback_commit_sha,
  observed_at,evidence,evidence_ref
) values
(
  'railway:test-ladder-degraded','canonical','canonical-serving',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',repeat('a',40),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',repeat('a',40),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('b',40),
  now(),'{}'::jsonb,'test:ladder:degraded:current'
),
(
  'railway:test-ladder-degraded','admitted','candidate-evidence-clear',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('b',40),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',repeat('b',40),
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',repeat('c',40),
  now()-interval '10 minutes','{}'::jsonb,'test:ladder:degraded:prior1'
),
(
  'railway:test-ladder-degraded','admitted','candidate-evidence-clear',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',repeat('c',40),
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',repeat('c',40),
  null,null,
  now()-interval '20 minutes','{}'::jsonb,'test:ladder:degraded:prior2'
),
(
  'railway:test-ladder-soak','soaking','admission-soak-incomplete',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd',repeat('d',40),
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',repeat('e',40),
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',repeat('e',40),
  now(),'{}'::jsonb,'test:ladder:soak:current'
),
(
  'railway:test-ladder-soak','admitted','candidate-evidence-clear',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',repeat('e',40),
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',repeat('e',40),
  'ffffffff-ffff-4fff-8fff-ffffffffffff',repeat('f',40),
  now()-interval '15 minutes','{}'::jsonb,'test:ladder:soak:prior'
),
(
  'railway:test-ladder-history','canonical','canonical-serving',
  '12121212-1212-4212-8212-121212121212',repeat('1',40),
  '12121212-1212-4212-8212-121212121212',repeat('1',40),
  null,null,
  now(),'{}'::jsonb,'test:ladder:history:current'
);

insert into foundation.defence_rollback_source_attestations(
  target_id,repository,rollback_commit_sha,canonical_commit_sha,
  source_available,canonical_source_available,
  observed_at,valid_until,evidence_ref,metadata
) values
(
  'railway:test-ladder-degraded','doug-dotcom/test-ladder-degraded',
  repeat('b',40),repeat('a',40),
  false,true,
  now(),now()+interval '2 hours',
  'test:ladder:degraded:b-unavailable','{}'::jsonb
),
(
  'railway:test-ladder-degraded','doug-dotcom/test-ladder-degraded',
  repeat('c',40),repeat('b',40),
  true,true,
  now(),now()+interval '2 hours',
  'test:ladder:degraded:c-ready','{}'::jsonb
),
(
  'railway:test-ladder-soak','doug-dotcom/test-ladder-soak',
  repeat('e',40),repeat('d',40),
  true,true,
  now(),now()+interval '2 hours',
  'test:ladder:soak:canonical-ready','{}'::jsonb
);

do $ladder$
declare
  v jsonb;
begin
  select foundation.get_defence_rollback_ladder_v1() into v;

  if not exists (
    select 1
    from jsonb_array_elements(v->'targets') x
    where x->>'targetId'='railway:test-ladder-degraded'
      and x->>'state'='degraded-fallback-ready'
      and (x#>>'{recommendedRecovery,rank}')::integer=2
      and x#>>'{recommendedRecovery,commitSha}'=repeat('c',40)
  ) then
    raise exception 'rank-2 recovery fallback should be recommended: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'targets') x
    cross join lateral jsonb_array_elements(x->'candidates') c
    where x->>'targetId'='railway:test-ladder-soak'
      and x->>'state'='primary-ready'
      and (c->>'rank')::integer=1
      and c->>'origin'='preserved-current-canonical'
      and c->>'commitSha'=repeat('e',40)
  ) then
    raise exception 'preserved canonical should be rank-1 during soak: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'targets') x
    where x->>'targetId'='railway:test-ladder-history'
      and x->>'state'='history-building'
      and (x->>'qualifiedHistoryDepth')::integer=0
  ) then
    raise exception 'single-release target should remain history-building: %',v;
  end if;
end;
$ladder$;

do $ladder$
begin
  if has_function_privilege(
       'anon','foundation.get_defence_rollback_ladder_v1()','EXECUTE'
     )
     or has_function_privilege(
       'authenticated','foundation.get_defence_rollback_ladder_v1()','EXECUTE'
     ) then
    raise exception 'public roles must not execute rollback ladder summary';
  end if;

  if not has_function_privilege(
       'foundation_runtime','foundation.get_defence_rollback_ladder_v1()','EXECUTE'
     ) then
    raise exception 'foundation_runtime must read bounded rollback ladder';
  end if;
end;
$ladder$;

rollback;
