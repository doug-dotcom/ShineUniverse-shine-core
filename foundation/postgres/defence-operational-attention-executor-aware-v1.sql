-- Shine Defence executor-aware operational attention v1.
-- Surface viable revalidation executor choice before admission consumption.

create or replace function foundation.apply_defence_on_demand_executor_selection_v1(
  p_attention jsonb,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $executor_aware$
declare
  v_base jsonb;
  v_item jsonb;
  v_selection jsonb;
  v_target_items jsonb := '[]'::jsonb;
  v_queue_items jsonb := '[]'::jsonb;
  v_counts jsonb;
  v_direct integer := 0;
  v_native integer := 0;
  v_blocked integer := 0;
  v_attention_state text;
begin
  if p_attention is null
     or jsonb_typeof(p_attention)<>'object'
     or p_attention->>'defenceOperationalAttention'
          <>'shine-defence/operational-attention-v1'
     or p_as_of is null then
    raise exception 'invalid-executor-aware-attention-input'
      using errcode='22023';
  end if;

  v_base := p_attention;

  for v_item in
    select value
    from jsonb_array_elements(
      coalesce(v_base->'targetItems','[]'::jsonb)
    )
  loop
    if v_item->>'causeClass'='on_demand_revalidation_required' then
      v_selection :=
        foundation.get_defence_on_demand_executor_selection_v1(
          v_item->>'targetId',p_as_of
        );

      v_item := v_item || jsonb_build_object(
        'executorSelection',v_selection
      );

      if v_selection->>'state'='blocked' then
        v_blocked := v_blocked+1;
        v_item := v_item || jsonb_build_object(
          'attentionClass','executor_unavailable',
          'nextAction','repair_on_demand_executor_readiness'
        );
      elsif v_selection->>'selectedMode'='direct_railway' then
        v_direct := v_direct+1;
      elsif v_selection->>'selectedMode'='native_git' then
        v_native := v_native+1;
      end if;
    end if;

    v_target_items := v_target_items || jsonb_build_array(v_item);
  end loop;

  select coalesce(jsonb_agg(item order by priority,stable_id),'[]'::jsonb)
  into v_queue_items
  from (
    select
      e.value as item,
      case
        when e.value->>'clusterState'='active' then 0
        when e.value->>'attentionClass'='shared_transport_residual' then 8
        else 10
      end as priority,
      e.value->>'itemId' as stable_id
    from jsonb_array_elements(
      coalesce(v_base->'estateItems','[]'::jsonb)
    ) e(value)

    union all

    select
      t.value as item,
      case
        when t.value->>'attentionClass'='executor_unavailable' then 0
        when t.value->>'attentionClass'='human_authorisation' then 1
        when t.value->>'attentionClass'='authorised_execution_pending' then 2
        when t.value->>'attentionClass'='execution_in_progress' then 3
        when t.value->>'attentionClass'='target_investigation' then 4
        when t.value->>'attentionClass'='state_attention' then 5
        when t.value->>'attentionClass'='shared_transport_residual' then 9
        when t.value->>'attentionClass'='sleep_expected' then 11
        else 12
      end as priority,
      t.value->>'targetId' as stable_id
    from jsonb_array_elements(v_target_items) t(value)
  ) q;

  v_counts := coalesce(v_base->'counts','{}'::jsonb)
    || jsonb_build_object(
      'onDemandDirectRailwaySelectedTargets',v_direct,
      'onDemandNativeGitSelectedTargets',v_native,
      'onDemandExecutorBlockedTargets',v_blocked
    );

  v_attention_state := case
    when v_blocked>0 then 'attention_required'
    else v_base->>'attentionState'
  end;

  return v_base || jsonb_build_object(
    'schemaVersion','1.3.0',
    'attentionState',v_attention_state,
    'counts',v_counts,
    'targetItems',v_target_items,
    'queueItems',v_queue_items,
    'executorSelection',jsonb_build_object(
      'contract','shine-defence/on-demand-executor-selection-v1',
      'directRailwayRequiresFreshCredentialReceipt',true,
      'nativeGitRequiresProvenProfile',true,
      'selectionPerformsExternalMutation',false,
      'admissionConsumesOnlyDirectRailwayInV1',true,
      'rawEstateStateOverridden',false,
      'releaseAdmissionOverridden',false
    )
  );
end;
$executor_aware$;

revoke all on function foundation.apply_defence_on_demand_executor_selection_v1(
  jsonb,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.apply_defence_on_demand_executor_selection_v1(
  jsonb,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role;


create or replace function foundation.get_defence_operational_attention_executor_aware_v1(
  p_as_of timestamptz default now(),
  p_lookback_seconds integer default 2700,
  p_cluster_min_targets integer default 3,
  p_confirmed_failure_fraction numeric default 0.5
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $executor_aware_wrapper$
declare
  v_base jsonb;
begin
  v_base :=
    foundation.get_defence_operational_attention_revalidation_aware_v1(
      p_as_of,p_lookback_seconds,p_cluster_min_targets,
      p_confirmed_failure_fraction
    );

  return foundation.apply_defence_on_demand_executor_selection_v1(
    v_base,p_as_of
  );
end;
$executor_aware_wrapper$;

revoke all on function foundation.get_defence_operational_attention_executor_aware_v1(
  timestamptz,integer,integer,numeric
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_operational_attention_executor_aware_v1(
  timestamptz,integer,integer,numeric
) to foundation_runtime,shine_defence_runtime,service_role;
