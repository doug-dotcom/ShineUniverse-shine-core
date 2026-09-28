-- Shine Defence Supabase runtime receipt Sentinel v1.
-- Separates Supabase self-verification from Railway runtime provenance while
-- exposing a combined whole-estate state.

alter table foundation.defence_estate_incident_events
  drop constraint if exists defence_estate_incident_events_reason_code_check;

alter table foundation.defence_estate_incident_events
  add constraint defence_estate_incident_events_reason_code_check
  check (reason_code in (
    'healthy',
    'missing-observation',
    'stale-observation',
    'runtime-failure',
    'unexpected-runtime-state',
    'health-coverage-missing',
    'health-degraded',
    'health-unhealthy',
    'health-observation-missing',
    'health-observation-stale',
    'runtime-provenance-coverage-missing',
    'runtime-provenance-missing',
    'runtime-provenance-stale',
    'supabase-runtime-receipt-coverage-missing',
    'supabase-runtime-receipt-missing',
    'supabase-runtime-receipt-stale',
    'supabase-runtime-receipt-database-unhealthy'
  ));


create or replace function foundation.get_defence_supabase_runtime_receipt_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_required integer := 0;
  v_coverage integer := 0;
  v_fresh integer := 0;
  v_missing integer := 0;
  v_stale integer := 0;
  v_unhealthy integer := 0;
  v_state text;
  v_problems jsonb := '[]'::jsonb;
begin
  with targets as (
    select
      t.target_id,
      t.provider_project_ref,
      t.metadata,
      case
        when t.metadata ? 'runtimeReceiptEffectiveAt'
          then (t.metadata->>'runtimeReceiptEffectiveAt')::timestamptz
        else t.updated_at
      end as effective_at,
      r.observation_id,
      r.database_reachable,
      r.observed_at,
      r.valid_until,
      r.function_id,
      r.function_version,
      r.region
    from foundation.defence_estate_targets t
    left join foundation.current_defence_supabase_runtime_receipts r using(target_id)
    where t.provider='supabase'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select
    count(*),
    count(*) filter (
      where metadata->>'runtimeReceiptRequired'='true'
        and metadata->>'receiptFunctionId' is not null
        and metadata->>'approvedReceiptVersion' is not null
        and metadata->>'projectRegion' is not null
    ),
    count(*) filter (
      where observation_id is not null and valid_until>now()
    ),
    count(*) filter (
      where metadata->>'runtimeReceiptRequired'='true'
        and observation_id is null
        and now()>effective_at+interval '20 minutes'
    ),
    count(*) filter (
      where metadata->>'runtimeReceiptRequired'='true'
        and observation_id is not null
        and valid_until<=now()
        and now()>effective_at+interval '20 minutes'
    ),
    count(*) filter (
      where observation_id is not null
        and valid_until>now()
        and not database_reachable
    )
  into
    v_required,v_coverage,v_fresh,v_missing,v_stale,v_unhealthy
  from targets;

  with targets as (
    select
      t.target_id,
      t.provider_project_ref,
      t.metadata,
      case
        when t.metadata ? 'runtimeReceiptEffectiveAt'
          then (t.metadata->>'runtimeReceiptEffectiveAt')::timestamptz
        else t.updated_at
      end as effective_at,
      r.observation_id,
      r.database_reachable,
      r.observed_at,
      r.valid_until,
      r.function_id,
      r.function_version,
      r.region
    from foundation.defence_estate_targets t
    left join foundation.current_defence_supabase_runtime_receipts r using(target_id)
    where t.provider='supabase'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'targetId',target_id,
      'projectRef',provider_project_ref,
      'observedAt',observed_at,
      'validUntil',valid_until,
      'databaseReachable',database_reachable,
      'functionId',function_id,
      'functionVersion',function_version,
      'region',region,
      'reasonCode',case
        when metadata->>'runtimeReceiptRequired'<>'true'
          or metadata->>'receiptFunctionId' is null
          or metadata->>'approvedReceiptVersion' is null
          or metadata->>'projectRegion' is null
          then 'supabase-runtime-receipt-coverage-missing'
        when observation_id is null
          and now()>effective_at+interval '20 minutes'
          then 'supabase-runtime-receipt-missing'
        when observation_id is not null
          and valid_until<=now()
          and now()>effective_at+interval '20 minutes'
          then 'supabase-runtime-receipt-stale'
        when observation_id is not null
          and valid_until>now()
          and not database_reachable
          then 'supabase-runtime-receipt-database-unhealthy'
        else 'healthy'
      end
    ) order by target_id
  ),'[]'::jsonb)
  into v_problems
  from targets
  where
    metadata->>'runtimeReceiptRequired'<>'true'
    or metadata->>'receiptFunctionId' is null
    or metadata->>'approvedReceiptVersion' is null
    or metadata->>'projectRegion' is null
    or (
      observation_id is null
      and now()>effective_at+interval '20 minutes'
    )
    or (
      observation_id is not null
      and valid_until<=now()
      and now()>effective_at+interval '20 minutes'
    )
    or (
      observation_id is not null
      and valid_until>now()
      and not database_reachable
    );

  v_state := case
    when v_unhealthy>0 then 'fail'
    when v_coverage<v_required or v_missing>0 or v_stale>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceSupabaseRuntimeReceiptSummary','shine-defence/supabase-runtime-receipt-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'requiredTargets',v_required,
    'coverageTargets',v_coverage,
    'freshTargets',v_fresh,
    'missingTargets',v_missing,
    'staleTargets',v_stale,
    'databaseUnhealthyTargets',v_unhealthy,
    'problemTargets',v_problems,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_supabase_runtime_receipt_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_supabase_runtime_receipt_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;


