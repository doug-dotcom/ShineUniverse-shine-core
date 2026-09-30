begin;

do $$
declare
  a foundation.defence_attestation_authority_activations%rowtype;
begin
  select * into a from foundation.current_defence_attestation_authority;
  if a.authority_sha<>'7bfd7fe685b4b2da814ac53dafdbfac2350591c8'
     or a.workflow_blob_sha<>'71218df29b79919af76115b9180a6afbbd8dbf79'
     or a.activation_kind<>'bootstrap' then
    raise exception 'bootstrap attestation authority state mismatch: %',row_to_json(a);
  end if;
end;
$$;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-authority-parity',
  'Authority Parity Test',
  'railway',
  '31111111-1111-4111-8111-111111111111',
  '32222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333334',
  'primary_service',
  true,
  array['active']::text[],
  'active',
  jsonb_build_object(
    'sourceRepository','doug-dotcom/test-authority-parity',
    'sourceBranch','main'
  )
);

insert into foundation.defence_release_source_head_observations(
  target_id,repository,branch,head_sha,head_committed_at,observed_at,valid_until,
  evidence_ref,metadata
) values (
  'railway:test-authority-parity',
  'doug-dotcom/test-authority-parity',
  'main',
  repeat('a',40),
  now()-interval '2 minutes',
  now()-interval '1 minute',
  now()+interval '23 hours',
  'test:authority-parity:bootstrap',
  jsonb_build_object(
    'githubJobWorkflowSha','7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'githubJobWorkflowRef','doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8'
  )
);

do $$
declare
  s jsonb;
begin
  if not foundation.is_defence_release_source_authority_current_v1(
    jsonb_build_object(
      'githubJobWorkflowSha','7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
      'githubJobWorkflowRef','doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8'
    )
  ) then
    raise exception 'current authority evidence rejected';
  end if;

  select foundation.get_defence_release_authority_parity_summary_v1() into s;
  if not exists (
    select 1
    from jsonb_array_elements(s->'attention') x
    where x->>'targetId'='railway:test-authority-parity'
  ) and not exists (
    select 1
    from foundation.current_defence_release_source_heads h
    where h.target_id='railway:test-authority-parity'
      and foundation.is_defence_release_source_authority_current_v1(h.metadata)
  ) then
    raise exception 'authority-aligned source evidence missing from parity state: %',s;
  end if;
end;
$$;

-- Rotate the active authority while leaving the prior source observation
-- time-fresh. The same evidence must become non-admissible immediately.
insert into foundation.defence_attestation_authority_activations(
  authority_sha,authority_ref,workflow_blob_sha,activation_kind,
  activated_at,evidence_ref,metadata
) values (
  repeat('e',40),
  'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'||repeat('e',40),
  repeat('f',40),
  'promotion',
  now(),
  'test:authority-parity:rotation',
  jsonb_build_object('testOnly',true)
);

do $$
declare
  s jsonb;
  h foundation.defence_release_source_head_observations%rowtype;
begin
  select * into h
  from foundation.current_defence_release_source_heads
  where target_id='railway:test-authority-parity';

  if h.valid_until<=now() then
    raise exception 'fixture source evidence unexpectedly time-stale';
  end if;

  if foundation.is_defence_release_source_authority_current_v1(h.metadata) then
    raise exception 'old-authority evidence remained admissible after rotation';
  end if;

  select foundation.get_defence_release_authority_parity_summary_v1() into s;
  if s->>'state'<>'warning'
     or not exists (
       select 1 from jsonb_array_elements(s->'attention') x
       where x->>'targetId'='railway:test-authority-parity'
         and x->>'reasonCode'='release-source-authority-stale'
         and x->>'observedAuthoritySha'='7bfd7fe685b4b2da814ac53dafdbfac2350591c8'
         and x->>'expectedAuthoritySha'=repeat('e',40)
     ) then
    raise exception 'authority rotation drift not surfaced: %',s;
  end if;
end;
$$;

do $$
begin
  begin
    update foundation.defence_attestation_authority_activations
    set activation_kind='rollback'
    where evidence_ref='test:authority-parity:rotation';
    raise exception 'authority activation history accepted mutation';
  exception
    when sqlstate '55000' then null;
  end;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.defence_attestation_authority_activations','SELECT')
     or has_table_privilege('authenticated','foundation.defence_attestation_authority_activations','SELECT') then
    raise exception 'public roles must not read attestation authority history';
  end if;
end;
$$;

rollback;
