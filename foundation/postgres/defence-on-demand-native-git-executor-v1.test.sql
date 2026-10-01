begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-revalidation-control','Revalidation Control Test','railway',
  '71111111-1111-4111-8111-111111111111',
  '72222222-2222-4222-8222-222222222222',
  '73333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active','sleeping']::text[],'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-revalidation-control',
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
  'test-v1','railway:test-revalidation-control',
  'https://example.invalid/health','json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,1,1,2,1200,true,now()-interval '4 hours',
  'test:revalidation-control:health-target','Transaction-only fixture.','on_demand'
);

insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values (
  '70000001-0000-4000-8000-000000000001',
  'railway:test-revalidation-control','test-v1',
  'https://example.invalid/health',
  now()-interval '181 minutes',
  'test:revalidation-control:req-health','{}'
);

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values (
  '70000001-0000-4000-8000-000000000001',
  'railway:test-revalidation-control',200,false,true,
  now()-interval '180 minutes',100,
  'test:revalidation-control:res-health','{}'
);

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-revalidation-control','railway',
  'doug-dotcom/test-revalidation-control',repeat('a',40),'main',
  '74444444-4444-4444-8444-444444444444',
  'test-revalidation-control','production',
  (select result_sequence from foundation.defence_health_probe_results
   where evidence_ref='test:revalidation-control:res-health'),
  now()-interval '180 minutes',now()-interval '60 minutes',
  'test:revalidation-control:provenance','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-revalidation-control','healthy',1,0,
  now()-interval '180 minutes',now()-interval '180 minutes',100,100,
  now()-interval '180 minutes',now()-interval '170 minutes',
  'test:revalidation-control:old-health','{}'
);

insert into foundation.defence_release_admission_events(
  target_id,admission_state,reason_code,
  serving_deployment_id,serving_commit_sha,
  canonical_deployment_id,canonical_commit_sha,
  rollback_deployment_id,rollback_commit_sha,
  observed_at,evidence,evidence_ref
) values (
  'railway:test-revalidation-control','canonical','canonical-serving',
  '74444444-4444-4444-8444-444444444444',repeat('a',40),
  '74444444-4444-4444-8444-444444444444',repeat('a',40),
  null,null,now()-interval '150 minutes','{"test":true}'::jsonb,
  'test:revalidation-control:canonical'
);

insert into foundation.defence_railway_transition_events(
  target_id,project_id,environment_id,service_id,deployment_id,
  event_type,transition_state,severity,source_kind,branch,commit_sha,
  occurred_at,payload_sha256,evidence_ref,metadata
) values (
  'railway:test-revalidation-control',
  '71111111-1111-4111-8111-111111111111',
  '72222222-2222-4222-8222-222222222222',
  '73333333-3333-4333-8333-333333333333',
  '74444444-4444-4444-8444-444444444444',
  'Deployment.SLEEPING','sleeping','INFO','test','main',repeat('a',40),
  now()-interval '149 minutes',repeat('7',64),
  'test:revalidation-control:transition','{}'
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-revalidation-control',
  'doug-dotcom/test-revalidation-control','main',repeat('b',40),
  now()-interval '1 minute',now()-interval '30 seconds',now()+interval '23 hours',
  'test:revalidation-control:source-ahead',
  jsonb_build_object(
    'githubJobWorkflowSha',
      (select authority_sha from foundation.current_defence_attestation_authority),
    'githubJobWorkflowRef',
      (select authority_ref from foundation.current_defence_attestation_authority)
  )
);

do $request$
declare
  r jsonb;
  s jsonb;
begin
  select foundation.request_defence_on_demand_revalidation_v1(
    '70000002-0000-4000-8000-000000000001',
    'railway:test-revalidation-control',
    'human:test-owner',
    now(),
    now()+interval '30 minutes'
  ) into r;

  if r->>'status'<>'requested'
     or r->>'nextAction'<>'approve_on_demand_revalidation_request'
     or r->>'approvalGranted'<>'false'
     or r->>'executionAuthorityGranted'<>'false'
     or r->>'executesExternalMutation'<>'false' then
    raise exception 'Revalidation request boundary invalid: %',r;
  end if;

  select foundation.get_defence_on_demand_revalidation_status_v1(
    'railway:test-revalidation-control',now()
  ) into s;

  if s->>'state'<>'pending_approval'
     or s->>'nextAction'<>'approve_on_demand_revalidation_request' then
    raise exception 'Pending approval status invalid: %',s;
  end if;
end;
$request$;


insert into foundation.defence_on_demand_executor_profiles(
  target_id,direct_railway_enabled,native_git_enabled,
  native_git_repository,native_git_branch,native_git_trigger_path_prefix,
  native_git_proof_commit_sha,native_git_proof_deployment_id,
  native_git_proven_at,effective_at,evidence_ref,metadata
) values (
  'railway:test-revalidation-control',false,true,
  'doug-dotcom/test-revalidation-control','main',
  'security/shine-defence/revalidation-triggers/',
  repeat('a',40),
  '74444444-4444-4444-8444-444444444444',
  now()-interval '1 day',
  now()-interval '1 day',
  'test:native-git-executor:profile',
  '{"test":true}'::jsonb
);

