begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-sleep-posture','Sleep Posture Test','railway',
  '51111111-1111-4111-8111-111111111111',
  '52222222-2222-4222-8222-222222222222',
  '53333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active','sleeping']::text[],'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-sleep-posture',
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
  'test-v1','railway:test-sleep-posture',
  'https://example.invalid/health','json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,1,1,2,1200,true,now()-interval '4 hours',
  'test:sleep-posture:health-target','Transaction-only fixture.','on_demand'
);

insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values (
  '50000001-0000-4000-8000-000000000001',
  'railway:test-sleep-posture','test-v1','https://example.invalid/health',
  now()-interval '181 minutes','test:sleep-posture:req','{}'
);

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values (
  '50000001-0000-4000-8000-000000000001',
  'railway:test-sleep-posture',200,false,true,
  now()-interval '180 minutes',100,'test:sleep-posture:res','{}'
);

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-sleep-posture','railway',
  'doug-dotcom/test-sleep-posture',repeat('a',40),'main',
  '54444444-4444-4444-8444-444444444444',
  'test-sleep-posture','production',
  (select result_sequence from foundation.defence_health_probe_results
   where evidence_ref='test:sleep-posture:res'),
  now()-interval '180 minutes',now()-interval '60 minutes',
  'test:sleep-posture:provenance','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-sleep-posture','healthy',1,0,
  now()-interval '180 minutes',now()-interval '180 minutes',100,100,
  now()-interval '180 minutes',now()-interval '170 minutes',
  'test:sleep-posture:old-health','{}'
);

insert into foundation.defence_release_admission_events(
  target_id,admission_state,reason_code,
  serving_deployment_id,serving_commit_sha,
  canonical_deployment_id,canonical_commit_sha,
  rollback_deployment_id,rollback_commit_sha,
  observed_at,evidence,evidence_ref
) values (
  'railway:test-sleep-posture','canonical','canonical-serving',
  '54444444-4444-4444-8444-444444444444',repeat('a',40),
  '54444444-4444-4444-8444-444444444444',repeat('a',40),
  null,null,now()-interval '150 minutes','{"test":true}'::jsonb,
  'test:sleep-posture:canonical'
);

insert into foundation.defence_railway_transition_events(
  target_id,project_id,environment_id,service_id,deployment_id,
  event_type,transition_state,severity,source_kind,branch,commit_sha,
  occurred_at,payload_sha256,evidence_ref,metadata
) values (
  'railway:test-sleep-posture',
  '51111111-1111-4111-8111-111111111111',
  '52222222-2222-4222-8222-222222222222',
  '53333333-3333-4333-8333-333333333333',
  '54444444-4444-4444-8444-444444444444',
  'deployment_status','sleeping',null,'test','main',repeat('a',40),
  now()-interval '149 minutes',repeat('1',64),
  'test:sleep-posture:transition','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-sleep-posture',
  'doug-dotcom/test-sleep-posture','main',repeat('a',40),
  now()-interval '4 hours',now()-interval '1 minute',now()+interval '23 hours',
  'test:sleep-posture:source-current',
  jsonb_build_object(
    'githubJobWorkflowSha',
      (select authority_sha from foundation.current_defence_attestation_authority),
    'githubJobWorkflowRef',
      (select authority_ref from foundation.current_defence_attestation_authority)
  )
);

do $expected_sleep$
declare
  v jsonb;
begin
  select foundation.get_defence_on_demand_sleep_posture_v1(
    'railway:test-sleep-posture',now()
  ) into v;

  if v->>'state'<>'expected_sleep_stale'
     or v->>'reasonCode'<>'on-demand-sleep-expected-stale'
     or v->>'nextAction'<>'none'
     or (v#>>'{evidence,onDemandCanonicalUnchanged}')::boolean is distinct from true
     or (v#>>'{evidence,sourceAhead}')::boolean is distinct from false
     or v->>'rawEstateStateOverridden'<>'false' then
    raise exception 'Expected sleeping stale posture misclassified: %',v;
  end if;
end;
$expected_sleep$;

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-sleep-posture',
  'doug-dotcom/test-sleep-posture','main',repeat('b',40),
  now()-interval '1 minute',now(),now()+interval '23 hours',
  'test:sleep-posture:source-ahead',
  jsonb_build_object(
    'githubJobWorkflowSha',
      (select authority_sha from foundation.current_defence_attestation_authority),
    'githubJobWorkflowRef',
      (select authority_ref from foundation.current_defence_attestation_authority)
  )
);

do $source_ahead$
declare
  v jsonb;
begin
  select foundation.get_defence_on_demand_sleep_posture_v1(
    'railway:test-sleep-posture',now()+interval '1 second'
  ) into v;

  if v->>'state'<>'revalidation_required'
     or v->>'reasonCode'<>'on-demand-source-ahead'
     or v->>'nextAction'<>'wake_and_revalidate_on_demand_target'
     or (v#>>'{evidence,sourceAhead}')::boolean is distinct from true then
    raise exception 'Source-ahead sleeping posture was not fail-closed: %',v;
  end if;
end;
$source_ahead$;

do $sleep_security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_on_demand_sleep_posture_v1(text,timestamp with time zone)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_on_demand_sleep_posture_v1(text,timestamp with time zone)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_on_demand_sleep_posture_v1(text,timestamp with time zone)',
       'EXECUTE'
     ) then
    raise exception 'On-demand sleep posture privilege boundary invalid';
  end if;
end;
$sleep_security$;

rollback;
