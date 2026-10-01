-- Shine Defence revalidation-aware operational attention v1.
-- Adds explicit request/approval/execution-control state to the existing
-- sleep-aware operational attention projection. No external action is executed.

create or replace function foundation.apply_defence_on_demand_revalidation_control_v1(
  p_attention jsonb,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $apply_control$
declare
  v_item jsonb;
  v_status jsonb;
  v_target_items jsonb := '[]'::jsonb;
  v_queue_items jsonb := '[]'::jsonb;
  v_counts jsonb;
  v_pending integer := 0;
  v_approved integer := 0;
  v_execution_ready integer := 0;
  v_in_progress integer := 0;
  v_failed integer := 0;
  v_completed integer := 0;
  v_attention_state text;
begin
  if p_attention is null
     or jsonb_typeof(p_attention)<>'object'
     or p_attention->>'defenceOperationalAttention'
          <>'shine-defence/operational-attention-v1'
     or p_as_of is null then
    raise exception 'invalid-revalidation-aware-attention-input'
      using errcode='22023';
  end if;

  for v_item in
    select value
    from jsonb_array_elements(
      coalesce(p_attention->'targetItems','[]'::jsonb)
    )
  loop
    if v_item->>'causeClass'='on_demand_revalidation_required' then
      v_status :=
        foundation.get_defence_on_demand_revalidation_status_v1(
          v_item->>'targetId',p_as_of
        );

      v_item := v_item || jsonb_build_object(
        'revalidationControl',v_status
      );

      case v_status->>'state'
        when 'none' then
          v_item := v_item || jsonb_build_object(
            'attentionClass','human_authorisation',
            'nextAction','request_on_demand_revalidation'
          );
        when 'pending_approval' then
          v_pending := v_pending+1;
          v_item := v_item || jsonb_build_object(
            'attentionClass','human_authorisation',
            'nextAction','approve_on_demand_revalidation_request'
          );
        when 'approved' then
          v_approved := v_approved+1;
          v_item := v_item || jsonb_build_object(
            'attentionClass','authorised_execution_pending',
            'nextAction','admit_on_demand_revalidation_execution'
          );
        when 'admitted' then
          v_execution_ready := v_execution_ready+1;
          v_item := v_item || jsonb_build_object(
            'attentionClass','authorised_execution_pending',
            'nextAction','redeploy_current_source'
          );
        when 'in_progress' then
          v_in_progress := v_in_progress+1;
          v_item := v_item || jsonb_build_object(
            'attentionClass','execution_in_progress',
            'nextAction','continue_on_demand_revalidation_execution'
          );
        when 'failed' then
          v_failed := v_failed+1;
          v_item := v_item || jsonb_build_object(
            'attentionClass','target_investigation',
            'nextAction','review_on_demand_revalidation_failure'
          );
        when 'completed' then
          v_completed := v_completed+1;
          v_item := v_item || jsonb_build_object(
            'attentionClass','revalidation_completed',
            'nextAction','none'
          );
        else
          v_item := v_item || jsonb_build_object(
            'attentionClass','human_authorisation',
            'nextAction','request_on_demand_revalidation'
          );
      end case;
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
        when e.value->>'attentionClass'='shared_transport_residual' then 7
        else 9
      end as priority,
      e.value->>'itemId' as stable_id
    from jsonb_array_elements(
      coalesce(p_attention->'estateItems','[]'::jsonb)
    ) e(value)

    union all

    select
      t.value as item,
      case
        when t.value->>'attentionClass'='human_authorisation' then 1
        when t.value->>'attentionClass'='authorised_execution_pending' then 2
        when t.value->>'attentionClass'='execution_in_progress' then 3
        when t.value->>'attentionClass'='target_investigation' then 4
        when t.value->>'attentionClass'='state_attention' then 5
        when t.value->>'attentionClass'='shared_transport_residual' then 8
        when t.value->>'attentionClass'='sleep_expected' then 10
        else 11
      end as priority,
      t.value->>'targetId' as stable_id
    from jsonb_array_elements(v_target_items) t(value)
  ) q;

  v_counts := coalesce(p_attention->'counts','{}'::jsonb)
    || jsonb_build_object(
      'onDemandRevalidationPendingApproval',v_pending,
      'onDemandRevalidationApproved',v_approved,
      'onDemandRevalidationExecutionReady',v_execution_ready,
      'onDemandRevalidationInProgress',v_in_progress,
      'onDemandRevalidationFailed',v_failed,
      'onDemandRevalidationCompleted',v_completed
    );

  v_attention_state := case
    when v_pending>0
      or v_approved>0
      or v_execution_ready>0
      or v_in_progress>0
      or v_failed>0
      then 'attention_required'
    else p_attention->>'attentionState'
  end;

  return p_attention || jsonb_build_object(
    'schemaVersion','1.2.0',
    'attentionState',v_attention_state,
    'counts',v_counts,
    'targetItems',v_target_items,
    'queueItems',v_queue_items,
    'revalidationControl',jsonb_build_object(
      'contract','shine-defence/on-demand-revalidation-control-v1',
      'approvalRequired',true,
      'approvalSingleUse',true,
      'executionAdmissionSingleUse',true,
      'externalMutationAutomatic',false,
      'rawEstateStateOverridden',false,
      'releaseAdmissionOverridden',false
    )
  );
end;
$apply_control$;

revoke all on function foundation.apply_defence_on_demand_revalidation_control_v1(
  jsonb,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.apply_defence_on_demand_revalidation_control_v1(
  jsonb,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role;


create or replace function foundation.get_defence_operational_attention_revalidation_aware_v1(
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
as $revalidation_aware$
declare
  v_base jsonb;
begin
  v_base :=
    foundation.get_defence_operational_attention_sleep_aware_v1(
      p_as_of,p_lookback_seconds,p_cluster_min_targets,
      p_confirmed_failure_fraction
    );

  return foundation.apply_defence_on_demand_revalidation_control_v1(
    v_base,p_as_of
  );
end;
$revalidation_aware$;

revoke all on function foundation.get_defence_operational_attention_revalidation_aware_v1(
  timestamptz,integer,integer,numeric
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_operational_attention_revalidation_aware_v1(
  timestamptz,integer,integer,numeric
) to foundation_runtime,shine_defence_runtime,service_role;
