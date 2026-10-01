-- Shine Defence on-demand sleep posture v1.
-- Read-only attribution for intentionally sleeping Railway services. This does
-- not change release-admission or raw estate state.

create or replace function foundation.get_defence_on_demand_sleep_posture_v1(
  p_target_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $on_demand_sleep_posture$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_health_target foundation.defence_health_probe_targets%rowtype;
  v_eval jsonb;
  v_state text;
  v_reason text;
  v_next_action text;
  v_applicable boolean := false;
  v_source_ahead boolean := false;
  v_source_fresh boolean := false;
  v_source_authority_current boolean := false;
  v_source_identity_ok boolean := false;
  v_transition_blocking boolean := false;
  v_on_demand_unchanged boolean := false;
  v_transition_state text;
  v_serving_deployment text;
  v_serving_commit text;
  v_canonical_deployment text;
  v_canonical_commit text;
begin
  if p_target_id is null
     or length(btrim(p_target_id))=0
     or p_as_of is null then
    raise exception 'invalid-on-demand-sleep-posture-input'
      using errcode='22023';
  end if;

  select * into v_target
  from foundation.defence_estate_targets
  where target_id=p_target_id
    and provider='railway'
    and lifecycle='active'
    and required_for_estate;

  if v_target.target_id is null then
    return jsonb_build_object(
      'defenceOnDemandSleepPosture','shine-defence/on-demand-sleep-posture-v1',
      'schemaVersion','1.0.0',
      'targetId',p_target_id,
      'state','not_applicable',
      'reasonCode','target-not-eligible',
      'nextAction','none',
      'rawEstateStateOverridden',false,
      'evaluatedAt',p_as_of
    );
  end if;

  select hp.* into v_health_target
  from foundation.current_defence_health_probe_target hp
  where hp.target_id=p_target_id
    and hp.enabled;

  v_applicable := coalesce(
    (v_target.metadata->>'sleepAllowed')::boolean
    and (v_target.metadata->>'sleepAware')::boolean
    and v_health_target.probe_mode='on_demand'
    and 'sleeping'=any(v_target.allowed_runtime_states),
    false
  );

  if not v_applicable then
    return jsonb_build_object(
      'defenceOnDemandSleepPosture','shine-defence/on-demand-sleep-posture-v1',
      'schemaVersion','1.0.0',
      'targetId',p_target_id,
      'state','not_applicable',
      'reasonCode','target-not-on-demand-sleep-aware',
      'nextAction','none',
      'rawEstateStateOverridden',false,
      'evaluatedAt',p_as_of
    );
  end if;

  v_eval := foundation.evaluate_defence_release_admission_v1(
    p_target_id,p_as_of
  );

  v_source_ahead := coalesce(
    (v_eval#>>'{evidence,sourceAhead}')::boolean,false
  );
  v_source_fresh := coalesce(
    (v_eval#>>'{evidence,sourceWatchFresh}')::boolean,false
  );
  v_source_authority_current := coalesce(
    (v_eval#>>'{evidence,sourceAuthorityCurrent}')::boolean,false
  );
  v_source_identity_ok := coalesce(
    (v_eval#>>'{evidence,sourceIdentityOk}')::boolean,false
  );
  v_transition_blocking := coalesce(
    (v_eval#>>'{evidence,transitionBlocking}')::boolean,false
  );
  v_on_demand_unchanged := coalesce(
    (v_eval#>>'{evidence,onDemandCanonicalUnchanged}')::boolean,false
  );
  v_transition_state := v_eval#>>'{evidence,latestCandidateTransitionState}';
  v_serving_deployment := v_eval#>>'{serving,deploymentId}';
  v_serving_commit := v_eval#>>'{serving,commitSha}';
  v_canonical_deployment := v_eval#>>'{canonical,deploymentId}';
  v_canonical_commit := v_eval#>>'{canonical,commitSha}';

  if coalesce(v_transition_state,'')<>'sleeping' then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-sleep-state-unconfirmed';
    v_next_action := 'verify_on_demand_sleep_state';
  elsif not v_source_identity_ok then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-source-identity-mismatch';
    v_next_action := 'revalidate_on_demand_release';
  elsif not v_source_authority_current then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-source-authority-stale';
    v_next_action := 'revalidate_on_demand_release';
  elsif not v_source_fresh then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-source-watch-stale';
    v_next_action := 'revalidate_on_demand_release';
  elsif v_transition_blocking then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-transition-blocking';
    v_next_action := 'investigate_on_demand_transition';
  elsif v_source_ahead then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-source-ahead';
    v_next_action := 'wake_and_revalidate_on_demand_target';
  elsif v_canonical_deployment is distinct from v_serving_deployment
     or v_canonical_commit is distinct from v_serving_commit then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-serving-identity-changed';
    v_next_action := 'wake_and_revalidate_on_demand_target';
  elsif not v_on_demand_unchanged then
    v_state := 'revalidation_required';
    v_reason := 'on-demand-prior-proof-not-reusable';
    v_next_action := 'wake_and_revalidate_on_demand_target';
  else
    v_state := 'expected_sleep_stale';
    v_reason := 'on-demand-sleep-expected-stale';
    v_next_action := 'none';
  end if;

  return jsonb_build_object(
    'defenceOnDemandSleepPosture','shine-defence/on-demand-sleep-posture-v1',
    'schemaVersion','1.0.0',
    'targetId',p_target_id,
    'state',v_state,
    'reasonCode',v_reason,
    'nextAction',v_next_action,
    'rawEstateStateOverridden',false,
    'releaseAdmission',jsonb_build_object(
      'decision',v_eval->>'decision',
      'reasonCode',v_eval->>'reasonCode'
    ),
    'serving',v_eval->'serving',
    'canonical',v_eval->'canonical',
    'evidence',jsonb_build_object(
      'probeMode',v_health_target.probe_mode,
      'sleepAllowed',coalesce((v_target.metadata->>'sleepAllowed')::boolean,false),
      'sleepAware',coalesce((v_target.metadata->>'sleepAware')::boolean,false),
      'latestTransitionState',v_transition_state,
      'sourceAhead',v_source_ahead,
      'sourceWatchFresh',v_source_fresh,
      'sourceAuthorityCurrent',v_source_authority_current,
      'sourceIdentityOk',v_source_identity_ok,
      'transitionBlocking',v_transition_blocking,
      'onDemandCanonicalUnchanged',v_on_demand_unchanged,
      'sourceHeadSha',v_eval#>>'{evidence,sourceHeadSha}',
      'recentSampleCount',v_eval#>>'{evidence,recentSampleCount}',
      'recentFailureCount',v_eval#>>'{evidence,recentFailureCount}'
    ),
    'evaluatedAt',p_as_of
  );
end;
$on_demand_sleep_posture$;

revoke all on function foundation.get_defence_on_demand_sleep_posture_v1(
  text,timestamptz
) from public,anon,authenticated;
grant execute on function foundation.get_defence_on_demand_sleep_posture_v1(
  text,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role;
