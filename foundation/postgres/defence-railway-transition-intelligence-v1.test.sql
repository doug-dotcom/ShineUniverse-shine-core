begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-transition',
  'Railway Transition Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  '{}'::jsonb
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1',
  'railway:test-transition',
  'https://example.invalid/health',
  'json_contains',
  '{"status":"ok"}'::jsonb,
  null,
  10000,1200,600,1,1,1,1200,
  true,now(),
  'test:transition:health-target',
  'Transaction-only Railway transition fixture.',
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
    'railway:test-transition','test-v1',null,'https://example.invalid/health',
    now(),'test:transition:health-request','{}'::jsonb
  ) returning probe_request_id into v_request;

  v_sequence := foundation.record_defence_health_probe_result_v1(
    v_request,200,false,null,true,now(),100,null,
    'test:transition:health-result','{}'::jsonb
  );

  insert into foundation.defence_runtime_provenance_observations(
    target_id,provider,repository,commit_sha,branch,deployment_id,
    service_name,environment_name,health_probe_result_sequence,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    'railway:test-transition','railway','doug-dotcom/test-transition',
    repeat('a',40),'main',
    '44444444-4444-4444-8444-444444444444',
    'test-transition','production',v_sequence,
    now(),now()+interval '1 hour',
    'test:transition:serving-provenance','{}'::jsonb
  );
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_railway_transition_v1(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '55555555-5555-4555-8555-555555555555',
    'Deployment.failed',
    'failed',
    'WARNING',
    'GitHub',
    'main',
    repeat('b',40),
    now(),
    repeat('c',64),
    'test:transition:failed-candidate',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status'<>'recorded'
     or v->>'targetId'<>'railway:test-transition' then
    raise exception 'failed candidate transition not recorded: %',v;
  end if;

  select foundation.get_defence_railway_transition_summary_v1() into v;
  if v->>'state'<>'warning'
     or (v->>'failedNonServingAttempts')::integer<1
     or (v->>'crashedServingDeployments')::integer<>0 then
    raise exception 'failed non-serving candidate should warn, not fail serving app: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_railway_transition_v1(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '66666666-6666-4666-8666-666666666666',
    'Deployment.building',
    'building',
    'INFO',
    'GitHub',
    'main',
    repeat('d',40),
    now()+interval '1 second',
    repeat('e',64),
    'test:transition:building',
    '{"test":true}'::jsonb
  ) into v;

  select foundation.get_defence_railway_transition_summary_v1() into v;
  if (v->>'inFlightDeployments')::integer<1 then
    raise exception 'fresh building transition should be visible in-flight: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_railway_transition_v1(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '77777777-7777-4777-8777-777777777777',
    'Deployment.deploying',
    'deploying',
    'INFO',
    'GitHub',
    'main',
    repeat('f',40),
    now()-interval '30 minutes',
    repeat('1',64),
    'test:transition:stuck',
    '{"test":true}'::jsonb
  ) into v;

  -- Make it current for a dedicated second target instead of relying on clock order.
  insert into foundation.defence_estate_targets(
    target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
    target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
  ) values (
    'railway:test-transition-stuck',
    'Railway Transition Stuck Test',
    'railway',
    '88888888-8888-4888-8888-888888888888',
    '99999999-9999-4999-8999-999999999999',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'primary_service',true,array['active']::text[],'active','{}'::jsonb
  );

  perform foundation.record_defence_railway_transition_v1(
    '88888888-8888-4888-8888-888888888888',
    '99999999-9999-4999-8999-999999999999',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'Deployment.deploying',
    'deploying',
    'INFO',
    'GitHub',
    'main',
    repeat('2',40),
    now()-interval '30 minutes',
    repeat('3',64),
    'test:transition:stuck-current',
    '{"test":true}'::jsonb
  );

  select foundation.get_defence_railway_transition_summary_v1() into v;
  if (v->>'stuckTransitions')::integer<1 then
    raise exception 'stuck release transition should warn: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_railway_transition_v1(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '44444444-4444-4444-8444-444444444444',
    'Deployment.crashed',
    'crashed',
    'CRITICAL',
    'GitHub',
    'main',
    repeat('a',40),
    now()+interval '2 seconds',
    repeat('4',64),
    'test:transition:serving-crashed',
    '{"test":true}'::jsonb
  ) into v;

  select foundation.get_defence_railway_transition_summary_v1() into v;
  if v->>'state'<>'fail'
     or (v->>'crashedServingDeployments')::integer<1 then
    raise exception 'crashed serving deployment must fail transition summary: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.run_defence_railway_transition_sentinel_v1(
    now()+interval '3 seconds'
  ) into v;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where incident_key='railway:test-transition:railway-transition'
      and state='fail'
      and reason_code='serving-deployment-crashed'
  ) then
    raise exception 'serving crash should open fail incident: %',v;
  end if;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where incident_key='railway:test-transition-stuck:railway-transition'
      and state='warning'
      and reason_code='release-transition-stuck'
  ) then
    raise exception 'stuck transition should open warning incident: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  perform foundation.record_defence_railway_transition_v1(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '44444444-4444-4444-8444-444444444444',
    'Deployment.success',
    'success',
    'INFO',
    'GitHub',
    'main',
    repeat('a',40),
    now()+interval '4 seconds',
    repeat('5',64),
    'test:transition:serving-recovered',
    '{"test":true}'::jsonb
  );

  select foundation.run_defence_railway_transition_sentinel_v1(
    now()+interval '5 seconds'
  ) into v;

  if not exists (
    select 1
    from foundation.current_defence_estate_incident_state
    where incident_key='railway:test-transition:railway-transition'
      and event_type='recovered'
      and state='pass'
      and reason_code='healthy'
  ) then
    raise exception 'serving recovery should close transition incident: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.record_defence_railway_transition_v1(
    '11111111-1111-4111-8111-111111111111',
    '22222222-2222-4222-8222-222222222222',
    '33333333-3333-4333-8333-333333333333',
    '55555555-5555-4555-8555-555555555555',
    'Deployment.failed',
    'failed',
    'WARNING',
    'GitHub',
    'main',
    repeat('b',40),
    now(),
    repeat('c',64),
    'test:transition:failed-candidate',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status'<>'replayed' then
    raise exception 'identical webhook evidence should be idempotent: %',v;
  end if;
end;
$$;


do $$
begin
  if has_table_privilege(
       'anon','foundation.defence_railway_transition_events','SELECT'
     )
     or has_table_privilege(
       'authenticated','foundation.current_defence_railway_transition','SELECT'
     ) then
    raise exception 'public roles must not read Railway transition evidence';
  end if;

  if has_function_privilege(
       'authenticated',
       'foundation.record_defence_railway_transition_v1(uuid,uuid,uuid,uuid,text,text,text,text,text,text,timestamptz,text,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'public role unexpectedly records Railway transitions';
  end if;

  begin
    update foundation.defence_railway_transition_events
       set severity='INFO';
    raise exception 'Railway transition history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
