begin;

do $heartbeat_missing$
declare
  v jsonb;
begin
  select foundation.get_defence_attestation_authority_sync_summary_v1(now(),5400) into v;
  if v->>'state'<>'warning'
     or v->>'reasonCode'<>'attestation-authority-sync-receipt-missing' then
    raise exception 'missing authority sync receipt not surfaced: %',v;
  end if;
end;
$heartbeat_missing$;

do $heartbeat_record$
declare
  v jsonb;
  s jsonb;
  t timestamptz := clock_timestamp();
begin
  select foundation.record_defence_attestation_authority_sync_receipt_v1(
    1,
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '71218df29b79919af76115b9180a6afbbd8dbf79',
    repeat('a',40),
    repeat('b',40),
    repeat('c',40),
    'asserted-current',
    '123456789',
    '1',
    'schedule',
    t,
    'test:authority-sync-heartbeat:1',
    jsonb_build_object('test',true)
  ) into v;

  if v->>'status'<>'recorded' then
    raise exception 'valid authority sync receipt rejected: %',v;
  end if;

  select foundation.get_defence_attestation_authority_sync_summary_v1(t+interval '1 minute',5400) into s;
  if s->>'state'<>'pass'
     or s->>'reasonCode'<>'attestation-authority-sync-current'
     or s#>>'{latestReceipt,githubEvent}'<>'schedule'
     or s#>>'{latestReceipt,publisherCommitSha}'<>repeat('a',40) then
    raise exception 'fresh authority sync receipt did not produce pass: %',s;
  end if;
end;
$heartbeat_record$;

do $heartbeat_replay$
declare
  first_result jsonb;
  second_result jsonb;
  t timestamptz := clock_timestamp();
begin
  select foundation.record_defence_attestation_authority_sync_receipt_v1(
    1,
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '71218df29b79919af76115b9180a6afbbd8dbf79',
    repeat('d',40),
    repeat('e',40),
    repeat('f',40),
    'asserted-current',
    '223456789',
    '1',
    'push',
    t,
    'test:authority-sync-heartbeat:replay',
    '{}'::jsonb
  ) into first_result;

  select foundation.record_defence_attestation_authority_sync_receipt_v1(
    1,
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '71218df29b79919af76115b9180a6afbbd8dbf79',
    repeat('d',40),
    repeat('e',40),
    repeat('f',40),
    'asserted-current',
    '223456789',
    '1',
    'push',
    t,
    'test:authority-sync-heartbeat:replay',
    '{}'::jsonb
  ) into second_result;

  if first_result->>'status'<>'recorded'
     or second_result->>'status'<>'replayed' then
    raise exception 'authority sync receipt retry was not idempotent: %, %',first_result,second_result;
  end if;
end;
$heartbeat_replay$;

do $heartbeat_mismatch$
declare
  v jsonb;
begin
  select foundation.record_defence_attestation_authority_sync_receipt_v1(
    1,
    repeat('9',40),
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@'||repeat('9',40),
    repeat('8',40),
    repeat('7',40),
    repeat('6',40),
    repeat('5',40),
    'asserted-current',
    '323456789',
    '1',
    'workflow_dispatch',
    clock_timestamp(),
    'test:authority-sync-heartbeat:mismatch',
    '{}'::jsonb
  ) into v;

  if v->>'status'<>'rejected'
     or v->>'reasonCode'<>'authority-sync-receipt-current-state-mismatch' then
    raise exception 'mismatched authority sync receipt accepted: %',v;
  end if;
end;
$heartbeat_mismatch$;

do $heartbeat_stale$
declare
  latest_at timestamptz;
  v jsonb;
begin
  select max(observed_at) into latest_at
  from foundation.defence_attestation_authority_sync_receipts;

  select foundation.get_defence_attestation_authority_sync_summary_v1(
    latest_at+interval '2 hours',5400
  ) into v;

  if v->>'state'<>'warning'
     or v->>'reasonCode'<>'attestation-authority-sync-receipt-stale' then
    raise exception 'stale authority sync receipt not surfaced: %',v;
  end if;
end;
$heartbeat_stale$;

do $heartbeat_security$
begin
  if has_table_privilege('anon','foundation.defence_attestation_authority_sync_receipts','SELECT')
     or has_table_privilege('authenticated','foundation.defence_attestation_authority_sync_receipts','SELECT')
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.record_defence_attestation_authority_sync_receipt_v1(bigint,text,text,text,text,text,text,text,text,text,text,timestamp with time zone,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'authority sync receipt write boundary exposed';
  end if;

  begin
    update foundation.defence_attestation_authority_sync_receipts
       set sync_outcome='replayed';
    raise exception 'authority sync receipt history unexpectedly mutable';
  exception
    when sqlstate '55000' then null;
  end;
end;
$heartbeat_security$;

rollback;
