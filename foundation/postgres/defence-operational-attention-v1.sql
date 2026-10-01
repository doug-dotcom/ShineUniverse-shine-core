-- Shine Defence operational attention v1.
-- Cause-aware, read-only runtime attention over immutable probe, health and
-- incident evidence. It never changes raw estate/admission/incident truth.

create or replace function foundation.get_defence_operational_attention_v1(
  p_as_of timestamptz default now(),
  p_lookback_seconds integer default 2700,
  p_cluster_min_targets integer default 3,
  p_confirmed_failure_fraction numeric default 0.5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $defence_operational_attention$
declare
  v_estate jsonb;
  v_estate_items jsonb := '[]'::jsonb;
  v_target_items jsonb := '[]'::jsonb;
  v_queue_items jsonb := '[]'::jsonb;
  v_confirmed_cycles integer := 0;
  v_cluster_cycles integer := 0;
  v_active_clusters integer := 0;
  v_recovered_clusters integer := 0;
  v_shared_residual integer := 0;
  v_target_specific integer := 0;
  v_mixed integer := 0;
  v_unresolved integer := 0;
  v_non_health integer := 0;
  v_attention_state text;
begin
  if p_as_of is null
     or p_lookback_seconds<600
     or p_lookback_seconds>86400
     or p_cluster_min_targets<2
     or p_cluster_min_targets>100
     or p_confirmed_failure_fraction<=0
     or p_confirmed_failure_fraction>1 then
    raise exception 'invalid-defence-operational-attention-window'
      using errcode='22023';
  end if;

  v_estate := foundation.get_defence_estate_summary_v1();

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
      coalesce(
        jsonb_agg(target_id order by target_id)
          filter (where transport_failure),
        '[]'::jsonb
      ) as affected_targets,
      min(response_at) as first_response_at,
      max(response_at) as last_response_at
    from scoped
    group by cycle_at
  ),
  classified_cycles as (
    select
      c.*,
      round(c.transport_failure_count::numeric/nullif(c.result_count,0),4)
        as failure_fraction,
      case
        when c.transport_failure_count>=p_cluster_min_targets
         and c.non_transport_failure_count=0
         and c.transport_failure_count::numeric/nullif(c.result_count,0)
              >=p_confirmed_failure_fraction
          then 'confirmed_shared_transport'
        when c.transport_failure_count>=p_cluster_min_targets
         and c.non_transport_failure_count=0
          then 'shared_transport_cluster'
        else null
      end as cause_class
    from cycles c
  ),
  clusters as (
    select c.*
    from classified_cycles c
    where c.cause_class is not null
  ),
  cluster_state as (
    select
      c.*,
      rec.cycle_at as recovery_cycle_at,
      rec.result_count as recovery_result_count,
      rec.pass_count as recovery_pass_count,
      case when rec.cycle_at is null then 'active' else 'recovered' end
        as cluster_state
    from clusters c
    left join lateral (
      select n.*
      from classified_cycles n
      where n.cycle_at>c.cycle_at
        and n.result_count>=c.result_count
        and n.pass_count=n.result_count
      order by n.cycle_at asc
      limit 1
    ) rec on true
  ),
  current_health as (
    select distinct on (h.target_id)
      h.*
    from foundation.defence_health_observations h
    join foundation.defence_estate_targets t
      on t.target_id=h.target_id
    where h.observed_at<=p_as_of
      and h.valid_until>p_as_of
      and h.health_state in ('degraded','unhealthy')
      and t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
    order by h.target_id,h.observed_at desc,h.recorded_at desc,h.observation_id desc
  ),
  cluster_projection as (
    select
      cs.*,
      (
        select count(*)::integer
        from current_health h
        where cs.affected_targets ? h.target_id
          and h.window_started_at<=cs.last_response_at
          and h.window_ended_at>=cs.first_response_at
      ) as residual_target_count
    from cluster_state cs
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'scope','estate',
        'itemId','transport-cycle:'||to_char(cp.cycle_at at time zone 'UTC','YYYYMMDDHH24MI'),
        'causeClass',cp.cause_class,
        'clusterState',cp.cluster_state,
        'cycleAt',cp.cycle_at,
        'resultCount',cp.result_count,
        'passCount',cp.pass_count,
        'transportFailureCount',cp.transport_failure_count,
        'nonTransportFailureCount',cp.non_transport_failure_count,
        'failureFraction',cp.failure_fraction,
        'tlsHandshakeTimeoutCount',cp.tls_handshake_timeout_count,
        'affectedTargets',cp.affected_targets,
        'residualTargetCount',cp.residual_target_count,
        'recovery',case
          when cp.recovery_cycle_at is null then null
          else jsonb_build_object(
            'cycleAt',cp.recovery_cycle_at,
            'resultCount',cp.recovery_result_count,
            'passCount',cp.recovery_pass_count
          )
        end,
        'attentionClass',case
          when cp.cluster_state='active' then 'shared_transport_unresolved'
          when cp.residual_target_count>0 then 'shared_transport_residual'
          else 'shared_transport_recovered'
        end,
        'nextAction',case
          when cp.cluster_state='active' then 'observe_next_scheduled_probe'
          when cp.residual_target_count>0 then 'observe_residual_health_window'
          else 'none'
        end,
        'rawHealthEvidencePreserved',true,
        'rawEstateStateOverridden',false
      )
      order by
        case when cp.cluster_state='active' then 0 else 1 end,
        cp.cycle_at desc
    ),'[]'::jsonb),
    count(*) filter (where cp.cause_class='confirmed_shared_transport')::integer,
    count(*) filter (where cp.cause_class='shared_transport_cluster')::integer,
    count(*) filter (where cp.cluster_state='active')::integer,
    count(*) filter (where cp.cluster_state='recovered')::integer
  into
    v_estate_items,v_confirmed_cycles,v_cluster_cycles,
    v_active_clusters,v_recovered_clusters
  from cluster_projection cp;

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
    where q.queued_at>p_as_of-pg_catalog.make_interval(secs=>p_lookback_seconds)
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
        as non_transport_failure_count
    from scoped
    group by cycle_at
  ),
  classified_cycles as (
    select
      c.*,
      case
        when c.transport_failure_count>=p_cluster_min_targets
         and c.non_transport_failure_count=0
         and c.transport_failure_count::numeric/nullif(c.result_count,0)
              >=p_confirmed_failure_fraction
          then 'confirmed_shared_transport'
        when c.transport_failure_count>=p_cluster_min_targets
         and c.non_transport_failure_count=0
          then 'shared_transport_cluster'
        else null
      end as cause_class
    from cycles c
  ),
  current_health as (
    select distinct on (h.target_id)
      h.*
    from foundation.defence_health_observations h
    join foundation.defence_estate_targets t
      on t.target_id=h.target_id
    where h.observed_at<=p_as_of
      and h.valid_until>p_as_of
      and h.health_state in ('degraded','unhealthy')
      and t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
    order by h.target_id,h.observed_at desc,h.recorded_at desc,h.observation_id desc
  ),
  health_failure_breakdown as (
    select
      h.target_id,
      h.health_state,
      h.failure_count as observation_failure_count,
      h.sample_count,
      h.window_started_at,
      h.window_ended_at,
      h.observed_at,
      count(*) filter (where not s.contract_ok)::integer as failed_results,
      count(*) filter (
        where not s.contract_ok
          and cc.cause_class='confirmed_shared_transport'
      )::integer as confirmed_shared_failures,
      count(*) filter (
        where not s.contract_ok
          and cc.cause_class='shared_transport_cluster'
      )::integer as shared_cluster_failures,
      count(*) filter (
        where not s.contract_ok
          and cc.cause_class is null
      )::integer as target_specific_failures
    from current_health h
    left join scoped s
      on s.target_id=h.target_id
     and s.response_at>=h.window_started_at
     and s.response_at<=h.window_ended_at
    left join classified_cycles cc
      on cc.cycle_at=s.cycle_at
    group by
      h.target_id,h.health_state,h.failure_count,h.sample_count,
      h.window_started_at,h.window_ended_at,h.observed_at
  ),
  health_items as (
    select
      hfb.target_id,
      coalesce(
        (
          select jsonb_agg(distinct a.app_key order by a.app_key)
          from foundation.defence_estate_target_apps a
          where a.target_id=hfb.target_id
        ),
        '[]'::jsonb
      ) as app_keys,
      hfb.health_state,
      hfb.observation_failure_count,
      hfb.sample_count,
      hfb.window_started_at,
      hfb.window_ended_at,
      hfb.observed_at,
      hfb.failed_results,
      hfb.confirmed_shared_failures,
      hfb.shared_cluster_failures,
      hfb.target_specific_failures,
      case
        when hfb.target_specific_failures>0
         and (hfb.confirmed_shared_failures+hfb.shared_cluster_failures)>0
          then 'mixed_or_unresolved'
        when hfb.target_specific_failures>0
          then 'target_specific'
        when hfb.confirmed_shared_failures>0
          then 'confirmed_shared_transport_residual'
        when hfb.shared_cluster_failures>0
          then 'shared_transport_cluster_residual'
        else 'unresolved_health'
      end as cause_class,
      i.state as incident_state,
      i.reason_code as incident_reason,
      i.event_id as incident_event_id
    from health_failure_breakdown hfb
    left join foundation.current_defence_estate_incident_state i
      on i.incident_key=hfb.target_id
  ),
  raw_non_health as (
    select
      p->>'targetId' as target_id,
      p->>'reason' as raw_reason,
      p->>'runtimeState' as runtime_state,
      p->>'healthState' as health_state
    from jsonb_array_elements(coalesce(v_estate->'problemTargets','[]'::jsonb)) p
    where coalesce(p->>'reason','') not in ('health-degraded','health-unhealthy')
  ),
  non_health_items as (
    select
      n.target_id,
      coalesce(
        (
          select jsonb_agg(distinct a.app_key order by a.app_key)
          from foundation.defence_estate_target_apps a
          where a.target_id=n.target_id
        ),
        '[]'::jsonb
      ) as app_keys,
      n.raw_reason,
      n.runtime_state,
      n.health_state,
      i.state as incident_state,
      i.reason_code as incident_reason,
      i.event_id as incident_event_id
    from raw_non_health n
    left join foundation.current_defence_estate_incident_state i
      on i.incident_key=n.target_id
    where not exists (
      select 1 from health_items h where h.target_id=n.target_id
    )
  ),
  all_target_items as (
    select jsonb_build_object(
      'scope','target',
      'targetId',h.target_id,
      'appKeys',h.app_keys,
      'causeClass',h.cause_class,
      'healthState',h.health_state,
      'failureCount',h.observation_failure_count,
      'sampleCount',h.sample_count,
      'windowStartedAt',h.window_started_at,
      'windowEndedAt',h.window_ended_at,
      'healthObservedAt',h.observed_at,
      'failedResults',h.failed_results,
      'confirmedSharedFailures',h.confirmed_shared_failures,
      'sharedClusterFailures',h.shared_cluster_failures,
      'targetSpecificFailures',h.target_specific_failures,
      'incidentState',h.incident_state,
      'incidentReason',h.incident_reason,
      'incidentEventId',h.incident_event_id,
      'attentionClass',case
        when h.cause_class in ('target_specific','mixed_or_unresolved','unresolved_health')
          then 'target_investigation'
        else 'shared_transport_residual'
      end,
      'nextAction',case
        when h.cause_class='target_specific' then 'investigate_target_health'
        when h.cause_class='mixed_or_unresolved' then 'investigate_mixed_health'
        when h.cause_class='unresolved_health' then 'investigate_unresolved_health'
        else 'observe_residual_health_window'
      end,
      'rawHealthEvidencePreserved',true,
      'rawEstateStateOverridden',false
    ) as item,
    case
      when h.cause_class in ('target_specific','mixed_or_unresolved','unresolved_health') then 0
      else 2
    end as sort_group,
    h.target_id as sort_id,
    h.cause_class
    from health_items h

    union all

    select jsonb_build_object(
      'scope','target',
      'targetId',n.target_id,
      'appKeys',n.app_keys,
      'causeClass','non_health_attention',
      'rawReason',n.raw_reason,
      'runtimeState',n.runtime_state,
      'healthState',n.health_state,
      'incidentState',n.incident_state,
      'incidentReason',n.incident_reason,
      'incidentEventId',n.incident_event_id,
      'attentionClass','state_attention',
      'nextAction','review_non_health_state',
      'rawHealthEvidencePreserved',true,
      'rawEstateStateOverridden',false
    ) as item,
    1 as sort_group,
    n.target_id as sort_id,
    'non_health_attention'::text as cause_class
    from non_health_items n
  )
  select
    coalesce(jsonb_agg(item order by sort_group,sort_id),'[]'::jsonb),
    count(*) filter (
      where cause_class in (
        'confirmed_shared_transport_residual','shared_transport_cluster_residual'
      )
    )::integer,
    count(*) filter (where cause_class='target_specific')::integer,
    count(*) filter (where cause_class='mixed_or_unresolved')::integer,
    count(*) filter (where cause_class='unresolved_health')::integer,
    count(*) filter (where cause_class='non_health_attention')::integer
  into
    v_target_items,v_shared_residual,v_target_specific,v_mixed,
    v_unresolved,v_non_health
  from all_target_items;

  select coalesce(jsonb_agg(item order by priority,stable_id),'[]'::jsonb)
  into v_queue_items
  from (
    select
      e.value as item,
      case
        when e.value->>'clusterState'='active' then 0
        when e.value->>'attentionClass'='shared_transport_residual' then 3
        else 5
      end as priority,
      e.value->>'itemId' as stable_id
    from jsonb_array_elements(v_estate_items) e(value)

    union all

    select
      t.value as item,
      case
        when t.value->>'attentionClass'='target_investigation' then 1
        when t.value->>'attentionClass'='state_attention' then 2
        else 4
      end as priority,
      t.value->>'targetId' as stable_id
    from jsonb_array_elements(v_target_items) t(value)
  ) q;

  v_attention_state := case
    when v_active_clusters>0
      or v_target_specific>0
      or v_mixed>0
      or v_unresolved>0
      or v_non_health>0
      then 'attention_required'
    when v_shared_residual>0 or v_recovered_clusters>0
      then 'observe'
    else 'clear'
  end;

  return jsonb_build_object(
    'defenceOperationalAttention','shine-defence/operational-attention-v1',
    'schemaVersion','1.0.0',
    'attentionState',v_attention_state,
    'rawEstateState',v_estate->>'state',
    'rawEstateStateOverridden',false,
    'rawHealthEvidencePreserved',true,
    'counts',jsonb_build_object(
      'confirmedSharedTransportCycles',v_confirmed_cycles,
      'sharedTransportClusterCycles',v_cluster_cycles,
      'activeSharedClusters',v_active_clusters,
      'recoveredSharedClusters',v_recovered_clusters,
      'sharedTransportResidualTargets',v_shared_residual,
      'targetSpecificTargets',v_target_specific,
      'mixedOrUnresolvedTargets',v_mixed,
      'unresolvedHealthTargets',v_unresolved,
      'nonHealthAttentionTargets',v_non_health
    ),
    'estateItems',v_estate_items,
    'targetItems',v_target_items,
    'queueItems',v_queue_items,
    'lookbackSeconds',p_lookback_seconds,
    'sharedClusterMinimumTargets',p_cluster_min_targets,
    'confirmedSharedFailureFraction',p_confirmed_failure_fraction,
    'evaluatedAt',p_as_of
  );
end;
$defence_operational_attention$;

revoke all on function foundation.get_defence_operational_attention_v1(
  timestamptz,integer,integer,numeric
) from public,anon,authenticated;
grant execute on function foundation.get_defence_operational_attention_v1(
  timestamptz,integer,integer,numeric
) to foundation_runtime,shine_defence_runtime,service_role;