create or replace function foundation.run_defence_supabase_runtime_receipt_sentinel_v1(
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_receipt foundation.defence_supabase_runtime_receipt_observations%rowtype;
  v_prior foundation.defence_estate_incident_events%rowtype;
  v_effective_at timestamptz;
  v_state text;
  v_reason text;
  v_event_type text;
  v_incident_key text;
  v_created integer := 0;
  v_active integer := 0;
begin
  for v_target in
    select *
    from foundation.defence_estate_targets
    where provider='supabase'
      and lifecycle='active'
      and required_for_estate
    order by target_id
  loop
    v_receipt := null;

    select r.*
      into v_receipt
    from foundation.defence_supabase_runtime_receipt_observations r
    where r.target_id=v_target.target_id
      and r.observed_at<=p_observed_at
    order by r.observed_at desc,r.recorded_at desc,r.observation_id desc
    limit 1;

    v_effective_at := case
      when v_target.metadata ? 'runtimeReceiptEffectiveAt'
        then (v_target.metadata->>'runtimeReceiptEffectiveAt')::timestamptz
      else v_target.updated_at
    end;

    if v_target.metadata->>'runtimeReceiptRequired'<>'true'
       or v_target.metadata->>'receiptFunctionId' is null
       or v_target.metadata->>'approvedReceiptVersion' is null
       or v_target.metadata->>'projectRegion' is null then
      v_state := 'warning';
      v_reason := 'supabase-runtime-receipt-coverage-missing';
    elsif v_receipt.observation_id is null
      and p_observed_at>v_effective_at+interval '20 minutes' then
      v_state := 'warning';
      v_reason := 'supabase-runtime-receipt-missing';
    elsif v_receipt.observation_id is not null
      and v_receipt.valid_until<=p_observed_at
      and p_observed_at>v_effective_at+interval '20 minutes' then
      v_state := 'warning';
      v_reason := 'supabase-runtime-receipt-stale';
    elsif v_receipt.observation_id is not null
      and v_receipt.valid_until>p_observed_at
      and not v_receipt.database_reachable then
      v_state := 'fail';
      v_reason := 'supabase-runtime-receipt-database-unhealthy';
    else
      v_state := 'pass';
      v_reason := 'healthy';
    end if;

    v_incident_key := v_target.target_id||':supabase-runtime-receipt';
    v_prior := null;

    select i.*
      into v_prior
    from foundation.defence_estate_incident_events i
    where i.incident_key=v_incident_key
    order by i.occurred_at desc,i.recorded_at desc,i.event_id desc
    limit 1;

    v_event_type := null;

    if v_state in ('warning','fail') then
      if v_prior.event_id is null or v_prior.event_type='recovered' then
        v_event_type := 'opened';
      elsif v_prior.state is distinct from v_state
         or v_prior.reason_code is distinct from v_reason then
        v_event_type := 'changed';
      end if;
    elsif v_prior.event_id is not null
      and v_prior.event_type<>'recovered' then
      v_event_type := 'recovered';
    end if;

    if v_event_type is not null then
      insert into foundation.defence_estate_incident_events(
        incident_key,target_id,event_type,state,reason_code,
        observation_id,health_observation_id,occurred_at,evidence_ref
      ) values (
        v_incident_key,
        v_target.target_id,
        v_event_type,
        v_state,
        v_reason,
        null,
        null,
        p_observed_at,
        'sentinel:shine-defence:supabase-runtime-receipt:v1'
      );
      v_created := v_created+1;
    end if;
  end loop;

  select count(*)
    into v_active
  from foundation.current_defence_estate_incidents
  where incident_key like 'supabase:%:supabase-runtime-receipt';

  return jsonb_build_object(
    'defenceSupabaseRuntimeReceiptSentinel','shine-defence/supabase-runtime-receipt-sentinel-v1',
    'schemaVersion','1.0.0',
    'observedAt',p_observed_at,
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active,
    'summary',foundation.get_defence_supabase_runtime_receipt_summary_v1()
  );
end;
$$;

revoke all on function foundation.run_defence_supabase_runtime_receipt_sentinel_v1(timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_defence_supabase_runtime_receipt_sentinel_v1(timestamptz)
  to shine_defence_runtime,service_role;


create or replace function foundation.get_defence_full_estate_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_estate jsonb;
  v_supabase jsonb;
  v_state text;
begin
  v_estate := foundation.get_defence_estate_summary_v1();
  v_supabase := foundation.get_defence_supabase_runtime_receipt_summary_v1();

  v_state := case
    when v_estate->>'state'='fail' or v_supabase->>'state'='fail' then 'fail'
    when v_estate->>'state'='warning' or v_supabase->>'state'='warning' then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceFullEstateSummary','shine-defence/full-estate-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'estate',v_estate,
    'supabaseRuntimeReceipts',v_supabase,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_full_estate_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_full_estate_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
