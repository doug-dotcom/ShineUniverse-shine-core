begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-source-head',
  'Release Source Head Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-source-head',
    'sourceBranch','main',
    'sourceHeadWatchRequired',true,
    'sourceHeadWatchEffectiveAt',(now()-interval '1 hour')::text,
    'sourceHeadWatchContract','shine-defence/release-source-watch-v1'
  )
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1',
  'railway:test-source-head',
  'https://example.invalid/health',
  'json_contains',
  '{"status":"ok"}'::jsonb,
  null,
  10000,1200,600,1,1,1,1200,
  true,now(),
  'test:source-head:health-target',
  'Transaction-only source-head fixture.',
  'continuous'
);

do $$
declare
  v_request uuid;
  v_sequence bigint;
begin
  insert into foundation.defence_health_probe_requests(
    target_id,target_version,external_request_id,target_url,queued_at,evidence_ref,metadata
  ) values (
    'railway:test-source-head','test-v1',null,'https://example.invalid/health',
    now(),'test:source-head:health-request','{}'::jsonb
  ) returning probe_request_id into v_request;

  v_sequence := foundation.record_defence_health_probe_result_v1(
    v_request,200,false,null,true,now(),100,null,
    'test:source-head:health-result','{}'::jsonb
  );

  insert into foundation.defence_runtime_provenance_observations(
    target_id,provider,repository,commit_sha,branch,deployment_id,
    service_name,environment_name,health_probe_result_sequence,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    'railway:test-source-head','railway','doug-dotcom/test-source-head',
    repeat('a',40),'main',
    '44444444-4444-4444-8444-444444444444',
    'test-source-head','production',v_sequence,
    now(),now()+interval '2 hours',
    'test:source-head:serving','{}'::jsonb
  );
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_release_source_head_v1(
    'railway:test-source-head',
    'doug-dotcom/test-source-head',
    'main',
    repeat('b',40),
    now()-interval '10 minutes',
    now(),
    now()+interval '30 minutes',
    'test:source-head:within-grace',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status'<>'recorded' then
    raise exception 'within-grace source head was not recorded: %',v;
  end if;

  select foundation.get_defence_release_source_head_summary_v1() into v;
  if v->>'state'<>'pass'
     or (v->>'sourceAheadTargets')::integer<1
     or (v->>'overdueNotServingTargets')::integer<>0 then
    raise exception 'recent source head ahead should remain rollout grace: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_release_source_head_v1(
    'railway:test-source-head',
    'attacker/wrong-repo',
    'main',
    repeat('c',40),
    now()-interval '40 minutes',
    now()+interval '1 second',
    now()+interval '30 minutes',
    'test:source-head:wrong-repo',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'release-source-identity-mismatch' then
    raise exception 'wrong source repo should be rejected: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_release_source_head_v1(
    'railway:test-source-head',
    'doug-dotcom/test-source-head',
    'main',
    repeat('c',40),
    now()-interval '40 minutes',
    now()+interval '2 seconds',
    now()+interval '30 minutes',
    'test:source-head:overdue',
    '{"test":true}'::jsonb
  ) into v;

  select foundation.get_defence_release_source_head_summary_v1() into v;
  if v->>'state'<>'warning'
     or (v->>'overdueNotServingTargets')::integer<1 then
    raise exception 'overdue source head should warn: %',v;
  end if;

  select foundation.run_defence_release_source_head_sentinel_v1(
    now()+interval '3 seconds'
  ) into v;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where incident_key='railway:test-source-head:release-source-head'
      and state='warning'
      and reason_code='release-source-head-not-serving'
  ) then
    raise exception 'overdue source head warning incident missing: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  perform foundation.record_defence_release_source_head_v1(
    'railway:test-source-head',
    'doug-dotcom/test-source-head',
    'main',
    repeat('a',40),
    now(),
    now()+interval '4 seconds',
    now()+interval '30 minutes',
    'test:source-head:recovered',
    '{"test":true}'::jsonb
  );

  select foundation.run_defence_release_source_head_sentinel_v1(
    now()+interval '5 seconds'
  ) into v;

  if not exists (
    select 1
    from foundation.current_defence_estate_incident_state
    where incident_key='railway:test-source-head:release-source-head'
      and event_type='recovered'
      and state='pass'
      and reason_code='healthy'
  ) then
    raise exception 'source head recovery missing: %',v;
  end if;
end;
$$;


do $
declare
  v jsonb;
begin
  perform foundation.record_defence_release_source_head_v1(
    'railway:test-source-head',
    'doug-dotcom/test-source-head',
    'main',
    repeat('d',40),
    now()-interval '40 minutes',
    now()+interval '6 seconds',
    now()+interval '90 minutes',
    'test:source-head:non-deployment',
    '{"test":true,"deploymentRelevant":false,"changedFileCount":1}'::jsonb
  );

  select foundation.get_defence_release_source_head_summary_v1() into v;

  if exists (
    select 1
    from jsonb_array_elements(v->'attention') x
    where x->>'targetId'='railway:test-source-head'
  ) then
    raise exception 'non-deployment source head must not become release attention: %',v;
  end if;

  select foundation.run_defence_release_source_head_sentinel_v1(
    now()+interval '7 seconds'
  ) into v;

  if exists (
    select 1
    from foundation.current_defence_estate_incidents
    where incident_key='railway:test-source-head:release-source-head'
  ) then
    raise exception 'non-deployment source head must not open an incident: %',v;
  end if;
end;
$;


do $
begin
  if has_table_privilege(
       'anon','foundation.defence_release_source_head_observations','SELECT'
     )
     or has_table_privilege(
       'authenticated','foundation.current_defence_release_source_heads','SELECT'
     ) then
    raise exception 'public roles must not read source-head evidence';
  end if;

  if has_function_privilege(
       'authenticated',
       'foundation.record_defence_release_source_head_v1(text,text,text,text,timestamptz,timestamptz,timestamptz,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'public role unexpectedly records source-head evidence';
  end if;

  begin
    update foundation.defence_release_source_head_observations
       set branch='mutation';
    raise exception 'source-head history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
