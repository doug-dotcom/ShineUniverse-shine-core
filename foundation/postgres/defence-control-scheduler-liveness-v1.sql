-- Shine Defence control scheduler liveness v1.
-- Observation-only visibility over GitHub scheduled control-plane activity.
-- It never refreshes proof, extends TTLs or overrides fail-closed truth.

create or replace function foundation.classify_defence_scheduler_age_v1(
  p_last_scheduled_at timestamptz,
  p_as_of timestamptz,
  p_warning_age_seconds integer,
  p_critical_age_seconds integer
)
returns text
language plpgsql
immutable
as $classify_scheduler_age$
declare
  v_age numeric;
begin
  if p_as_of is null
     or p_warning_age_seconds<300
     or p_critical_age_seconds<=p_warning_age_seconds
     or p_critical_age_seconds>86400 then
    raise exception 'invalid-defence-scheduler-age-policy'
      using errcode='22023';
  end if;

  if p_last_scheduled_at is null then
    return 'missing';
  end if;

  v_age := extract(epoch from (p_as_of-p_last_scheduled_at));

  if v_age<0 then
    return 'invalid_future';
  elsif v_age<=p_warning_age_seconds then
    return 'current';
  elsif v_age<=p_critical_age_seconds then
    return 'delayed';
  else
    return 'silent';
  end if;
end;
$classify_scheduler_age$;


create or replace function foundation.get_defence_control_scheduler_liveness_v1(
  p_as_of timestamptz default now(),
  p_warning_age_seconds integer default 1800,
  p_critical_age_seconds integer default 7200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,foundation
as $scheduler_liveness$
declare
  v_targets jsonb := '[]'::jsonb;
  v_required integer := 0;
  v_current integer := 0;
  v_delayed integer := 0;
  v_silent integer := 0;
  v_missing integer := 0;
  v_future integer := 0;
  v_authority_last_schedule timestamptz;
  v_authority_last_any timestamptz;
  v_authority_class text;
  v_state text;
begin
  if p_as_of is null
     or p_warning_age_seconds<300
     or p_critical_age_seconds<=p_warning_age_seconds
     or p_critical_age_seconds>86400 then
    raise exception 'invalid-defence-scheduler-liveness-policy'
      using errcode='22023';
  end if;

  with scoped as (
    select
      t.target_id,
      t.metadata->>'sourceRepository' as repository,
      latest_schedule.bound_at as latest_scheduled_at,
      latest_any.bound_at as latest_any_at,
      latest_any.event_name as latest_any_event,
      foundation.classify_defence_scheduler_age_v1(
        latest_schedule.bound_at,
        p_as_of,
        p_warning_age_seconds,
        p_critical_age_seconds
      ) as scheduler_state
    from foundation.defence_estate_targets t
    left join lateral (
      select b.bound_at
      from foundation.github_oidc_operation_bindings b
      where lower(b.repository)=lower(t.metadata->>'sourceRepository')
        and b.audience='shine-defence-rollback-readiness'
        and b.operation='rollback-claim'
        and b.event_name='schedule'
      order by b.bound_at desc
      limit 1
    ) latest_schedule on true
    left join lateral (
      select b.bound_at,b.event_name
      from foundation.github_oidc_operation_bindings b
      where lower(b.repository)=lower(t.metadata->>'sourceRepository')
        and b.audience='shine-defence-rollback-readiness'
        and b.operation='rollback-claim'
      order by b.bound_at desc
      limit 1
    ) latest_any on true
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select
    count(*)::integer,
    count(*) filter (where scheduler_state='current')::integer,
    count(*) filter (where scheduler_state='delayed')::integer,
    count(*) filter (where scheduler_state='silent')::integer,
    count(*) filter (where scheduler_state='missing')::integer,
    count(*) filter (where scheduler_state='invalid_future')::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'targetId',target_id,
          'repository',repository,
          'state',scheduler_state,
          'latestScheduledAt',latest_scheduled_at,
          'latestAnyAt',latest_any_at,
          'latestAnyEvent',latest_any_event,
          'scheduledAgeSeconds',case
            when latest_scheduled_at is null then null
            else greatest(
              0,
              floor(extract(epoch from (p_as_of-latest_scheduled_at)))
            )::bigint
          end
        )
        order by
          case scheduler_state
            when 'silent' then 0
            when 'missing' then 1
            when 'invalid_future' then 2
            when 'delayed' then 3
            else 4
          end,
          target_id
      ),
      '[]'::jsonb
    )
  into
    v_required,v_current,v_delayed,v_silent,v_missing,v_future,v_targets
  from scoped;

  select
    max(observed_at) filter (where github_event='schedule'),
    max(observed_at)
  into v_authority_last_schedule,v_authority_last_any
  from foundation.defence_attestation_authority_sync_receipts;

  v_authority_class := foundation.classify_defence_scheduler_age_v1(
    v_authority_last_schedule,
    p_as_of,
    p_warning_age_seconds,
    p_critical_age_seconds
  );

  v_state := case
    when v_silent>0
      or v_missing>0
      or v_future>0
      or v_authority_class in ('silent','missing','invalid_future')
      then 'warning'
    when v_delayed>0
      or v_authority_class='delayed'
      then 'watch'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceControlSchedulerLiveness',
      'shine-defence/control-scheduler-liveness-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'warningAgeSeconds',p_warning_age_seconds,
    'criticalAgeSeconds',p_critical_age_seconds,
    'targetSchedules',jsonb_build_object(
      'requiredTargets',v_required,
      'currentTargets',v_current,
      'delayedTargets',v_delayed,
      'silentTargets',v_silent,
      'missingTargets',v_missing,
      'invalidFutureTargets',v_future,
      'targets',v_targets
    ),
    'authoritySchedule',jsonb_build_object(
      'state',v_authority_class,
      'latestScheduledAt',v_authority_last_schedule,
      'latestAnyAt',v_authority_last_any,
      'scheduledAgeSeconds',case
        when v_authority_last_schedule is null then null
        else greatest(
          0,
          floor(extract(epoch from (p_as_of-v_authority_last_schedule)))
        )::bigint
      end
    ),
    'schedulerIsEvidenceSource',false,
    'refreshesProof',false,
    'extendsProofTtl',false,
    'mintsAuthorityState',false,
    'rawEstateStateOverridden',false,
    'releaseAdmissionOverridden',false,
    'rollbackReadinessOverridden',false,
    'evaluatedAt',p_as_of
  );
end;
$scheduler_liveness$;

revoke all on function foundation.classify_defence_scheduler_age_v1(
  timestamptz,timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway;

revoke all on function foundation.get_defence_control_scheduler_liveness_v1(
  timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway;

grant execute on function foundation.get_defence_control_scheduler_liveness_v1(
  timestamptz,integer,integer
) to foundation_runtime,shine_defence_runtime,service_role;
