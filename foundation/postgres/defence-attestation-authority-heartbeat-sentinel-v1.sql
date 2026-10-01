-- Shine Defence attestation-authority heartbeat Sentinel v1.
-- Read-only early warning for a still-valid authority heartbeat approaching the
-- existing fail-closed freshness boundary. This never refreshes authority state.

create or replace function foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
  p_as_of timestamptz default now(),
  p_warning_age_seconds integer default 3600,
  p_fail_closed_age_seconds integer default 5400
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $authority_heartbeat_sentinel$
declare
  v_sync jsonb;
  v_age_seconds bigint;
  v_state text;
  v_band text;
  v_reason text;
  v_impact text;
  v_seconds_until_fail_closed bigint;
  v_observed_at timestamptz;
  v_warning_at timestamptz;
  v_expires_at timestamptz;
begin
  if p_as_of is null
     or p_warning_age_seconds<300
     or p_fail_closed_age_seconds<600
     or p_fail_closed_age_seconds>86400
     or p_warning_age_seconds>=p_fail_closed_age_seconds then
    raise exception 'invalid-attestation-authority-heartbeat-sentinel-window'
      using errcode='22023';
  end if;

  v_sync := foundation.get_defence_attestation_authority_sync_summary_v1(
    p_as_of,p_fail_closed_age_seconds
  );

  v_age_seconds := case
    when coalesce(v_sync->>'receiptAgeSeconds','') ~ '^[0-9]+$'
      then (v_sync->>'receiptAgeSeconds')::bigint
    else null
  end;

  v_observed_at := case
    when v_sync#>>'{latestReceipt,observedAt}' is null then null
    else (v_sync#>>'{latestReceipt,observedAt}')::timestamptz
  end;

  v_warning_at := case
    when v_observed_at is null then null
    else v_observed_at+make_interval(secs=>p_warning_age_seconds)
  end;

  v_expires_at := case
    when v_observed_at is null then null
    else v_observed_at+make_interval(secs=>p_fail_closed_age_seconds)
  end;

  v_seconds_until_fail_closed := case
    when v_age_seconds is null then null
    else greatest(0,p_fail_closed_age_seconds-v_age_seconds)
  end;

  if v_sync->>'state'='warning' then
    v_state := 'warning';
    v_band := 'fail_closed';
    v_reason := v_sync->>'reasonCode';
    v_impact := 'privileged-ingest-fail-closed';
  elsif v_age_seconds>=p_warning_age_seconds then
    v_state := 'warning';
    v_band := 'expiry_risk';
    v_reason := 'attestation-authority-sync-expiry-risk';
    v_impact := 'privileged-ingest-at-risk';
  else
    v_state := 'pass';
    v_band := 'current';
    v_reason := 'attestation-authority-sync-current';
    v_impact := 'none';
  end if;

  return jsonb_build_object(
    'defenceAttestationAuthorityHeartbeatSentinel',
      'shine-defence/attestation-authority-heartbeat-sentinel-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'band',v_band,
    'reasonCode',v_reason,
    'likelyImpact',v_impact,
    'receiptAgeSeconds',v_age_seconds,
    'warningAgeSeconds',p_warning_age_seconds,
    'failClosedAgeSeconds',p_fail_closed_age_seconds,
    'secondsUntilFailClosed',v_seconds_until_fail_closed,
    'warningAt',v_warning_at,
    'failClosedAt',v_expires_at,
    'currentAuthority',v_sync->'currentAuthority',
    'latestReceipt',v_sync->'latestReceipt',
    'sourceState',v_sync->>'state',
    'sourceReasonCode',v_sync->>'reasonCode',
    'evaluatedAt',p_as_of
  );
end;
$authority_heartbeat_sentinel$;

revoke all on function foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
  timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_attestation_authority_heartbeat_sentinel_v1(
  timestamptz,integer,integer
) to foundation_runtime,shine_defence_runtime,service_role;
