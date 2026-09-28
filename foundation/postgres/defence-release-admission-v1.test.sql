begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-admission',
  'Release Admission Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-admission',
    'sourceBranch','main'
  )
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1','railway:test-admission','https://example.invalid/health',
  'json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,3,1,2,1200,true,now()-interval '2 hours',
  'test:admission:health-target',
  'Transaction-only release admission fixture.',
  'continuous'
);

-- Baseline A: healthy for long enough to become the first canonical release.
insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values
  ('10000001-0000-4000-8000-000000000001','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '86 minutes','test:admission:a:req1','{}'),
  ('10000001-0000-4000-8000-000000000002','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '81 minutes','test:admission:a:req2','{}'),
  ('10000001-0000-4000-8000-000000000003','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '76 minutes','test:admission:a:req3','{}');

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values
  ('10000001-0000-4000-8000-000000000001','railway:test-admission',200,false,true,now()-interval '85 minutes',100,'test:admission:a:res1','{}'),
  ('10000001-0000-4000-8000-000000000002','railway:test-admission',200,false,true,now()-interval '80 minutes',100,'test:admission:a:res2','{}'),
  ('10000001-0000-4000-8000-000000000003','railway:test-admission',200,false,true,now()-interval '75 minutes',100,'test:admission:a:res3','{}');

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','railway','doug-dotcom/test-admission',repeat('a',40),'main',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','test-admission','production',
  (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission:a:res1'),
  now()-interval '90 minutes',now()+interval '2 hours','test:admission:a:provenance','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','doug-dotcom/test-admission','main',repeat('a',40),
  now()-interval '91 minutes',now()-interval '90 minutes',now()+interval '2 hours',
  'test:admission:a:source','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','healthy',3,0,
  now()-interval '85 minutes',now()-interval '75 minutes',100,100,
  now()-interval '75 minutes',now()+interval '2 hours','test:admission:a:health','{}'
);

do $$
declare
  v jsonb;
begin
  select foundation.reconcile_defence_release_admission_v1(
    now()-interval '70 minutes'
  ) into v;

  if not exists (
    select 1 from foundation.current_defence_release_admission
    where target_id='railway:test-admission'
      and admission_state='admitted'
      and canonical_commit_sha=repeat('a',40)
      and canonical_deployment_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
  ) then
    raise exception 'healthy baseline release should become canonical: %',v;
  end if;
end;
$$;


-- Candidate B: first appears with only one post-release proof, so the previous
-- canonical remains authoritative while B soaks.
insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values
  ('10000002-0000-4000-8000-000000000001','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '46 minutes','test:admission:b:req1','{}'),
  ('10000002-0000-4000-8000-000000000002','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '41 minutes','test:admission:b:req2','{}'),
  ('10000002-0000-4000-8000-000000000003','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '36 minutes','test:admission:b:req3','{}');

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values
  ('10000002-0000-4000-8000-000000000001','railway:test-admission',200,false,true,now()-interval '45 minutes',100,'test:admission:b:res1','{}'),
  ('10000002-0000-4000-8000-000000000002','railway:test-admission',200,false,true,now()-interval '40 minutes',100,'test:admission:b:res2','{}'),
  ('10000002-0000-4000-8000-000000000003','railway:test-admission',200,false,true,now()-interval '35 minutes',100,'test:admission:b:res3','{}');

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','railway','doug-dotcom/test-admission',repeat('b',40),'main',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','test-admission','production',
  (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission:b:res1'),
  now()-interval '50 minutes',now()+interval '2 hours','test:admission:b:provenance','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','doug-dotcom/test-admission','main',repeat('b',40),
  now()-interval '51 minutes',now()-interval '50 minutes',now()+interval '2 hours',
  'test:admission:b:source','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','healthy',1,0,
  now()-interval '45 minutes',now()-interval '45 minutes',100,100,
  now()-interval '45 minutes',now()+interval '2 hours','test:admission:b:health-early','{}'
);

do $$
declare
  v jsonb;
begin
  select foundation.reconcile_defence_release_admission_v1(
    now()-interval '44 minutes'
  ) into v;

  if not exists (
    select 1 from foundation.current_defence_release_admission
    where target_id='railway:test-admission'
      and admission_state='soaking'
      and serving_commit_sha=repeat('b',40)
      and canonical_commit_sha=repeat('a',40)
  ) then
    raise exception 'new candidate should soak while old canonical remains authoritative: %',v;
  end if;
end;
$$;

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','healthy',3,0,
  now()-interval '45 minutes',now()-interval '35 minutes',100,100,
  now()-interval '35 minutes',now()+interval '2 hours','test:admission:b:health-clear','{}'
);

do $$
declare
  v jsonb;
begin
  select foundation.reconcile_defence_release_admission_v1(
    now()-interval '34 minutes'
  ) into v;

  if not exists (
    select 1 from foundation.current_defence_release_admission
    where target_id='railway:test-admission'
      and admission_state='admitted'
      and canonical_commit_sha=repeat('b',40)
      and canonical_deployment_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
  ) then
    raise exception 'candidate with complete soak evidence should be admitted: %',v;
  end if;
end;
$$;


-- Candidate C begins serving, then immediately fails health. Defence must keep
-- B canonical and recommend B as the rollback target.
insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values
  ('10000003-0000-4000-8000-000000000001','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '21 minutes','test:admission:c:req1','{}'),
  ('10000003-0000-4000-8000-000000000002','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '19 minutes','test:admission:c:req2','{}');

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values
  ('10000003-0000-4000-8000-000000000001','railway:test-admission',200,false,true,now()-interval '20 minutes',100,'test:admission:c:res1','{}'),
  ('10000003-0000-4000-8000-000000000002','railway:test-admission',503,false,false,now()-interval '18 minutes',100,'test:admission:c:res2','{}');

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','railway','doug-dotcom/test-admission',repeat('c',40),'main',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc','test-admission','production',
  (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission:c:res1'),
  now()-interval '20 minutes',now()+interval '2 hours','test:admission:c:provenance','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','doug-dotcom/test-admission','main',repeat('c',40),
  now()-interval '21 minutes',now()-interval '20 minutes',now()+interval '2 hours',
  'test:admission:c:source','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','unhealthy',2,1,
  now()-interval '20 minutes',now()-interval '18 minutes',100,100,
  now()-interval '18 minutes',now()+interval '2 hours','test:admission:c:health-fail','{}'
);

do $$
declare
  v jsonb;
begin
  select foundation.reconcile_defence_release_admission_v1(
    now()-interval '17 minutes'
  ) into v;

  if not exists (
    select 1 from foundation.current_defence_release_admission
    where target_id='railway:test-admission'
      and admission_state='rollback-recommended'
      and serving_commit_sha=repeat('c',40)
      and canonical_commit_sha=repeat('b',40)
      and rollback_commit_sha=repeat('b',40)
  ) then
    raise exception 'failed serving candidate should recommend previous canonical rollback: %',v;
  end if;
end;
$$;


-- The provider rolls back B as a new deployment instance. Commit identity is
-- canonical even though the Railway deployment id changes.
insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values
  ('10000004-0000-4000-8000-000000000001','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '11 minutes','test:admission:rb:req1','{}'),
  ('10000004-0000-4000-8000-000000000002','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '7 minutes','test:admission:rb:req2','{}'),
  ('10000004-0000-4000-8000-000000000003','railway:test-admission','test-v1','https://example.invalid/health',now()-interval '4 minutes','test:admission:rb:req3','{}');

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values
  ('10000004-0000-4000-8000-000000000001','railway:test-admission',200,false,true,now()-interval '10 minutes',100,'test:admission:rb:res1','{}'),
  ('10000004-0000-4000-8000-000000000002','railway:test-admission',200,false,true,now()-interval '6 minutes',100,'test:admission:rb:res2','{}'),
  ('10000004-0000-4000-8000-000000000003','railway:test-admission',200,false,true,now()-interval '3 minutes',100,'test:admission:rb:res3','{}');

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','railway','doug-dotcom/test-admission',repeat('b',40),'main',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd','test-admission','production',
  (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission:rb:res1'),
  now()-interval '10 minutes',now()+interval '2 hours','test:admission:rollback:provenance','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','doug-dotcom/test-admission','main',repeat('b',40),
  now()-interval '50 minutes',now()-interval '10 minutes',now()+interval '2 hours',
  'test:admission:rollback:source','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission','healthy',3,0,
  now()-interval '10 minutes',now()-interval '3 minutes',100,100,
  now()-interval '3 minutes',now()+interval '2 hours','test:admission:rollback:health','{}'
);

do $$
declare
  v jsonb;
begin
  select foundation.reconcile_defence_release_admission_v1(
    now()-interval '2 minutes'
  ) into v;

  if not exists (
    select 1 from foundation.current_defence_release_admission
    where target_id='railway:test-admission'
      and admission_state='rollback-observed'
      and serving_commit_sha=repeat('b',40)
      and canonical_commit_sha=repeat('b',40)
      and canonical_deployment_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'
  ) then
    raise exception 'rollback to canonical commit should be recognised under new deployment id: %',v;
  end if;

  select foundation.get_defence_release_admission_summary_v1() into v;
  if (v->>'rollbackRecommendedTargets')::integer<>0 then
    raise exception 'rollback observation should clear active rollback recommendation: %',v;
  end if;
end;
$$;


-- Bootstrap safety: if Defence comes online while a brand-new candidate is
-- already serving, the most recent older stable release becomes canonical.
insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-admission-bootstrap',
  'Release Admission Bootstrap Test',
  'railway',
  '21111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222223',
  '23333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-admission-bootstrap',
    'sourceBranch','main'
  )
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1','railway:test-admission-bootstrap','https://example.invalid/health',
  'json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,3,1,2,1200,true,now()-interval '1 hour',
  'test:admission:bootstrap:health-target',
  'Transaction-only bootstrap fixture.',
  'continuous'
);

insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values
  ('20000001-0000-4000-8000-000000000001','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '41 minutes','test:admission:bootstrap:old:req1','{}'),
  ('20000001-0000-4000-8000-000000000002','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '31 minutes','test:admission:bootstrap:old:req2','{}'),
  ('20000001-0000-4000-8000-000000000003','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '21 minutes','test:admission:bootstrap:old:req3','{}'),
  ('20000002-0000-4000-8000-000000000001','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '5 minutes','test:admission:bootstrap:new:req1','{}');

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values
  ('20000001-0000-4000-8000-000000000001','railway:test-admission-bootstrap',200,false,true,now()-interval '40 minutes',100,'test:admission:bootstrap:old:res1','{}'),
  ('20000001-0000-4000-8000-000000000002','railway:test-admission-bootstrap',200,false,true,now()-interval '30 minutes',100,'test:admission:bootstrap:old:res2','{}'),
  ('20000001-0000-4000-8000-000000000003','railway:test-admission-bootstrap',200,false,true,now()-interval '20 minutes',100,'test:admission:bootstrap:old:res3','{}'),
  ('20000002-0000-4000-8000-000000000001','railway:test-admission-bootstrap',200,false,true,now()-interval '4 minutes',100,'test:admission:bootstrap:new:res1','{}');

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values
  (
    'railway:test-admission-bootstrap','railway','doug-dotcom/test-admission-bootstrap',
    repeat('e',40),'main','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'test-admission-bootstrap','production',
    (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission:bootstrap:old:res1'),
    now()-interval '40 minutes',now()+interval '1 hour',
    'test:admission:bootstrap:old:prov1','{}'
  ),
  (
    'railway:test-admission-bootstrap','railway','doug-dotcom/test-admission-bootstrap',
    repeat('e',40),'main','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'test-admission-bootstrap','production',
    (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission:bootstrap:old:res3'),
    now()-interval '20 minutes',now()+interval '1 hour',
    'test:admission:bootstrap:old:prov2','{}'
  ),
  (
    'railway:test-admission-bootstrap','railway','doug-dotcom/test-admission-bootstrap',
    repeat('f',40),'main','ffffffff-ffff-4fff-8fff-ffffffffffff',
    'test-admission-bootstrap','production',
    (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission:bootstrap:new:res1'),
    now()-interval '4 minutes',now()+interval '1 hour',
    'test:admission:bootstrap:new:prov','{}'
  );

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-bootstrap','doug-dotcom/test-admission-bootstrap','main',
  repeat('f',40),now()-interval '5 minutes',now()-interval '4 minutes',
  now()+interval '1 hour','test:admission:bootstrap:new:source',
  '{"deploymentRelevant":true}'::jsonb
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-bootstrap','healthy',1,0,
  now()-interval '4 minutes',now()-interval '4 minutes',100,100,
  now()-interval '4 minutes',now()+interval '1 hour',
  'test:admission:bootstrap:new:health','{}'
);

do $bootstrap$
declare
  v jsonb;
begin
  select foundation.reconcile_defence_release_admission_v1(now()) into v;

  if not exists (
    select 1
    from foundation.current_defence_release_admission
    where target_id='railway:test-admission-bootstrap'
      and admission_state='soaking'
      and serving_commit_sha=repeat('f',40)
      and canonical_commit_sha=repeat('e',40)
      and canonical_deployment_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
  ) then
    raise exception 'young candidate should bootstrap the prior stable release as canonical: %',v;
  end if;
end;
$bootstrap$;


do $$
begin
  if has_table_privilege('anon','foundation.defence_release_admission_events','SELECT')
     or has_table_privilege('authenticated','foundation.current_defence_release_admission','SELECT') then
    raise exception 'public roles must not read release admission controls';
  end if;

  if has_function_privilege(
       'anon',
       'foundation.evaluate_defence_release_admission_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.reconcile_defence_release_admission_v1(timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'public roles must not execute release admission controls';
  end if;

  begin
    update foundation.defence_release_admission_events
       set reason_code='mutation';
    raise exception 'release admission history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
