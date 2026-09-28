begin;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from foundation.defence_estate_targets
  where provider='railway'
    and metadata->>'runtimeProvenanceRequired'='true'
    and metadata->>'sourceRepository' is not null
    and metadata->>'sourceBranch' is not null;

  if v_count<>14 then
    raise exception 'expected 14 Railway targets with provenance identity, got %',v_count;
  end if;
end;
$$;


do $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_request uuid;
  v_sequence bigint;
  v jsonb;
begin
  select * into v_target
  from foundation.current_defence_health_probe_target
  where target_id='railway:daash';

  insert into foundation.defence_health_probe_requests(
    target_id,target_version,external_request_id,target_url,queued_at,evidence_ref,metadata
  ) values (
    v_target.target_id,v_target.target_version,null,v_target.target_url,now(),
    'test:runtime-provenance:request:valid','{}'::jsonb
  )
  returning probe_request_id into v_request;

  v_sequence := foundation.record_defence_health_probe_result_v1(
    v_request,200,false,null,true,now(),100,null,
    'test:runtime-provenance:result:valid','{}'::jsonb
  );

  select foundation.record_defence_runtime_provenance_v1(
    'railway:daash',
    jsonb_build_object(
      'x-shine-runtime-provider','railway',
      'x-shine-runtime-repository','doug-dotcom/Shine-DaAsh',
      'x-shine-runtime-commit',repeat('a',40),
      'x-shine-runtime-branch','main',
      'x-shine-runtime-deployment','11111111-1111-4111-8111-111111111111',
      'x-shine-runtime-service','shine-daash-x',
      'x-shine-runtime-environment','production'
    ),
    v_sequence
  ) into v;

  if v->>'status'<>'recorded'
     or v->>'commitSha'<>repeat('a',40)
     or v->>'deploymentId'<>'11111111-1111-4111-8111-111111111111' then
    raise exception 'valid runtime provenance not recorded: %',v;
  end if;
end;
$$;


do $$
begin
  if not exists (
    select 1
    from foundation.current_defence_runtime_provenance
    where target_id='railway:daash'
      and repository='doug-dotcom/Shine-DaAsh'
      and commit_sha=repeat('a',40)
      and deployment_id='11111111-1111-4111-8111-111111111111'
  ) then
    raise exception 'current runtime provenance missing';
  end if;

  if not exists (
    select 1
    from foundation.current_defence_estate_observations
    where target_id='railway:daash'
      and evidence_kind='runtime-self-report'
      and deployment_ref='11111111-1111-4111-8111-111111111111'
      and artifact_ref=repeat('a',40)
      and version_ref='main'
  ) then
    raise exception 'runtime provenance did not refresh serving estate observation';
  end if;
end;
$$;


do $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_request uuid;
  v_sequence bigint;
  v jsonb;
  v_before integer;
  v_after integer;
