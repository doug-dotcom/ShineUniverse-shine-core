-- Shine Defence target recovery awareness v1.
-- Reclassify advisory attention only when an isolated target-specific failure
-- has been followed by enough clean scheduled probes. Raw health and incident
-- state remain unchanged and authoritative.

create or replace function foundation.get_defence_target_recovery_evidence_v1(
  p_target_id text,
  p_window_started_at timestamptz,
  p_window_ended_at timestamptz,
  p_as_of timestamptz default now(),
  p_min_consecutive_passes integer default 2
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $target_recovery_evidence$
declare
  v_last_failure_cycle timestamptz;
  v_last_failure_response timestamptz;
  v_later_samples integer := 0;
  v_later_passes integer := 0;
  v_latest_cycle timestamptz;
  v_latest_response timestamptz;
  v_latest_contract_ok boolean;
begin
  if p_target_id is null
     or length(btrim(p_target_id))=0
     or p_window_started_at is null
     or p_window_ended_at is null
     or p_as_of is null
     or p_window_ended_at<p_window_started_at
     or p_min_consecutive_passes<1
     or p_min_consecutive_passes>20 then
    raise exception 'invalid-target-recovery-evidence-input'
      using errcode='22023';
  end if;

  with ranked as (
    select
      date_trunc('minute',q.queued_at) as cycle_at,
      r.contract_ok,
      r.response_at,
      row_number() over (
        partition by date_trunc('minute',q.queued_at)
        order by r.response_at desc,r.result_sequence desc
      ) as rn
    from foundation.defence_health_probe_requests q
    join foundation.defence_health_probe_results r
      on r.probe_request_id=q.probe_request_id
    where q.target_id=p_target_id
      and r.response_at>=p_window_started_at
      and r.response_at<=least(p_window_ended_at,p_as_of)
  ),
  scoped as (
    select cycle_at,contract_ok,response_at
    from ranked
    where rn=1
  )
  select cycle_at,response_at
  into v_last_failure_cycle,v_last_failure_response
  from scoped
  where not contract_ok
  order by response_at desc
  limit 1;

  if v_last_failure_cycle is null then
    return jsonb_build_object(
      'contract','shine-defence/target-recovery-evidence-v1',
      'schemaVersion','1.0.0',
      'targetId',p_target_id,
      'state','not_applicable',
      'reasonCode','no-failure-in-attention-window',
      'minimumConsecutivePasses',p_min_consecutive_passes,
      'laterSampleCount',0,
      'laterPassCount',0,
      'rawHealthEvidencePreserved',true,
      'rawEstateStateOverridden',false,
      'evaluatedAt',p_as_of
    );
  end if;

  with ranked as (
    select
      date_trunc('minute',q.queued_at) as cycle_at,
      r.contract_ok,
      r.response_at,
      row_number() over (
        partition by date_trunc('minute',q.queued_at)
        order by r.response_at desc,r.result_sequence desc
      ) as rn
    from foundation.defence_health_probe_requests q
    join foundation.defence_health_probe_results r
      on r.probe_request_id=q.probe_request_id
    where q.target_id=p_target_id
      and r.response_at>v_last_failure_response
      and r.response_at<=least(p_window_ended_at,p_as_of)
  ),
  scoped as (
    select cycle_at,contract_ok,response_at
    from ranked
    where rn=1
  ),
  summary as (
    select
      count(*)::integer as sample_count,
      count(*) filter (where contract_ok)::integer as pass_count
    from scoped
  ),
  latest as (
    select cycle_at,response_at,contract_ok
    from scoped
    order by response_at desc
    limit 1
  )
  select
    s.sample_count,
    s.pass_count,
    l.cycle_at,
    l.response_at,
    l.contract_ok
  into
    v_later_samples,
    v_later_passes,
    v_latest_cycle,
    v_latest_response,
    v_latest_contract_ok
  from summary s
  left join latest l on true;

  return jsonb_build_object(
    'contract','shine-defence/target-recovery-evidence-v1',
    'schemaVersion','1.0.0',
    'targetId',p_target_id,
    'state',case
      when v_later_samples>=p_min_consecutive_passes
       and v_later_passes=v_later_samples
       and coalesce(v_latest_contract_ok,false)
        then 'recovered'
      when v_later_samples<p_min_consecutive_passes
        then 'unproven'
      else 'not_recovered'
    end,
    'reasonCode',case
      when v_later_samples>=p_min_consecutive_passes
       and v_later_passes=v_later_samples
       and coalesce(v_latest_contract_ok,false)
        then 'consecutive-clean-probes-after-last-failure'
      when v_later_samples<p_min_consecutive_passes
        then 'insufficient-clean-probes-after-last-failure'
      else 'newer-failure-or-nonpass-present'
    end,
    'lastFailureCycleAt',v_last_failure_cycle,
    'lastFailureResponseAt',v_last_failure_response,
    'laterSampleCount',coalesce(v_later_samples,0),
    'laterPassCount',coalesce(v_later_passes,0),
    'latestCycleAt',v_latest_cycle,
    'latestResponseAt',v_latest_response,
    'latestContractOk',v_latest_contract_ok,
    'minimumConsecutivePasses',p_min_consecutive_passes,
    'rawHealthEvidencePreserved',true,
    'rawEstateStateOverridden',false,
    'evaluatedAt',p_as_of
  );
end;
$target_recovery_evidence$;

revoke all on function foundation.get_defence_target_recovery_evidence_v1(
  text,timestamptz,timestamptz,timestamptz,integer
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_target_recovery_evidence_v1(
  text,timestamptz,timestamptz,timestamptz,integer
) to foundation_runtime,shine_defence_runtime,service_role;


create or replace function foundation.apply_defence_target_recovery_awareness_v1(
  p_attention jsonb,
  p_as_of timestamptz default now(),
  p_min_consecutive_passes integer default 2
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $target_recovery_awareness$
declare
  v_base jsonb;
  v_item jsonb;
  v_evidence jsonb;
  v_target_items jsonb := '[]'::jsonb;
  v_queue_items jsonb := '[]'::jsonb;
  v_counts jsonb;
  v_recovered integer := 0;
  v_raw_target_specific integer := 0;
  v_actionable_targets integer := 0;
  v_active_clusters integer := 0;
  v_residual_items integer := 0;
  v_attention_state text;
begin
  if p_attention is null
     or jsonb_typeof(p_attention)<>'object'
     or p_attention->>'defenceOperationalAttention'
          <>'shine-defence/operational-attention-v1'
     or p_as_of is null
     or p_min_consecutive_passes<1
     or p_min_consecutive_passes>20 then
    raise exception 'invalid-target-recovery-awareness-input'
      using errcode='22023';
  end if;

  v_base := p_attention;
  v_raw_target_specific :=
    coalesce((v_base#>>'{counts,targetSpecificTargets}')::integer,0);

  for v_item in
    select value
    from jsonb_array_elements(coalesce(v_base->'targetItems','[]'::jsonb))
  loop
    if v_item->>'causeClass'='target_specific'
       and v_item->>'attentionClass'='target_investigation' then
      v_evidence := foundation.get_defence_target_recovery_evidence_v1(
        v_item->>'targetId',
        (v_item->>'windowStartedAt')::timestamptz,
        (v_item->>'windowEndedAt')::timestamptz,
        p_as_of,
        p_min_consecutive_passes
      );

      v_item := v_item || jsonb_build_object(
        'recoveryEvidence',v_evidence
      );

      if v_evidence->>'state'='recovered' then
        v_recovered := v_recovered+1;
        v_item := v_item || jsonb_build_object(
          'causeClass','target_specific_recovered_residual',
          'attentionClass','target_recovery_residual',
          'nextAction','observe_residual_health_window'
        );
      end if;
    end if;

    v_target_items := v_target_items || jsonb_build_array(v_item);
  end loop;

  select count(*)::integer
  into v_actionable_targets
  from jsonb_array_elements(v_target_items) t(value)
  where t.value->>'attentionClass' in (
    'executor_unavailable',
    'human_authorisation',
    'authorised_execution_pending',
    'execution_in_progress',
    'target_investigation',
    'state_attention'
  );

  select count(*)::integer
  into v_active_clusters
  from jsonb_array_elements(coalesce(v_base->'estateItems','[]'::jsonb)) e(value)
  where e.value->>'clusterState'='active';

  select (
    count(*) filter (
      where t.value->>'attentionClass' in (
        'shared_transport_residual',
        'target_recovery_residual',
        'sleep_expected'
      )
    )
    +
    (
      select count(*)
      from jsonb_array_elements(coalesce(v_base->'estateItems','[]'::jsonb)) e(value)
      where e.value->>'clusterState'='recovered'
    )
  )::integer
  into v_residual_items
  from jsonb_array_elements(v_target_items) t(value);

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
    from jsonb_array_elements(coalesce(v_base->'estateItems','[]'::jsonb)) e(value)

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
        when t.value->>'attentionClass'='target_recovery_residual' then 9
        when t.value->>'attentionClass'='shared_transport_residual' then 10
        when t.value->>'attentionClass'='sleep_expected' then 11
        else 12
      end as priority,
      t.value->>'targetId' as stable_id
    from jsonb_array_elements(v_target_items) t(value)
  ) q;

  v_counts := coalesce(v_base->'counts','{}'::jsonb)
    || jsonb_build_object(
      'targetSpecificRecoveredTargets',v_recovered,
      'targetSpecificActionableTargets',
        greatest(v_raw_target_specific-v_recovered,0)
    );

  v_attention_state := case
    when v_actionable_targets>0 or v_active_clusters>0
      then 'attention_required'
    when v_residual_items>0
      then 'observe'
    else 'clear'
  end;

  return v_base || jsonb_build_object(
    'schemaVersion','1.5.0',
    'attentionState',v_attention_state,
    'counts',v_counts,
    'targetItems',v_target_items,
    'queueItems',v_queue_items,
    'targetRecovery',jsonb_build_object(
      'contract','shine-defence/target-recovery-awareness-v1',
      'minimumConsecutivePasses',p_min_consecutive_passes,
      'reclassifiesAttentionOnly',true,
      'rawHealthEvidencePreserved',true,
      'rawEstateStateOverridden',false,
      'incidentStateOverridden',false,
      'releaseAdmissionOverridden',false,
      'automaticRetryAuthorized',false,
      'automaticRestartAuthorized',false
    )
  );
end;
$target_recovery_awareness$;

revoke all on function foundation.apply_defence_target_recovery_awareness_v1(
  jsonb,timestamptz,integer
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.apply_defence_target_recovery_awareness_v1(
  jsonb,timestamptz,integer
) to foundation_runtime,shine_defence_runtime,service_role;


create or replace function foundation.get_defence_operational_attention_recovery_aware_v1(
  p_as_of timestamptz default now(),
  p_lookback_seconds integer default 2700,
  p_cluster_min_targets integer default 3,
  p_confirmed_failure_fraction numeric default 0.5,
  p_min_consecutive_passes integer default 2
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $target_recovery_wrapper$
declare
  v_base jsonb;
begin
  v_base :=
    foundation.get_defence_operational_attention_executor_aware_v1(
      p_as_of,p_lookback_seconds,p_cluster_min_targets,
      p_confirmed_failure_fraction
    );

  return foundation.apply_defence_target_recovery_awareness_v1(
    v_base,p_as_of,p_min_consecutive_passes
  );
end;
$target_recovery_wrapper$;

revoke all on function foundation.get_defence_operational_attention_recovery_aware_v1(
  timestamptz,integer,integer,numeric,integer
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_operational_attention_recovery_aware_v1(
  timestamptz,integer,integer,numeric,integer
) to foundation_runtime,shine_defence_runtime,service_role;