set local role shine_defence_on_demand_approver;

do $approve_native$
declare
  r jsonb;
begin
  select foundation.approve_defence_on_demand_revalidation_v1(
    '71000003-0000-4000-8000-000000000001',
    '70000002-0000-4000-8000-000000000001',
    'human:test-owner',
    'explicit-human',
    now(),
    now()+interval '10 minutes'
  ) into r;

  if r->>'status'<>'approved'
     or r->>'selectedExecutorMode'<>'native_git'
     or r->>'nextAction'<>'prepare_native_git_revalidation_candidate'
     or r->>'executionAuthorityGranted'<>'false' then
    raise exception 'Native Git approval selection invalid: %',r;
  end if;
end;
$approve_native$;

reset role;
set local role shine_defence_on_demand_executor;

do $candidate_required$
begin
  begin
    perform foundation.admit_defence_on_demand_revalidation_execution_v1(
      '71000004-0000-4000-8000-000000000001',
      '71000003-0000-4000-8000-000000000001',
      now()
    );
    raise exception 'Native Git admission without candidate unexpectedly accepted';
  exception
    when raise_exception then
      if sqlerrm<>'on-demand-native-git-candidate-required' then
        raise;
      end if;
  end;
end;
$candidate_required$;

do $prepare_candidate$
declare
  r jsonb;
  s jsonb;
begin
  select foundation.record_defence_on_demand_native_git_candidate_v1(
    '71000005-0000-4000-8000-000000000001',
    '71000003-0000-4000-8000-000000000001',
    'doug-dotcom/test-revalidation-control',
    'main',
    repeat('b',40),
    repeat('c',40),
    'security/shine-defence/revalidation-triggers/test-native.json',
    repeat('d',64),
    'executor:test',
    now(),
    now()+interval '8 minutes',
    'test:native-git-executor:candidate',
    '{"test":true,"runtimeCodeChanged":false}'::jsonb
  ) into r;

  if r->>'status'<>'candidate-prepared'
     or r->>'candidateCommitSha'<>repeat('c',40)
     or r->>'nextAction'<>'admit_on_demand_revalidation_execution'
     or r->>'executionAuthorityGranted'<>'false'
     or r->>'externalMutationPerformed'<>'false' then
    raise exception 'Native Git candidate record invalid: %',r;
  end if;

  select foundation.get_defence_on_demand_revalidation_status_v1(
    'railway:test-revalidation-control',now()
  ) into s;

  if s->>'state'<>'candidate_prepared'
     or s->>'nextAction'<>'admit_on_demand_revalidation_execution'
     or s#>>'{candidate,baseHeadSha}'<>repeat('b',40)
     or s#>>'{candidate,candidateCommitSha}'<>repeat('c',40) then
    raise exception 'Native Git candidate status invalid: %',s;
  end if;
end;
$prepare_candidate$;

do $admit_native$
declare
  r jsonb;
begin
  select foundation.admit_defence_on_demand_revalidation_execution_v1(
    '71000006-0000-4000-8000-000000000001',
    '71000003-0000-4000-8000-000000000001',
    now()
  ) into r;

  if r->>'status'<>'admitted'
     or r->>'selectedExecutorMode'<>'native_git'
     or r->>'nextAction'<>'execute_native_git_fast_forward'
     or r#>>'{executionEnvelope,constraints,executorMode}'<>'native_git'
     or r#>>'{executionEnvelope,constraints,requiredBranchBaseSha}'<>repeat('b',40)
     or r#>>'{executionEnvelope,constraints,expectedSourceHeadSha}'<>repeat('c',40)
     or r#>>'{executionEnvelope,sourceCandidate,candidateCommitSha}'<>repeat('c',40)
     or r#>>'{executionEnvelope,sourceCandidate,baseHeadSha}'<>repeat('b',40)
     or r->>'executionAuthorityGranted'<>'true' then
    raise exception 'Native Git execution admission invalid: %',r;
  end if;
end;
$admit_native$;

do $candidate_append_only$
begin
  begin
    update foundation.defence_on_demand_native_git_candidates
       set candidate_commit_sha=repeat('e',40)
     where candidate_id='71000005-0000-4000-8000-000000000001';
    raise exception 'Native Git candidate unexpectedly mutated';
  exception
    when sqlstate '55000' then null;
    when insufficient_privilege then null;
  end;
end;
$candidate_append_only$;

reset role;

do $native_security$
begin
  if has_table_privilege(
       'anon',
       'foundation.defence_on_demand_native_git_candidates',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'foundation.defence_on_demand_native_git_candidates',
       'SELECT'
     )
     or has_function_privilege(
       'service_role',
       'foundation.record_defence_on_demand_native_git_candidate_v1(uuid,uuid,text,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,text,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_on_demand_executor',
       'foundation.record_defence_on_demand_native_git_candidate_v1(uuid,uuid,text,text,text,text,text,text,text,timestamp with time zone,timestamp with time zone,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Native Git executor privilege boundary invalid';
  end if;
end;
$native_security$;

rollback;
