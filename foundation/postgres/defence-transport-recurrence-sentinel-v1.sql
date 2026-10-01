-- Shine Defence transport recurrence sentinel v1.
-- Detect repeated same-cycle shared transport failures without suppressing raw
-- health evidence or absorbing target-specific failures into transport attribution.

create or replace function foundation.get_defence_transport_recurrence_sentinel_v1(
  p_as_of timestamptz default now(),
  p_lookback_seconds integer default 3600,
  p_min_affected_targets integer default 3,
  p_min_failure_fraction numeric default 0.5,
  p_recurrence_threshold integer default 3
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $transport_recurrence_sentinel$
declare
  v_raw_estate jsonb;
  v_qualifying_cycle_count integer := 0;
  v_tls_dominant_cycle_count integer := 0;
  v_latest record;
  v_recovery record;
begin
  if p_as_of is null
     or p_lookback_seconds < 600
     or p_lookback_seconds > 604800
     or p_min_affected_targets < 2
     or p_min_affected_targets > 100
     or p_min_failure_fraction <= 0
     or p_min_failure_fraction > 1
     or p_recurrence_threshold < 2
     or p_recurrence_threshold > 100 then
    raise exception 'invalid-transport-recurrence-sentinel-window'
      using errcode='22023';
  end if;

  v_raw_estate := foundation.get_defence_estate_summary_v1();

  with ranked as (
    select
      date_trunc('minute',q.queued_at) as cycle_at,
      q.target_id,
      r.result_sequence,
      r.http_status,
      r.timed_out,
      r.error_message,
      r.contract_ok,
      r.response_at,
      row_number() over (
        partition by date_trunc('minute',q.queued_at),q.target_id
        order by r.response_at desc,r.result_sequence desc
      ) as rn
    from foundation.defence_health_probe_requests q
    join foundation.defence_health_probe_results r
      on r.probe_request_id=q.probe_request_id
    join foundation.defence_estate_targets t
      on t.target_id=q.target_id
    where q.queued_at > p_as_of-make_interval(secs=>p_lookback_seconds)
      and q.queued_at <= p_as_of
      and t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  ),
  scoped as (
    select
      cycle_at,target_id,result_sequence,http_status,timed_out,error_message,
      contract_ok,response_at,
      (
        timed_out
        or (
          http_status is null
          and error_message is not null
          and length(btrim(error_message))>0
        )
      ) as transport_failure,
      (
        (
          timed_out
          or (
            http_status is null
            and error_message is not null
            and length(btrim(error_message))>0
          )
        )
        and lower(coalesce(error_message,'')) like '%tcp/ssl handshake%'
      ) as tls_transport_failure
    from ranked
    where rn=1
  ),
  cycles as (
    select
      cycle_at,
      count(*)::integer as result_count,
      count(*) filter (where contract_ok)::integer as pass_count,
      count(*) filter (where transport_failure)::integer as transport_failure_count,
      count(*) filter (where tls_transport_failure)::integer as tls_handshake_timeout_count,
      count(*) filter (
        where not contract_ok and not transport_failure
      )::integer as non_transport_failure_count,
      jsonb_agg(target_id order by target_id)
        filter (where transport_failure) as affected_targets,
      min(response_at) as first_response_at,
      max(response_at) as last_response_at
    from scoped
    group by cycle_at
  ),
  qualified as (
    select
      c.*,
      round(
        c.transport_failure_count::numeric/nullif(c.result_count,0),4
      ) as failure_fraction
    from cycles c
    where c.result_count>=p_min_affected_targets
      and c.transport_failure_count>=p_min_affected_targets
      and c.non_transport_failure_count=0
      and c.transport_failure_count::numeric/nullif(c.result_count,0)
        >=p_min_failure_fraction
  ),
  counts as (
    select
      count(*)::integer as qualifying_cycle_count,
      count(*) filter (
        where tls_handshake_timeout_count=transport_failure_count
          and transport_failure_count>0
      )::integer as tls_dominant_cycle_count
    from qualified
  )
  select qualifying_cycle_count,tls_dominant_cycle_count
  into v_qualifying_cycle_count,v_tls_dominant_cycle_count
  from counts;

  with ranked as (
    select
      date_trunc('minute',q.queued_at) as cycle_at,
      q.target_id,
      r.result_sequence,
      r.http_status,
      r.timed_out,
      r.error_message,
      r.contract_ok,
      r.response_at,
      row_number() over (
        partition by date_trunc('minute',q.queued_at),q.target_id
        order by r.response_at desc,r.result_sequence desc
      ) as rn
    from foundation.defence_health_probe_requests q
    join foundation.defence_health_probe_results r
      on r.probe_request_id=q.probe_request_id
    join foundation.defence_estate_targets t
      on t.target_id=q.target_id
    where q.queued_at > p_as_of-make_interval(secs=>p_lookback_seconds)
      and q.queued_at <= p_as_of
      and t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  ),
  scoped as (
    select
      cycle_at,target_id,result_sequence,http_status,timed_out,error_message,
      contract_ok,response_at,
      (
        timed_out
        or (
          http_status is null
          and error_message is not null
          and length(btrim(error_message))>0
        )
      ) as transport_failure
    from ranked
    where rn=1
  ),
  cycles as (
    select
      cycle_at,
      count(*)::integer as result_count,
      count(*) filter (where contract_ok)::integer as pass_count,
      count(*) filter (where transport_failure)::integer as transport_failure_count,
      count(*) filter (
        where transport_failure
          and lower(coalesce(error_message,'')) like '%tcp/ssl handshake%'
      )::integer as tls_handshake_timeout_count,
      count(*) filter (
        where not contract_ok and not transport_failure
      )::integer as non_transport_failure_count,
      jsonb_agg(target_id order by target_id)
        filter (where transport_failure) as affected_targets,
      min(response_at) as first_response_at,
      max(response_at) as last_response_at
    from scoped
    group by cycle_at
  )
  select
    c.*,
    round(
      c.transport_failure_count::numeric/nullif(c.result_count,0),4
    ) as failure_fraction
  into v_latest
  from cycles c
  where c.result_count>=p_min_affected_targets
    and c.transport_failure_count>=p_min_affected_targets
    and c.non_transport_failure_count=0
    and c.transport_failure_count::numeric/nullif(c.result_count,0)
      >=p_min_failure_fraction
  order by c.cycle_at desc
  limit 1;

  if v_latest.cycle_at is not null then
    with ranked as (
      select
        date_trunc('minute',q.queued_at) as cycle_at,
        q.target_id,
        r.result_sequence,
        r.contract_ok,
        r.response_at,
        row_number() over (
          partition by date_trunc('minute',q.queued_at),q.target_id
          order by r.response_at desc,r.result_sequence desc
        ) as rn
      from foundation.defence_health_probe_requests q
      join foundation.defence_health_probe_results r
        on r.probe_request_id=q.probe_request_id
      join foundation.defence_estate_targets t
        on t.target_id=q.target_id
      where q.queued_at > v_latest.cycle_at
        and q.queued_at <= p_as_of
        and t.provider='railway'
        and t.lifecycle='active'
        and t.required_for_estate
    ),
    cycles as (
      select
        cycle_at,
        count(*)::integer as result_count,
        count(*) filter (where contract_ok)::integer as pass_count,
        count(*) filter (where not contract_ok)::integer as failure_count,
        min(response_at) as first_response_at,
        max(response_at) as last_response_at
      from ranked
      where rn=1
      group by cycle_at
    )
    select *
    into v_recovery
    from cycles
    where result_count>=v_latest.result_count
      and pass_count=result_count
      and failure_count=0
    order by cycle_at asc
    limit 1;
  end if;

  return jsonb_build_object(
    'defenceTransportRecurrenceSentinel',
      'shine-defence/transport-recurrence-sentinel-v1',
    'schemaVersion','1.0.0',
    'state',case
      when v_qualifying_cycle_count=0 then 'stable'
      when v_qualifying_cycle_count<p_recurrence_threshold then 'watch'
      else 'recurrent'
    end,
    'reasonCode',case
      when v_qualifying_cycle_count=0 then 'no-repeated-shared-transport'
      when v_qualifying_cycle_count<p_recurrence_threshold
        then 'shared-transport-below-recurrence-threshold'
      else 'shared-transport-recurrence-detected'
    end,
    'qualifyingCycleCount',v_qualifying_cycle_count,
    'tlsDominantCycleCount',v_tls_dominant_cycle_count,
    'recurrenceThreshold',p_recurrence_threshold,
    'latestEventState',case
      when v_latest.cycle_at is null then 'none'
      when v_recovery.cycle_at is null then 'active'
      else 'recovered'
    end,
    'latestEvent',case
      when v_latest.cycle_at is null then null
      else jsonb_build_object(
        'cycleAt',v_latest.cycle_at,
        'resultCount',v_latest.result_count,
        'passCount',v_latest.pass_count,
        'transportFailureCount',v_latest.transport_failure_count,
        'nonTransportFailureCount',v_latest.non_transport_failure_count,
        'failureFraction',v_latest.failure_fraction,
        'tlsHandshakeTimeoutCount',v_latest.tls_handshake_timeout_count,
        'affectedTargets',coalesce(v_latest.affected_targets,'[]'::jsonb),
        'firstResponseAt',v_latest.first_response_at,
        'lastResponseAt',v_latest.last_response_at
      )
    end,
    'latestRecovery',case
      when v_recovery.cycle_at is null then null
      else jsonb_build_object(
        'cycleAt',v_recovery.cycle_at,
        'resultCount',v_recovery.result_count,
        'passCount',v_recovery.pass_count,
        'failureCount',v_recovery.failure_count,
        'firstResponseAt',v_recovery.first_response_at,
        'lastResponseAt',v_recovery.last_response_at
      )
    end,
    'rawEstateState',v_raw_estate->>'state',
    'rawHealthEvidencePreserved',true,
    'rawEstateStateOverridden',false,
    'targetSpecificFailuresExcludedFromQualification',true,
    'automaticRetryAuthorized',false,
    'automaticRestartAuthorized',false,
    'lookbackSeconds',p_lookback_seconds,
    'minimumAffectedTargets',p_min_affected_targets,
    'minimumFailureFraction',p_min_failure_fraction,
    'evaluatedAt',p_as_of
  );
end;
$transport_recurrence_sentinel$;

revoke all on function foundation.get_defence_transport_recurrence_sentinel_v1(
  timestamptz,integer,integer,numeric,integer
) from public,anon,authenticated;
grant execute on function foundation.get_defence_transport_recurrence_sentinel_v1(
  timestamptz,integer,integer,numeric,integer
) to foundation_runtime,shine_defence_runtime,service_role;
