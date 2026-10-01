-- Shine Defence correlated transport-failure attribution v1.
-- Attribute same-cycle multi-target probe transport failures while preserving
-- every raw health result and all existing fail/degraded semantics unchanged.

create or replace function foundation.get_defence_correlated_transport_attribution_v1(
  p_as_of timestamptz default now(),
  p_lookback_seconds integer default 21600,
  p_min_affected_targets integer default 3,
  p_min_failure_fraction numeric default 0.5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $correlated_transport_attribution$
declare
  v_event record;
  v_recovery record;
  v_raw_estate jsonb;
begin
  if p_as_of is null
     or p_lookback_seconds<600
     or p_lookback_seconds>604800
     or p_min_affected_targets<2
     or p_min_affected_targets>100
     or p_min_failure_fraction<=0
     or p_min_failure_fraction>1 then
    raise exception 'invalid-correlated-transport-attribution-window'
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
    where q.queued_at>p_as_of-make_interval(secs=>p_lookback_seconds)
      and q.queued_at<=p_as_of
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
      count(*) filter (where not contract_ok and not transport_failure)::integer
        as non_transport_failure_count,
      count(*) filter (
        where transport_failure
          and lower(coalesce(error_message,'')) like '%tcp/ssl handshake%'
      )::integer as tls_handshake_timeout_count,
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
      round(c.transport_failure_count::numeric/nullif(c.result_count,0),4)
        as failure_fraction
    from cycles c
    where c.result_count>=p_min_affected_targets
      and c.transport_failure_count>=p_min_affected_targets
      and c.non_transport_failure_count=0
      and c.transport_failure_count::numeric/nullif(c.result_count,0)
        >=p_min_failure_fraction
    order by c.cycle_at desc
    limit 1
  )
  select * into v_event from qualified;

  if v_event.cycle_at is null then
    return jsonb_build_object(
      'defenceCorrelatedTransportAttribution',
        'shine-defence/correlated-transport-attribution-v1',
      'schemaVersion','1.0.0',
      'state','none',
      'reasonCode','no-correlated-transport-event',
      'rawEstateState',v_raw_estate->>'state',
      'rawHealthEvidencePreserved',true,
      'rawEstateStateOverridden',false,
      'lookbackSeconds',p_lookback_seconds,
      'minimumAffectedTargets',p_min_affected_targets,
      'minimumFailureFraction',p_min_failure_fraction,
      'evaluatedAt',p_as_of
    );
  end if;

  with ranked as (
    select
      date_trunc('minute',q.queued_at) as cycle_at,
      q.target_id,
      r.result_sequence,
      r.contract_ok,
      r.timed_out,
      r.http_status,
      r.error_message,
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
    where q.queued_at>v_event.cycle_at
      and q.queued_at<=p_as_of
      and t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  ),
  scoped as (
    select * from ranked where rn=1
  ),
  cycles as (
    select
      cycle_at,
      count(*)::integer as result_count,
      count(*) filter (where contract_ok)::integer as pass_count,
      count(*) filter (where not contract_ok)::integer as failure_count,
      count(*) filter (where timed_out)::integer as timeout_count,
      min(response_at) as first_response_at,
      max(response_at) as last_response_at
    from scoped
    group by cycle_at
  )
  select * into v_recovery
  from cycles
  where result_count>=v_event.result_count
    and pass_count=result_count
    and failure_count=0
  order by cycle_at asc
  limit 1;

  return jsonb_build_object(
    'defenceCorrelatedTransportAttribution',
      'shine-defence/correlated-transport-attribution-v1',
    'schemaVersion','1.0.0',
    'state',case
      when v_recovery.cycle_at is null then 'active'
      else 'recovered'
    end,
    'reasonCode',case
      when v_recovery.cycle_at is null
        then 'correlated-transport-failure-active'
      else 'correlated-transport-failure-recovered'
    end,
    'rawEstateState',v_raw_estate->>'state',
    'rawHealthEvidencePreserved',true,
    'rawEstateStateOverridden',false,
    'event',jsonb_build_object(
      'cycleAt',v_event.cycle_at,
      'resultCount',v_event.result_count,
      'passCount',v_event.pass_count,
      'transportFailureCount',v_event.transport_failure_count,
      'nonTransportFailureCount',v_event.non_transport_failure_count,
      'failureFraction',v_event.failure_fraction,
      'tlsHandshakeTimeoutCount',v_event.tls_handshake_timeout_count,
      'affectedTargets',coalesce(v_event.affected_targets,'[]'::jsonb),
      'firstResponseAt',v_event.first_response_at,
      'lastResponseAt',v_event.last_response_at
    ),
    'recovery',case
      when v_recovery.cycle_at is null then null
      else jsonb_build_object(
        'cycleAt',v_recovery.cycle_at,
        'resultCount',v_recovery.result_count,
        'passCount',v_recovery.pass_count,
        'failureCount',v_recovery.failure_count,
        'timeoutCount',v_recovery.timeout_count,
        'firstResponseAt',v_recovery.first_response_at,
        'lastResponseAt',v_recovery.last_response_at
      )
    end,
    'lookbackSeconds',p_lookback_seconds,
    'minimumAffectedTargets',p_min_affected_targets,
    'minimumFailureFraction',p_min_failure_fraction,
    'evaluatedAt',p_as_of
  );
end;
$correlated_transport_attribution$;

revoke all on function foundation.get_defence_correlated_transport_attribution_v1(
  timestamptz,integer,integer,numeric
) from public,anon,authenticated;
grant execute on function foundation.get_defence_correlated_transport_attribution_v1(
  timestamptz,integer,integer,numeric
) to foundation_runtime,shine_defence_runtime,service_role;
