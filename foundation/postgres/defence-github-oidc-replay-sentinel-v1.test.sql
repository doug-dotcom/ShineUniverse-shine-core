begin;

do $$
declare
  v_first jsonb;
  v_replay jsonb;
  v_conflict jsonb;
  v_summary jsonb;
  v_full jsonb;
  v_after timestamptz;
begin
  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/replay-sentinel-test',
    'refs/heads/main',
    'doug-dotcom/replay-sentinel-test/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '700001',
    '1',
    'schedule',
    'shine-defence-release-head',
    'release-head-snapshot',
    'railway:replay-sentinel-test',
    '{"contract":"shine-defence/release-head-snapshot-v1","value":1}'::jsonb
  ) into v_first;

  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/replay-sentinel-test',
    'refs/heads/main',
    'doug-dotcom/replay-sentinel-test/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '700001',
    '1',
    'schedule',
    'shine-defence-release-head',
    'release-head-snapshot',
    'railway:replay-sentinel-test',
    '{"value":1,"contract":"shine-defence/release-head-snapshot-v1"}'::jsonb
  ) into v_replay;

  if v_replay->>'status'<>'replayed-exact' then
    raise exception 'exact retry was not preserved as audit-only replay: %',v_replay;
  end if;

  if exists (
    select 1
    from foundation.github_oidc_replay_alert_events
  ) then
    raise exception 'exact retry unexpectedly produced replay alert';
  end if;

  select foundation.bind_github_oidc_operation_v1(
    'doug-dotcom/replay-sentinel-test',
    'refs/heads/main',
    'doug-dotcom/replay-sentinel-test/.github/workflows/shine-defence-release-head.yml@refs/heads/main',
    '700001',
    '1',
    'schedule',
    'shine-defence-release-head',
    'release-head-snapshot',
    'railway:replay-sentinel-test',
    '{"contract":"shine-defence/release-head-snapshot-v1","value":2}'::jsonb
  ) into v_conflict;

  if v_conflict->>'status'<>'rejected-conflict' then
    raise exception 'changed-payload replay did not fail closed: %',v_conflict;
  end if;

  if (
    select count(*)
    from foundation.github_oidc_replay_alert_events
  )<>1 then
    raise exception 'changed-payload replay did not create exactly one alert';
  end if;

  if not exists (
    select 1
    from foundation.github_oidc_replay_alert_events a
    where a.repository='doug-dotcom/replay-sentinel-test'
      and a.run_id='700001'
      and a.run_attempt='1'
      and a.audience='shine-defence-release-head'
      and a.operation='release-head-snapshot'
      and a.target_key='railway:replay-sentinel-test'
      and a.original_request_sha256<>a.presented_request_sha256
      and a.severity='fail'
  ) then
    raise exception 'replay alert lost the original/conflicting request identity';
  end if;

  v_after := clock_timestamp()+interval '1 second';

  select foundation.get_defence_github_oidc_replay_summary_v1(
    v_after,86400
  ) into v_summary;

  if v_summary->>'state'<>'fail'
     or v_summary->>'reasonCode'<>'github-oidc-replay-conflict'
     or (v_summary->>'conflictsInWindow')::integer<>1
     or (v_summary->>'historicalConflictCount')::integer<>1
     or (v_summary->>'exactReplaysInWindow')::integer<>1
     or jsonb_array_length(v_summary->'attention')<>1 then
    raise exception 'replay Sentinel summary did not escalate conflict: %',v_summary;
  end if;

  select foundation.get_defence_full_estate_summary_v1() into v_full;
  if v_full->>'schemaVersion'<>'1.7.0'
     or v_full#>>'{githubOidcReplay,state}'<>'fail'
     or v_full->>'state'<>'fail' then
    raise exception 'full-estate summary did not surface replay fail state: %',v_full;
  end if;

  select foundation.get_defence_github_oidc_replay_summary_v1(
    v_after+interval '25 hours',86400
  ) into v_summary;

  if v_summary->>'state'<>'pass'
     or (v_summary->>'conflictsInWindow')::integer<>0
     or (v_summary->>'historicalConflictCount')::integer<>1
     or jsonb_array_length(v_summary->'attention')<>0 then
    raise exception 'expired attention window did not preserve history cleanly: %',v_summary;
  end if;
end;
$$;


do $$
begin
  if has_table_privilege(
       'anon','foundation.github_oidc_replay_alert_events','SELECT'
     )
     or has_table_privilege(
       'authenticated','foundation.github_oidc_replay_alert_events','SELECT'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_github_oidc_replay_summary_v1(timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.escalate_github_oidc_replay_conflict_v1()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.escalate_github_oidc_replay_conflict_v1()',
       'EXECUTE'
     ) then
    raise exception 'public roles unexpectedly access OIDC replay Sentinel';
  end if;

  begin
    update foundation.github_oidc_replay_alert_events
       set severity='fail';
    raise exception 'OIDC replay alert history unexpectedly mutated';
  exception
    when sqlstate '55000' then
      null;
  end;

  begin
    delete from foundation.github_oidc_replay_alert_events;
    raise exception 'OIDC replay alert history unexpectedly deleted';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

do $binding_fk_index_test$
begin
  if not exists (
    select 1
    from pg_indexes
    where schemaname='foundation'
      and tablename='github_oidc_replay_alert_events'
      and indexname='github_oidc_replay_alert_events_binding_id_idx'
      and indexdef ilike '%(binding_id)%'
  ) then
    raise exception 'OIDC replay alert binding foreign key lacks covering index';
  end if;
end;
$binding_fk_index_test$;


rollback;