begin
  select count(*) into v_before
  from foundation.defence_runtime_provenance_observations
  where target_id='railway:daash';

  select * into v_target
  from foundation.current_defence_health_probe_target
  where target_id='railway:daash';

  insert into foundation.defence_health_probe_requests(
    target_id,target_version,external_request_id,target_url,queued_at,evidence_ref,metadata
  ) values (
    v_target.target_id,v_target.target_version,null,v_target.target_url,now(),
    'test:runtime-provenance:request:wrong-repo','{}'::jsonb
  )
  returning probe_request_id into v_request;

  v_sequence := foundation.record_defence_health_probe_result_v1(
    v_request,200,false,null,true,now(),100,null,
    'test:runtime-provenance:result:wrong-repo','{}'::jsonb
  );

  select foundation.record_defence_runtime_provenance_v1(
    'railway:daash',
    jsonb_build_object(
      'x-shine-runtime-provider','railway',
      'x-shine-runtime-repository','attacker/wrong-repo',
      'x-shine-runtime-commit',repeat('b',40),
      'x-shine-runtime-branch','main',
      'x-shine-runtime-deployment','22222222-2222-4222-8222-222222222222',
      'x-shine-runtime-service','shine-daash-x',
      'x-shine-runtime-environment','production'
    ),
    v_sequence
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'runtime-provenance-repository-mismatch' then
    raise exception 'wrong repo should be rejected: %',v;
  end if;

  select count(*) into v_after
  from foundation.defence_runtime_provenance_observations
  where target_id='railway:daash';

  if v_after<>v_before then
    raise exception 'rejected provenance mutated history';
  end if;
end;
$$;


do $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_request uuid;
  v_sequence bigint;
  v jsonb;
begin
  select * into v_target
  from foundation.current_defence_health_probe_target
  where target_id='railway:daash';

  insert into foundation.defence_health_probe_requests(
    target_id,target_version,external_request_id,target_url,queued_at,evidence_ref,metadata
  ) values (
    v_target.target_id,v_target.target_version,null,v_target.target_url,now(),
    'test:runtime-provenance:request:bad-health','{}'::jsonb
  )
  returning probe_request_id into v_request;

  v_sequence := foundation.record_defence_health_probe_result_v1(
    v_request,503,false,null,false,now(),100,null,
    'test:runtime-provenance:result:bad-health','{}'::jsonb
  );

  select foundation.record_defence_runtime_provenance_v1(
    'railway:daash',
    jsonb_build_object(
      'x-shine-runtime-provider','railway',
      'x-shine-runtime-repository','doug-dotcom/Shine-DaAsh',
      'x-shine-runtime-commit',repeat('c',40),
      'x-shine-runtime-branch','main',
      'x-shine-runtime-deployment','33333333-3333-4333-8333-333333333333',
      'x-shine-runtime-service','shine-daash-x',
      'x-shine-runtime-environment','production'
    ),
    v_sequence
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'health-contract-not-passed' then
    raise exception 'failed health must not carry provenance: %',v;
  end if;
end;
$$;


-- Use a transaction-only target so existing live provenance can never
-- invalidate the missing-provenance acceptance case.
insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata,
  registered_at,updated_at
) values (
  'railway:test-provenance-gap',
  'Runtime Provenance Gap Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'runtimeProvenanceContract','shine-defence/runtime-provenance-v1',
    'runtimeProvenanceRequired',true,
    'runtimeProvenanceEffectiveAt',(now()-interval '1 hour')::text,
    'sourceRepository','doug-dotcom/test-provenance-gap',
    'sourceBranch','main'
  ),
  now()-interval '1 hour',
  now()-interval '1 hour'
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1',
  'railway:test-provenance-gap',
  'https://example.invalid/health',
  'json_contains',
  '{"status":"ok"}'::jsonb,
  null,
  10000,1200,600,1,1,1,1200,
  true,
  now()-interval '1 hour',
  'test:runtime-provenance:gap-health-target',
  'Transaction-only provenance gap fixture.',
  'continuous'
);

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,observed_at,valid_until,
  evidence_kind,evidence_ref,metadata
) values (
  'railway:test-provenance-gap','active','unknown',now(),now()+interval '2 hours',
  'manual-verified','test:runtime-provenance:gap-provider','{}'::jsonb
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-provenance-gap','healthy',1,0,now()-interval '5 minutes',now(),
  100,100,now(),now()+interval '1 hour',
  'test:runtime-provenance:gap-health','{}'::jsonb
);

do $$
declare
  v jsonb;
begin
  select foundation.run_defence_estate_sentinel_v1(now()+interval '1 second') into v;

  if not exists (
    select 1
    from foundation.current_defence_estate_incidents
    where target_id='railway:test-provenance-gap'
      and state='warning'
      and reason_code='runtime-provenance-missing'
  ) then
    raise exception 'missing continuous provenance must create its own warning: %',v;
  end if;
end;
$$;


do $$
begin
  if has_table_privilege(
       'anon',
       'foundation.defence_runtime_provenance_observations',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'foundation.current_defence_runtime_provenance',
       'SELECT'
     ) then
    raise exception 'public roles must not read runtime provenance';
  end if;

  if has_function_privilege(
       'authenticated',
       'foundation.record_defence_runtime_provenance_v1(text,jsonb,bigint)',
       'EXECUTE'
     ) then
    raise exception 'public role unexpectedly records runtime provenance';
  end if;

  begin
    update foundation.defence_runtime_provenance_observations
       set branch='mutation';
    raise exception 'runtime provenance history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
