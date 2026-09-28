begin;

insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,
  required_for_core,lifecycle,metadata
)
values (
  'test.layer33.service',
  'Layer 33 Test Service',
  'shine-core',
  'internal-service',
  'test/layer33',
  false,
  'active',
  '{}'::jsonb
);

do $layer33$
declare
  v_first jsonb;
  v_replay jsonb;
  v_second_run jsonb;
  v_health jsonb;
  v_count integer;
  v_receipt uuid;
begin
  select foundation.submit_service_deployment_receipt_v1(
    'test.layer33.service',
    'test',
    'manual-verified',
    'test://layer33/runtime',
    '1',
    repeat('a',64),
    'active',
    'github://doug-dotcom/ShineUniverse-shine-core/commit/1111111111111111111111111111111111111111',
    'test:provider:layer33:v1',
    now(),
    'github-actions-oidc',
    jsonb_build_object(
      'transport','github-oidc',
      'githubRunId','330001',
      'githubRunAttempt','1',
      'githubEvent','push',
      'githubRepository','doug-dotcom/ShineUniverse-shine-core',
      'githubRef','refs/heads/main',
      'githubWorkflowRef','doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
      'githubWorkflowSha',repeat('2',40),
      'rollback',false
    )
  ) into v_first;

  if v_first->>'status'<>'reconciled'
     or v_first->>'publicationOutcome'<>'accepted-new'
     or v_first->>'publicationId' is null then
    raise exception 'new receipt should create publication event: %',v_first;
  end if;

  v_receipt := (v_first->>'receiptId')::uuid;

  select foundation.submit_service_deployment_receipt_v1(
    'test.layer33.service',
    'test',
    'manual-verified',
    'test://layer33/runtime',
    '1',
    repeat('a',64),
    'active',
    'github://doug-dotcom/ShineUniverse-shine-core/commit/1111111111111111111111111111111111111111',
    'test:provider:layer33:v1',
    now(),
    'github-actions-oidc',
    jsonb_build_object(
      'transport','github-oidc',
      'githubRunId','330001',
      'githubRunAttempt','1',
      'githubEvent','push',
      'githubRepository','doug-dotcom/ShineUniverse-shine-core',
      'githubRef','refs/heads/main',
      'githubWorkflowRef','doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
      'githubWorkflowSha',repeat('2',40),
      'rollback',false
    )
  ) into v_replay;

  if v_replay->>'status'<>'replayed'
     or v_replay->>'publicationId'<>v_first->>'publicationId' then
    raise exception 'same workflow attempt should replay publication idempotently: first=% replay=%',v_first,v_replay;
  end if;

  select count(*) into v_count
  from foundation.service_deployment_receipt_publications
  where receipt_id=v_receipt;

  if v_count<>1 then
    raise exception 'same workflow attempt should create one publication event, got %',v_count;
  end if;

  select foundation.submit_service_deployment_receipt_v1(
    'test.layer33.service',
    'test',
    'manual-verified',
    'test://layer33/runtime',
    '1',
    repeat('a',64),
    'active',
    'github://doug-dotcom/ShineUniverse-shine-core/commit/1111111111111111111111111111111111111111',
    'test:provider:layer33:v1',
    now(),
    'github-actions-oidc',
    jsonb_build_object(
      'transport','github-oidc',
      'githubRunId','330002',
      'githubRunAttempt','1',
      'githubEvent','push',
      'githubRepository','doug-dotcom/ShineUniverse-shine-core',
      'githubRef','refs/heads/main',
      'githubWorkflowRef','doug-dotcom/ShineUniverse-shine-core/.github/workflows/publish-foundation-deployment-receipt.yml@refs/heads/main',
      'githubWorkflowSha',repeat('3',40),
      'rollback',false
    )
  ) into v_second_run;

  if v_second_run->>'status'<>'replayed'
     or v_second_run->>'publicationOutcome'<>'replayed-existing'
     or v_second_run->>'publicationId'=v_first->>'publicationId' then
    raise exception 'new workflow run should create a new replay attestation: %',v_second_run;
  end if;

  select count(*) into v_count
  from foundation.service_deployment_receipt_publications
  where receipt_id=v_receipt;

  if v_count<>2 then
    raise exception 'two distinct workflow runs should create two publication events, got %',v_count;
  end if;

  select foundation.get_deployment_receipt_publication_health_v1(
    'test.layer33.service','test',86400
  ) into v_health;

  if v_health->>'state'<>'pass'
     or v_health->>'assurance'<>'github-oidc'
     or v_health->>'reasonCode'<>'publication-attested-by-github-oidc' then
    raise exception 'latest OIDC publication should pass attestation health: %',v_health;
  end if;

  if v_health#>>'{publication,transportRunId}'<>'330002' then
    raise exception 'attestation health should point at latest OIDC run: %',v_health;
  end if;
end;
$layer33$;


do $layer33$
declare
  v_health jsonb;
begin
  select foundation.get_deployment_receipt_publication_health_v1(
    'foundation.gateway','production',86400
  ) into v_health;

  if v_health->>'state' not in ('unknown','degraded','pass') then
    raise exception 'production attestation state should be typed: %',v_health;
  end if;
end;
$layer33$;


do $layer33$
begin
  begin
    update foundation.service_deployment_receipt_publications
    set transport='mutated'
    where service_id='test.layer33.service';
    raise exception 'append-only publication mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;

  if has_table_privilege(
    'foundation_gateway',
    'foundation.service_deployment_receipt_publications',
    'INSERT'
  ) then
    raise exception 'Gateway must not directly insert publication attestations';
  end if;

  if has_table_privilege(
    'anon',
    'foundation.service_deployment_receipt_publications',
    'SELECT'
  ) then
    raise exception 'anon must not read deployment publication attestations';
  end if;

  if not has_function_privilege(
    'foundation_runtime',
    'foundation.get_deployment_receipt_publication_health_v1(text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'foundation_runtime must read publication attestation health';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.get_deployment_receipt_publication_health_v1(text,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'anon must not read publication attestation health';
  end if;
end;
$layer33$;

rollback;
