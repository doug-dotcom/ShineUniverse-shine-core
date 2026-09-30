begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-admission-authority',
  'Admission Authority Parity Test',
  'railway',
  '41111111-1111-4111-8111-111111111111',
  '42222222-2222-4222-8222-222222222222',
  '43333333-3333-4333-8333-333333333333',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-admission-authority',
    'sourceBranch','main'
  )
);

insert into foundation.defence_health_probe_targets(
  target_version,target_id,target_url,response_mode,expected_json,expected_text,
  timeout_milliseconds,evaluation_window_seconds,max_evidence_age_seconds,
  min_samples,degraded_failure_count,unhealthy_failure_count,startup_grace_seconds,
  enabled,effective_at,evidence_ref,evidence_note,probe_mode
) values (
  'test-v1','railway:test-admission-authority','https://example.invalid/health',
  'json_contains','{"status":"ok"}'::jsonb,null,
  10000,1200,600,1,1,2,1200,true,now()-interval '1 hour',
  'test:admission-authority:health-target',
  'Transaction-only authority-current admission fixture.',
  'on_demand'
);

insert into foundation.defence_health_probe_requests(
  probe_request_id,target_id,target_version,target_url,queued_at,evidence_ref,metadata
) values (
  '40000001-0000-4000-8000-000000000001',
  'railway:test-admission-authority','test-v1','https://example.invalid/health',
  now()-interval '5 minutes','test:admission-authority:req','{}'
);

insert into foundation.defence_health_probe_results(
  probe_request_id,target_id,http_status,timed_out,contract_ok,response_at,
  roundtrip_ms,evidence_ref,metadata
) values (
  '40000001-0000-4000-8000-000000000001',
  'railway:test-admission-authority',200,false,true,now()-interval '4 minutes',
  100,'test:admission-authority:res','{}'
);

insert into foundation.defence_runtime_provenance_observations(
  target_id,provider,repository,commit_sha,branch,deployment_id,
  service_name,environment_name,health_probe_result_sequence,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-authority','railway',
  'doug-dotcom/test-admission-authority',repeat('a',40),'main',
  '44444444-4444-4444-8444-444444444444',
  'test-admission-authority','production',
  (select result_sequence from foundation.defence_health_probe_results
   where evidence_ref='test:admission-authority:res'),
  now()-interval '5 minutes',now()+interval '2 hours',
  'test:admission-authority:provenance','{}'
);

insert into foundation.defence_health_observations(
  target_id,health_state,sample_count,failure_count,
  window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
  observed_at,valid_until,evidence_ref,metadata
) values (
  'railway:test-admission-authority','healthy',1,0,
  now()-interval '4 minutes',now()-interval '4 minutes',100,100,
  now()-interval '4 minutes',now()+interval '2 hours',
  'test:admission-authority:health','{}'
);

-- Evidence is still time-fresh, but it names a different reusable authority.
insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-admission-authority',
  'doug-dotcom/test-admission-authority','main',repeat('a',40),
  now()-interval '6 minutes',now()-interval '5 minutes',now()+interval '23 hours',
  'test:admission-authority:stale-authority',
  jsonb_build_object(
    'githubJobWorkflowSha',repeat('d',40),
    'githubJobWorkflowRef',
      'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'||repeat('d',40)
  )
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_defence_release_admission_v1(
    'railway:test-admission-authority',now()
  ) into v;

  if v->>'decision'<>'hold'
     or v->>'reasonCode'<>'source-watch-authority-stale'
     or (v#>>'{evidence,sourceAuthorityCurrent}')::boolean is distinct from false
     or v#>>'{evidence,observedAuthoritySha}'<>repeat('d',40)
     or v#>>'{evidence,expectedAuthoritySha}'<>'7bfd7fe685b4b2da814ac53dafdbfac2350591c8' then
    raise exception 'time-fresh old-authority evidence was not rejected: %',v;
  end if;
end;
$$;

-- A newer observation signed by the active authority restores authority parity.
insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-admission-authority',
  'doug-dotcom/test-admission-authority','main',repeat('a',40),
  now()-interval '6 minutes',now()-interval '1 minute',now()+interval '23 hours',
  'test:admission-authority:current-authority',
  jsonb_build_object(
    'githubJobWorkflowSha','7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'githubJobWorkflowRef',
      'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8'
  )
);

do $$
declare
  v jsonb;
  p jsonb;
begin
  select foundation.evaluate_defence_release_admission_v1(
    'railway:test-admission-authority',now()
  ) into v;

  if v->>'reasonCode'='source-watch-authority-stale'
     or (v#>>'{evidence,sourceAuthorityCurrent}')::boolean is distinct from true then
    raise exception 'current-authority evidence did not restore admissibility: %',v;
  end if;

  select foundation.get_defence_release_authority_parity_summary_v1() into p;
  if exists (
    select 1 from jsonb_array_elements(p->'attention') x
    where x->>'targetId'='railway:test-admission-authority'
  ) then
    raise exception 'current-authority target remained in parity attention: %',p;
  end if;
end;
$$;

rollback;
