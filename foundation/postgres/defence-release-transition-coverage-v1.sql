-- Shine Defence release-transition coverage truth v1.
-- Native Railway webhooks are enhanced provider-push evidence. Repo-local
-- GitHub OIDC source-head attestations are the mandatory estate-wide fallback.

create or replace function foundation.get_defence_release_transition_coverage_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_required integer := 0;
  v_fallback_fresh integer := 0;
  v_fallback_stale integer := 0;
  v_fallback_missing integer := 0;
  v_native_ever integer := 0;
  v_native_24h integer := 0;
  v_enhanced integer := 0;
  v_state text;
  v_targets jsonb := '[]'::jsonb;
begin
  with coverage as (
    select
      t.target_id,
      h.observation_id as head_observation_id,
      h.valid_until as head_valid_until,
      wh.last_webhook_at,
      wh.webhook_event_count,
      case
        when h.observation_id is not null and h.valid_until>now() then true
        else false
      end as fallback_fresh
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_source_heads h using(target_id)
    left join (
      select
        target_id,
        max(occurred_at) as last_webhook_at,
        count(*)::integer as webhook_event_count
      from foundation.defence_railway_transition_events
      where evidence_ref like 'railway-webhook:%'
      group by target_id
    ) wh using(target_id)
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select
    count(*),
    count(*) filter (where fallback_fresh),
    count(*) filter (
      where head_observation_id is not null
        and head_valid_until<=now()
    ),
    count(*) filter (where head_observation_id is null),
    count(*) filter (where last_webhook_at is not null),
    count(*) filter (where last_webhook_at>now()-interval '24 hours'),
    count(*) filter (where fallback_fresh and last_webhook_at is not null)
  into
    v_required,
    v_fallback_fresh,
    v_fallback_stale,
    v_fallback_missing,
    v_native_ever,
    v_native_24h,
    v_enhanced
  from coverage;

  with coverage as (
    select
      t.target_id,
      h.observation_id as head_observation_id,
      h.observed_at as head_observed_at,
      h.valid_until as head_valid_until,
      wh.last_webhook_at,
      coalesce(wh.webhook_event_count,0) as webhook_event_count,
      case
        when h.observation_id is not null and h.valid_until>now() then true
        else false
      end as fallback_fresh
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_source_heads h using(target_id)
    left join (
      select
        target_id,
        max(occurred_at) as last_webhook_at,
        count(*)::integer as webhook_event_count
      from foundation.defence_railway_transition_events
      where evidence_ref like 'railway-webhook:%'
      group by target_id
    ) wh using(target_id)
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'targetId',target_id,
      'coverageMode',case
        when fallback_fresh and last_webhook_at is not null then 'provider-push+repo-oidc-fallback'
        when fallback_fresh then 'repo-oidc-fallback'
        when last_webhook_at is not null then 'provider-push-only'
        else 'uncovered'
      end,
      'fallbackFresh',fallback_fresh,
      'fallbackObservedAt',head_observed_at,
      'fallbackValidUntil',head_valid_until,
      'providerPushObserved',last_webhook_at is not null,
      'providerPushLastAt',last_webhook_at,
      'providerPushEventCount',webhook_event_count
    ) order by target_id
  ),'[]'::jsonb)
  into v_targets
  from coverage;

  v_state := case
    when v_fallback_fresh=v_required and v_required>0 then 'pass'
    else 'warning'
  end;

  return jsonb_build_object(
    'defenceReleaseTransitionCoverage','shine-defence/release-transition-coverage-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'requiredTargets',v_required,
    'repoOidcFallbackFreshTargets',v_fallback_fresh,
    'repoOidcFallbackStaleTargets',v_fallback_stale,
    'repoOidcFallbackMissingTargets',v_fallback_missing,
    'providerPushObservedTargets',v_native_ever,
    'providerPushObservedLast24hTargets',v_native_24h,
    'enhancedProviderPushAndFallbackTargets',v_enhanced,
    'targets',v_targets,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_release_transition_coverage_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_release_transition_coverage_v1()
  to foundation_runtime,shine_defence_runtime,service_role;


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
  v_transitions jsonb;
  v_source_heads jsonb;
  v_transition_coverage jsonb;
  v_state text;
begin
  v_estate := foundation.get_defence_estate_summary_v1();
  v_supabase := foundation.get_defence_supabase_runtime_receipt_summary_v1();
  v_transitions := foundation.get_defence_railway_transition_summary_v1();
  v_source_heads := foundation.get_defence_release_source_head_summary_v1();
  v_transition_coverage := foundation.get_defence_release_transition_coverage_v1();

  v_state := case
    when v_estate->>'state'='fail'
      or v_supabase->>'state'='fail'
      or v_transitions->>'state'='fail'
      then 'fail'
    when v_estate->>'state'='warning'
      or v_supabase->>'state'='warning'
      or v_transitions->>'state'='warning'
      or v_source_heads->>'state'='warning'
      or v_transition_coverage->>'state'='warning'
      then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceFullEstateSummary','shine-defence/full-estate-summary-v1',
    'schemaVersion','1.3.0',
    'state',v_state,
    'estate',v_estate,
    'supabaseRuntimeReceipts',v_supabase,
    'railwayReleaseTransitions',v_transitions,
    'releaseSourceHeads',v_source_heads,
    'releaseTransitionCoverage',v_transition_coverage,
    'evaluatedAt',now()
  );
end;
$$;
