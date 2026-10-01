-- Shine Defence sleep-aware operational attention overlay v1.
-- Reclassifies generic stale on-demand/sleep-aware runtime attention without
-- changing raw estate state or the base transport-cause projection.

create or replace function foundation.get_defence_operational_attention_sleep_aware_v1(
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
as $sleep_aware_operational_attention$
declare
  v_base jsonb;
  v_item jsonb;
  v_posture jsonb;
  v_target_items jsonb := '[]'::jsonb;
  v_queue_items jsonb := '[]'::jsonb;
  v_counts jsonb;
  v_active_clusters integer := 0;
  v_recovered_clusters integer := 0;
  v_shared_residual integer := 0;
  v_target_specific integer := 0;
  v_mixed integer := 0;
  v_unresolved integer := 0;
  v_non_health integer := 0;
  v_expected_sleep integer := 0;
  v_sleep_revalidation integer := 0;
  v_attention_state text;
begin
  v_base := foundation.get_defence_operational_attention_v1(
    p_as_of,p_lookback_seconds,p_cluster_min_targets,p_confirmed_failure_fraction
  );

  for v_item in
    select value from jsonb_array_elements(coalesce(v_base->'targetItems','[]'::jsonb))
  loop
    if v_item->>'causeClass'='non_health_attention'
       and v_item->>'rawReason' in ('stale-observation','health-observation-stale') then
      v_posture := foundation.get_defence_on_demand_sleep_posture_v1(
        v_item->>'targetId',p_as_of
      );

      if v_posture->>'state'='expected_sleep_stale' then
        v_item := v_item || jsonb_build_object(
          'causeClass','expected_on_demand_sleep',
          'attentionClass','sleep_expected',
          'nextAction','none',
          'onDemandSleepPosture',v_posture
        );
      elsif v_posture->>'state'='revalidation_required' then
        v_item := v_item || jsonb_build_object(
          'causeClass','on_demand_revalidation_required',
          'attentionClass','target_investigation',
          'nextAction',coalesce(v_posture->>'nextAction','revalidate_on_demand_release'),
          'onDemandSleepPosture',v_posture
        );
      end if;
    end if;

    v_target_items := v_target_items || jsonb_build_array(v_item);
  end loop;

  select
    count(*) filter (
      where value->>'causeClass' in (
        'confirmed_shared_transport_residual','shared_transport_cluster_residual'
      )
    )::integer,
    count(*) filter (where value->>'causeClass'='target_specific')::integer,
    count(*) filter (where value->>'causeClass'='mixed_or_unresolved')::integer,
    count(*) filter (where value->>'causeClass'='unresolved_health')::integer,
    count(*) filter (where value->>'causeClass'='non_health_attention')::integer,
    count(*) filter (where value->>'causeClass'='expected_on_demand_sleep')::integer,
    count(*) filter (
      where value->>'causeClass'='on_demand_revalidation_required'
    )::integer
  into
    v_shared_residual,v_target_specific,v_mixed,v_unresolved,v_non_health,
    v_expected_sleep,v_sleep_revalidation
  from jsonb_array_elements(v_target_items);

  v_active_clusters := coalesce(
    (v_base#>>'{counts,activeSharedClusters}')::integer,0
  );
  v_recovered_clusters := coalesce(
    (v_base#>>'{counts,recoveredSharedClusters}')::integer,0
  );

  select coalesce(jsonb_agg(item order by priority,stable_id),'[]'::jsonb)
  into v_queue_items
  from (
    select
      e.value as item,
      case
        when e.value->>'clusterState'='active' then 0
        when e.value->>'attentionClass'='shared_transport_residual' then 4
        else 6
      end as priority,
      e.value->>'itemId' as stable_id
    from jsonb_array_elements(coalesce(v_base->'estateItems','[]'::jsonb)) e(value)

    union all

    select
      t.value as item,
      case
        when t.value->>'causeClass'='on_demand_revalidation_required' then 1
        when t.value->>'attentionClass'='target_investigation' then 1
        when t.value->>'attentionClass'='state_attention' then 2
        when t.value->>'attentionClass'='shared_transport_residual' then 5
        when t.value->>'attentionClass'='sleep_expected' then 7
        else 8
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
      or v_sleep_revalidation>0
      then 'attention_required'
    when v_shared_residual>0
      or v_recovered_clusters>0
      or v_expected_sleep>0
      then 'observe'
    else 'clear'
  end;

  v_counts := coalesce(v_base->'counts','{}'::jsonb) || jsonb_build_object(
    'sharedTransportResidualTargets',v_shared_residual,
    'targetSpecificTargets',v_target_specific,
    'mixedOrUnresolvedTargets',v_mixed,
    'unresolvedHealthTargets',v_unresolved,
    'nonHealthAttentionTargets',v_non_health,
    'expectedOnDemandSleepTargets',v_expected_sleep,
    'onDemandRevalidationTargets',v_sleep_revalidation
  );

  return v_base || jsonb_build_object(
    'schemaVersion','1.1.0',
    'attentionState',v_attention_state,
    'counts',v_counts,
    'targetItems',v_target_items,
    'queueItems',v_queue_items,
    'sleepAwareOverlay',jsonb_build_object(
      'contract','shine-defence/on-demand-sleep-operational-overlay-v1',
      'rawEstateStateOverridden',false,
      'releaseAdmissionOverridden',false,
      'automaticWakeAuthorized',false
    )
  );
end;
$sleep_aware_operational_attention$;

revoke all on function foundation.get_defence_operational_attention_sleep_aware_v1(
  timestamptz,integer,integer,numeric
) from public,anon,authenticated;
grant execute on function foundation.get_defence_operational_attention_sleep_aware_v1(
  timestamptz,integer,integer,numeric
) to foundation_runtime,shine_defence_runtime,service_role;
