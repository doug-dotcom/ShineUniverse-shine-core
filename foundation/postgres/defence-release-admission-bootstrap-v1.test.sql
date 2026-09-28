begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-admission-bootstrap',
  'Release Admission Bootstrap Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active']::text[],'active',
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
  'test-v1','railway:test-admission-bootstrap',
  'https://example.invalid/health','json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,3,1,2,1200,true,now()-interval '2 hours',
  'test:admission-bootstrap:health-target',
  'Transaction-only canonical bootstrap fixture.',
  'continuous'
);

insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values
  ('20000001-0000-4000-8000-000000000001','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '66 minutes','test:admission-bootstrap:a:req1','{}'),
  ('20000001-0000-4000-8000-000000000002','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '61 minutes','test:admission-bootstrap:a:req2','{}'),
  ('20000001-0000-4000-8000-000000000003','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '56 minutes','test:admission-bootstrap:a:req3','{}'),
  ('20000002-0000-4000-8000-000000000001','railway:test-admission-bootstrap','test-v1','https://example.invalid/health',now()-interval '5 minutes','test:admission-bootstrap:b:req1','{}');

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values
  ('20000001-0000-4000-8000-000000000001','railway:test-admission-bootstrap',200,false,true,now()-interval '65 minutes',100,'test:admission-bootstrap:a:res1','{}'),
  ('20000001-0000-4000-8000-000000000002','railway:test-admission-bootstrap',200,false,true,now()-interval '60 minutes',100,'test:admission-bootstrap:a:res2','{}'),
  ('20000001-0000-4000-8000-000000000003','railway:test-admission-bootstrap',200,false,true,now()-interval '55 minutes',100,'test:admission-bootstrap:a:res3','{}'),
  ('20000002-0000-4000-8000-000000000001','railway:test-admission-bootstrap',200,false,true,now()-interval '4 minutes',100,'test:admission-bootstrap:b:res1','{}');

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values
  (
    'railway:test-admission-bootstrap','railway',
    'doug-dotcom/test-admission-bootstrap',repeat('a',40),'main',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'test-admission-bootstrap','production',
    (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission-bootstrap:a:res1'),
    now()-interval '70 minutes',now()+interval '2 hours',
    'test:admission-bootstrap:a:prov-first','{}'
  ),
  (
    'railway:test-admission-bootstrap','railway',
    'doug-dotcom/test-admission-bootstrap',repeat('a',40),'main',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'test-admission-bootstrap','production',
    (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission-bootstrap:a:res3'),
    now()-interval '50 minutes',now()+interval '2 hours',
    'test:admission-bootstrap:a:prov-last','{}'
  ),
  (
    'railway:test-admission-bootstrap','railway',
    'doug-dotcom/test-admission-bootstrap',repeat('b',40),'main',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'test-admission-bootstrap','production',
    (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission-bootstrap:b:res1'),
    now()-interval '5 minutes',now()+interval '2 hours',
    'test:admission-bootstrap:b:prov','{}'
  );

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-admission-bootstrap','doug-dotcom/test-admission-bootstrap','main',
  repeat('b',40),now()-interval '6 minutes',now()-interval '5 minutes',
  now()+interval '2 hours','test:admission-bootstrap:b:source',
  '{"deploymentRelevant":true}'::jsonb
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-bootstrap','healthy',1,0,
  now()-interval '4 minutes',now()-interval '4 minutes',100,100,
  now()-interval '4 minutes',now()+interval '2 hours',
  'test:admission-bootstrap:b:health','{}'
);

do $bootstrap$
declare
  v jsonb;
begin
  select foundation.evaluate_defence_release_admission_v1(
    'railway:test-admission-bootstrap',now()
  ) into v;

  if v->>'decision'<>'soaking'
     or v#>>'{rollbackTarget,commitSha}'<>repeat('a',40)
     or v#>>'{rollbackTarget,deploymentId}'<>'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     or coalesce((v#>>'{evidence,bootstrapRollbackFound}')::boolean,false) is not true then
    raise exception 'stable prior release must anchor soaking candidate rollback: %',v;
  end if;

  select foundation.reconcile_defence_release_admission_v1(now()) into v;

  if not exists (
    select 1
    from foundation.current_defence_release_admission
    where target_id='railway:test-admission-bootstrap'
      and admission_state='soaking'
      and serving_commit_sha=repeat('b',40)
      and canonical_commit_sha=repeat('a',40)
      and rollback_commit_sha=repeat('a',40)
  ) then
    raise exception 'bootstrap reconcile must preserve prior stable release as canonical anchor: %',v;
  end if;
end;
$bootstrap$;

rollback;
