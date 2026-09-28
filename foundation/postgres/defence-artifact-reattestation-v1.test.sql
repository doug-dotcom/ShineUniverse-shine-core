begin;

insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,
  required_for_core,lifecycle,metadata
) values (
  'foundation.test-reattest',
  'Defence Reattestation Test',
  'shine-core',
  'internal-service',
  'test/reattest-v1',
  true,
  'active',
  '{}'::jsonb
);

do $$
begin
  begin
    insert into foundation.service_deployment_expectations(
      service_id,environment,expected_runtime_ref,expected_version,
      expected_artifact_sha256,expected_state,source_ref,effective_at,
      evidence_ref,evidence_note
    ) values (
      'foundation.test-reattest','production','internal://test-reattest','1',
      repeat('a',64),'active',null,now(),
      'test:reattest:missing-source','must fail'
    );
    raise exception 'required core expectation unexpectedly accepted without source_ref';
  exception
    when sqlstate '22023' then
      null;
  end;
end;
$$;

insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
) values (
  'foundation.test-reattest','production','internal://test-reattest','1',
  repeat('a',64),'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/1111111111111111111111111111111111111111',
  now(),
  'test:reattest:expectation:v1',
  'exact source-bound test expectation'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,evidence_note,metadata
) values (
  'foundation.test-reattest','production','internal://test-reattest','1',
  repeat('a',64),'active','unknown',now(),'manual-verified',
  'test:reattest:observation:v1','aligned test observation','{}'::jsonb
);

do $$
declare
  v jsonb;
begin
  select foundation.get_defence_reattestation_work_v1(false) into v;

  if v->>'status'<>'work'
     or v->>'serviceId'<>'foundation.test-reattest'
     or v->>'artifactSha256'<>repeat('a',64)
     or v->>'sourceCommit'<>'1111111111111111111111111111111111111111'
     or v->>'sourceRepository'<>'doug-dotcom/ShineUniverse-shine-core' then
    raise exception 'expected exact source-bound reattestation work: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_reattestation_v1(
    'foundation.test-reattest',
    'production',
    repeat('a',64),
    '1111111111111111111111111111111111111111',
    'pass',
    'pass',
    '1.0.0',
    '2222222222222222222222222222222222222222',
    repeat('b',64),
    now(),
    now()+interval '24 hours',
    'test:reattest:pass:v1',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'state'<>'pass' then
    raise exception 'passing reattestation did not record pass: %',v;
  end if;

  select foundation.get_defence_reattestation_work_v1(false) into v;
  if v->>'status'<>'no-work' then
    raise exception 'passing exact artefact assurance should clear work: %',v;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from foundation.defence_external_evidence
    where subject_ref='foundation.test-reattest'
      and artifact_sha256=repeat('a',64)
      and domain='auth'
      and status='pass'
  ) then
    raise exception 'auth evidence missing after pass';
  end if;

  if not exists (
    select 1
    from foundation.defence_external_evidence
    where subject_ref='foundation.test-reattest'
      and artifact_sha256=repeat('a',64)
      and domain='dependencies'
      and status='pass'
  ) then
    raise exception 'dependency evidence missing after pass';
  end if;
end;
$$;

insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,
  expected_artifact_sha256,expected_state,source_ref,effective_at,
  evidence_ref,evidence_note
) values (
  'foundation.test-reattest','production','internal://test-reattest','2',
  repeat('c',64),'active',
  'github://doug-dotcom/ShineUniverse-shine-core/commit/3333333333333333333333333333333333333333',
  now()+interval '1 second',
  'test:reattest:expectation:v2',
  'new exact source-bound test expectation'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,artifact_sha256,
  runtime_state,health_state,observed_at,evidence_kind,evidence_ref,evidence_note,metadata
) values (
  'foundation.test-reattest','production','internal://test-reattest','2',
  repeat('c',64),'active','unknown',now()+interval '1 second','manual-verified',
  'test:reattest:observation:v2','new aligned test observation','{}'::jsonb
);

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_reattestation_v1(
    'foundation.test-reattest',
    'production',
    repeat('c',64),
    '3333333333333333333333333333333333333333',
    'fail',
    'pass',
    '1.0.0',
    '4444444444444444444444444444444444444444',
    repeat('d',64),
    now()+interval '2 seconds',
    now()+interval '24 hours',
    'test:reattest:fail:v2',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'state'<>'fail' then
    raise exception 'failed auth inspection did not record fail: %',v;
  end if;

  select foundation.get_defence_reattestation_work_v1(false) into v;
  if v->>'status'<>'blocked'
     or v->>'reasonCode'<>'existing-failed-evidence' then
    raise exception 'failed exact artefact evidence must block automatic overwrite: %',v;
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.defence_artifact_attestation_events','SELECT')
     or has_table_privilege('authenticated','foundation.defence_artifact_attestation_events','SELECT') then
    raise exception 'public roles must not read artefact attestation events';
  end if;

  if has_function_privilege('anon','foundation.get_defence_reattestation_work_v1(boolean)','EXECUTE')
     or has_function_privilege(
       'authenticated',
       'foundation.record_defence_reattestation_v1(text,text,text,text,text,text,text,text,text,timestamptz,timestamptz,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'public roles must not execute reattestation controls';
  end if;

  begin
    update foundation.defence_artifact_attestation_events
       set state='pass';
    raise exception 'attestation event history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

rollback;
