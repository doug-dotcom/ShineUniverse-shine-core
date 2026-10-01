begin;

do $sentinel_current$
declare
  recorded jsonb;
  sentinel jsonb;
  t timestamptz := clock_timestamp();
begin
  select foundation.record_defence_attestation_authority_sync_receipt_v1(
    1,
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '71218df29b79919af76115b9180a6afbbd8dbf79',
    repeat('1',40),
    repeat('2',40),
    repeat('3',40),
    'asserted-current',
    '1000000001',
    '1',
    'schedule',
    t,
    'test:authority-heartbeat-sentinel:current',
    '{}'::jsonb
  ) into recorded;

  if recorded->>'status'<>'recorded' then
    raise exception 'Sentinel current fixture rejected: %',recorded;
  end if;

  select foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
    t+interval '15 minutes',3600,5400
  ) into sentinel;

  if sentinel->>'state'<>'pass'
     or sentinel->>'band'<>'current'
     or sentinel->>'reasonCode'<>'attestation-authority-sync-current'
     or (sentinel->>'secondsUntilFailClosed')::bigint<>4500 then
    raise exception 'Current heartbeat misclassified: %',sentinel;
  end if;
end;
$sentinel_current$;

do $sentinel_expiry_risk$
declare
  sentinel jsonb;
  latest_at timestamptz;
begin
  select max(observed_at) into latest_at
  from foundation.defence_attestation_authority_sync_receipts;

  select foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
    latest_at+interval '70 minutes',3600,5400
  ) into sentinel;

  if sentinel->>'state'<>'warning'
     or sentinel->>'band'<>'expiry_risk'
     or sentinel->>'reasonCode'<>'attestation-authority-sync-expiry-risk'
     or sentinel->>'likelyImpact'<>'privileged-ingest-at-risk'
     or (sentinel->>'secondsUntilFailClosed')::bigint<>1200 then
    raise exception 'Pre-expiry heartbeat risk not surfaced: %',sentinel;
  end if;
end;
$sentinel_expiry_risk$;

do $sentinel_fail_closed$
declare
  sentinel jsonb;
  latest_at timestamptz;
begin
  select max(observed_at) into latest_at
  from foundation.defence_attestation_authority_sync_receipts;

  select foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
    latest_at+interval '2 hours',3600,5400
  ) into sentinel;

  if sentinel->>'state'<>'warning'
     or sentinel->>'band'<>'fail_closed'
     or sentinel->>'reasonCode'<>'attestation-authority-sync-receipt-stale'
     or sentinel->>'likelyImpact'<>'privileged-ingest-fail-closed'
     or (sentinel->>'secondsUntilFailClosed')::bigint<>0 then
    raise exception 'Fail-closed heartbeat not surfaced: %',sentinel;
  end if;
end;
$sentinel_fail_closed$;

do $sentinel_security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(timestamp with time zone,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(timestamp with time zone,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(timestamp with time zone,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Heartbeat Sentinel privilege boundary invalid';
  end if;
end;
$sentinel_security$;

do $sentinel_invalid_window$
begin
  begin
    perform foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
      clock_timestamp(),5400,5400
    );
    raise exception 'Invalid Sentinel threshold window accepted';
  exception
    when sqlstate '22023' then null;
  end;
end;
$sentinel_invalid_window$;

rollback;
