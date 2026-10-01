begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-sleep-overlay','Sleep Overlay Test','railway',
  '61111111-1111-4111-8111-111111111111',
  '62222222-2222-4222-8222-222222222222',
  '63333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active','sleeping']::text[],'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-sleep-overlay',
    'sourceBranch','main',
    'sleepAllowed',true,
    'sleepAware',true,
    'healthMonitoringMode','on_demand'
  )
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1','railway:test-sleep-overlay',
  'https://example.invalid/health','json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,1,1,2,1200,true,now()-interval '4 hours',
  'test:sleep-overlay:health-target','Transaction-only fixture.','on_demand'
);

insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values (
  '60000001-0000-4000-8000-000000000001',
  'railway:test-sleep-overlay','test-v1','https://example.invalid/health',
  now()-interval '181 minutes','test:sleep-overlay:req','{}'
);

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values (
  '60000001-0000-4000-8000-000000000001',
  'railway:test-sleep-overlay',200,false,true,
  now()-interval '180 minutes',100,'test:sleep-overlay:res','{}'
);

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-sleep-overlay','railway',
  'doug-dotcom/test-sleep-overlay',repeat('a',40),'main',
  '64444444-4444-4444-8444-444444444444',
  'test-sleep-overlay','production',
  (select result_sequence from foundation.defence_health_probe_results
   where evidence_ref='test:sleep-overlay:res'),
  now()-interval '180 minutes',now()-interval '60 minutes',
  'test:sleep-overlay:provenance','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-sleep-overlay','healthy',1,0,
  now()-interval '180 minutes',now()-interval '180 minutes',100,100,
  now()-interval '180 minutes',now()-interval '170 minutes',
  'test:sleep-overlay:old-health','{}'
);

insert into foundation.defence_estate_observations(
  target_id,runtime_state,health_state,deployment_ref,version_ref,artifact_ref,
  observed_at,valid_until,evidence_kind,evidence_ref,metadata
) values (
  'railway:test-sleep-overlay','sleeping','unknown',
  '64444444-4444-4444-8444-444444444444',repeat('a',40),null,
  now()-interval '180 minutes',now()-interval '60 minutes',
  'manual-verified','test:sleep-overlay:estate-stale','{}'
);

insert into foundation.defence_release_admission_events(
  target_id,admission_state,reason_code,
  serving_deployment_id,serving_commit_sha,
  canonical_deployment_id,canonical_commit_sha,
  rollback_deployment_id,rollback_commit_sha,
  observed_at,evidence,evidence_ref
) values (
  'railway:test-sleep-overlay','canonical','canonical-serving',
  '64444444-4444-4444-8444-444444444444',repeat('a',40),
  '64444444-4444-4444-8444-444444444444',repeat('a',40),
  null,null,now()-interval '150 minutes','{"test":true}'::jsonb,
  'test:sleep-overlay:canonical'
);

insert into foundation.defence_railway_transition_events(
  target_id,project_id,environment_id,service_id,deployment_id,
  event_type,transition_state,severity,source_kind,branch,commit_sha,
  occurred_at,payload_sha256,evidence_ref,metadata
) values (
  'railway:test-sleep-overlay',
  '61111111-1111-4111-8111-111111111111',
  '62222222-2222-4222-8222-222222222222',
  '63333333-3333-4333-8333-333333333333',
  '64444444-4444-4444-8444-444444444444',
  'Deployment.SLEEPING','sleeping','INFO','test','main',repeat('a',40),
  now()-interval '149 minutes',repeat('2',64),
  'test:sleep-overlay:transition','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-sleep-overlay',
  'doug-dotcom/test-sleep-overlay','main',repeat('a',40),
  now()-interval '4 hours',now()-interval '1 minute',now()+interval '23 hours',
  'test:sleep-overlay:source-current',
  jsonb_build_object(
    'githubJobWorkflowSha',
      (select authority_sha from foundation.current_defence_attestation_authority),
    'githubJobWorkflowRef',
      (select authority_ref from foundation.current_defence_attestation_authority)
  )
);

do $expected_overlay$
declare
  v jsonb;
begin
  select foundation.get_defence_operational_attention_sleep_aware_v1(
    now(),2700,3,0.5
  ) into v;

  if not exists (
       select 1
       from jsonb_array_elements(v->'targetItems') x
       where x->>'targetId'='railway:test-sleep-overlay'
         and x->>'causeClass'='expected_on_demand_sleep'
         and x->>'attentionClass'='sleep_expected'
         and x->>'nextAction'='none'
     )
     or coalesce((v#>>'{counts,expectedOnDemandSleepTargets}')::integer,0)<1
     or v#>>'{sleepAwareOverlay,rawEstateStateOverridden}'<>'false' then
    raise exception 'Expected on-demand sleep was not separated from stale attention: %',v;
  end if;
end;
$expected_overlay$;

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-sleep-overlay',
  'doug-dotcom/test-sleep-overlay','main',repeat('b',40),
  now()-interval '1 minute',now(),now()+interval '23 hours',
  'test:sleep-overlay:source-ahead',
  jsonb_build_object(
    'githubJobWorkflowSha',
      (select authority_sha from foundation.current_defence_attestation_authority),
    'githubJobWorkflowRef',
      (select authority_ref from foundation.current_defence_attestation_authority)
  )
);

do $revalidation_overlay$
declare
  v jsonb;
begin
  select foundation.get_defence_operational_attention_sleep_aware_v1(
    now()+interval '1 second',2700,3,0.5
  ) into v;

  if not exists (
       select 1
       from jsonb_array_elements(v->'targetItems') x
       where x->>'targetId'='railway:test-sleep-overlay'
         and x->>'causeClass'='on_demand_revalidation_required'
         and x->>'attentionClass'='target_investigation'
         and x->>'nextAction'='wake_and_revalidate_on_demand_target'
     )
     or coalesce((v#>>'{counts,onDemandRevalidationTargets}')::integer,0)<1 then
    raise exception 'Source-ahead on-demand target did not require revalidation: %',v;
  end if;
end;
$revalidation_overlay$;

rollback;
