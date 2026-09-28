begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-admission-sleep',
  'Release Admission Sleep-Aware Test',
  'railway',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active','sleeping']::text[],'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-admission-sleep',
    'sourceBranch','main'
  )
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1','railway:test-admission-sleep',
  'https://example.invalid/health','json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,1,1,1,1200,true,now()-interval '3 hours',
  'test:admission-sleep:health-target',
  'Transaction-only sleep-aware admission fixture.',
  'on_demand'
);

insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values (
  '30000001-0000-4000-8000-000000000001',
  'railway:test-admission-sleep','test-v1',
  'https://example.invalid/health',
  now()-interval '121 minutes',
  'test:admission-sleep:req1','{}'
);

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values (
  '30000001-0000-4000-8000-000000000001',
  'railway:test-admission-sleep',200,false,true,
  now()-interval '120 minutes',100,
  'test:admission-sleep:res1','{}'
);

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-sleep','railway',
  'doug-dotcom/test-admission-sleep',repeat('a',40),'main',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'test-admission-sleep','production',
  (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission-sleep:res1'),
  now()-interval '120 minutes',now()+interval '4 hours',
  'test:admission-sleep:provenance-original','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-admission-sleep','doug-dotcom/test-admission-sleep','main',
  repeat('a',40),now()-interval '3 hours',now()-interval '2 minutes',
  now()+interval '2 hours','test:admission-sleep:source',
  '{"deploymentRelevant":true}'::jsonb
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-sleep','healthy',1,0,
  now()-interval '120 minutes',now()-interval '120 minutes',100,100,
  now()-interval '120 minutes',now()-interval '110 minutes',
  'test:admission-sleep:old-health','{}'
);

insert into foundation.defence_release_admission_events(
  target_id,admission_state,reason_code,
  serving_deployment_id,serving_commit_sha,
  canonical_deployment_id,canonical_commit_sha,
  rollback_deployment_id,rollback_commit_sha,
  observed_at,evidence,evidence_ref
) values (
  'railway:test-admission-sleep','admitted','baseline-evidence-clear',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',repeat('a',40),
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',repeat('a',40),
  null,null,
  now()-interval '90 minutes',
  '{"test":true}'::jsonb,
  'test:admission-sleep:canonical'
);

do $sleep$
declare
  v jsonb;
begin
  select foundation.evaluate_defence_release_admission_v1(
    'railway:test-admission-sleep',now()
  ) into v;

  if v->>'decision'<>'canonical'
     or v->>'reasonCode'<>'canonical-serving'
     or coalesce((v#>>'{evidence,onDemandCanonicalUnchanged}')::boolean,false) is not true
     or coalesce((v#>>'{evidence,healthFreshAndHealthy}')::boolean,true) is not false then
    raise exception 'unchanged sleeping canonical release should remain canonical without forced wake: %',v;
  end if;
end;
$sleep$;

-- Same commit under a new deployment identity must not inherit the old health proof.
insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-sleep','railway',
  'doug-dotcom/test-admission-sleep',repeat('a',40),'main',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'test-admission-sleep','production',
  (select result_sequence from foundation.defence_health_probe_results where evidence_ref='test:admission-sleep:res1'),
  now()-interval '1 minute',now()+interval '4 hours',
  'test:admission-sleep:provenance-redeploy','{}'
);

do $redeploy$
declare
  v jsonb;
begin
  select foundation.evaluate_defence_release_admission_v1(
    'railway:test-admission-sleep',now()
  ) into v;

  if v->>'decision'<>'hold'
     or v->>'reasonCode'<>'serving-health-not-clear-no-rollback-anchor'
     or coalesce((v#>>'{evidence,onDemandCanonicalUnchanged}')::boolean,true) is not false then
    raise exception 'new deployment of canonical commit must require fresh on-demand health: %',v;
  end if;
end;
$redeploy$;

rollback;
