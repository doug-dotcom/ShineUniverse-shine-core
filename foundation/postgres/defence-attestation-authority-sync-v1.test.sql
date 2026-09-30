begin;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_attestation_authority_activation_v1(
    repeat('e',40),
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'||repeat('e',40),
    repeat('f',40),
    'promotion',
    '2026-09-30T07:58:39.000Z'::timestamptz,
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    null,
    'test:authority-sync:promotion-e',
    jsonb_build_object('lineageSequence',2)
  ) into v;

  if v->>'status'<>'recorded'
     or v->>'authoritySha'<>repeat('e',40) then
    raise exception 'valid promotion rejected: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_attestation_authority_activation_v1(
    repeat('e',40),
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'||repeat('e',40),
    repeat('f',40),
    'promotion',
    '2026-09-30T07:58:39.000Z'::timestamptz,
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    null,
    'test:authority-sync:promotion-e',
    jsonb_build_object('lineageSequence',2)
  ) into v;

  if v->>'status'<>'replayed' then
    raise exception 'exact activation replay was not idempotent: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_attestation_authority_activation_v1(
    repeat('a',40),
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'||repeat('a',40),
    repeat('b',40),
    'promotion',
    '2026-09-30T08:58:39.000Z'::timestamptz,
    repeat('d',40),
    null,
    'test:authority-sync:wrong-predecessor',
    jsonb_build_object('lineageSequence',3)
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'authority-predecessor-mismatch' then
    raise exception 'predecessor skip accepted: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_attestation_authority_activation_v1(
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '71218df29b79919af76115b9180a6afbbd8dbf79',
    'promotion',
    '2026-09-30T08:58:39.000Z'::timestamptz,
    repeat('e',40),
    null,
    'test:authority-sync:promotion-replay-bootstrap',
    jsonb_build_object('lineageSequence',3)
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'promotion-authority-replay' then
    raise exception 'promotion replay of old authority accepted: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.record_defence_attestation_authority_activation_v1(
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    repeat('c',40),
    'rollback',
    '2026-09-30T08:58:39.000Z'::timestamptz,
    repeat('e',40),
    1,
    'test:authority-sync:rollback-wrong-blob',
    jsonb_build_object('lineageSequence',3)
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'rollback-workflow-blob-mismatch' then
    raise exception 'altered rollback workflow bytes accepted: %',v;
  end if;
end;
$$;

do $$
declare
  v jsonb;
  a foundation.defence_attestation_authority_activations%rowtype;
begin
  select foundation.record_defence_attestation_authority_activation_v1(
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '71218df29b79919af76115b9180a6afbbd8dbf79',
    'rollback',
    '2026-09-30T08:58:39.000Z'::timestamptz,
    repeat('e',40),
    1,
    'test:authority-sync:rollback-bootstrap',
    jsonb_build_object('lineageSequence',3)
  ) into v;

  if v->>'status'<>'recorded'
     or v->>'activationKind'<>'rollback' then
    raise exception 'valid rollback rejected: %',v;
  end if;

  select * into a from foundation.current_defence_attestation_authority;
  if a.authority_sha<>'7bfd7fe685b4b2da814ac53dafdbfac2350591c8'
     or a.activation_kind<>'rollback' then
    raise exception 'rollback did not become current authority';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege(
    'anon',
    'foundation.record_defence_attestation_authority_activation_v1(text,text,text,text,timestamptz,text,bigint,text,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'foundation.record_defence_attestation_authority_activation_v1(text,text,text,text,timestamptz,text,bigint,text,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'shine_defence_runtime',
    'foundation.record_defence_attestation_authority_activation_v1(text,text,text,text,timestamptz,text,bigint,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'authority activation recorder exposed beyond service role';
  end if;
end;
$$;

rollback;
