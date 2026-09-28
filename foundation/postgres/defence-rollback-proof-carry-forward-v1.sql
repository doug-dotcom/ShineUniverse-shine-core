-- Hosted upgrade: carry fresh prior-canonical source proof into rollback readiness.
-- This does not claim Railway-native rollback image retention.

create or replace function foundation.get_defence_rollback_readiness_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_required integer := 0;
  v_history_building integer := 0;
  v_anchored integer := 0;
  v_source_ready integer := 0;
  v_source_unavailable integer := 0;
  v_source_stale integer := 0;
  v_source_missing integer := 0;
  v_carried_forward integer := 0;
  v_state text;
  v_attention jsonb := '[]'::jsonb;
  v_targets jsonb := '[]'::jsonb;
begin
  with x as (
    select
      t.target_id,
      t.metadata->>'sourceRepository' as repository,
      a.canonical_deployment_id,
      a.canonical_commit_sha,
      a.rollback_deployment_id,
      a.rollback_commit_sha,
      proof.observation_id,
      proof.source_available,
      proof.observed_at,
      proof.valid_until,
      proof.proof_mode
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_admission a using(target_id)
    left join lateral (
      select
        r.observation_id,
        r.source_available,
        r.observed_at,
        r.valid_until,
        case
          when r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
            then 'exact-current-pair'
          when r.canonical_commit_sha=a.rollback_commit_sha
            then 'prior-canonical-carry-forward'
          else null
        end as proof_mode
      from foundation.defence_rollback_source_attestations r
      where r.target_id=t.target_id
        and a.rollback_commit_sha is not null
        and (
          (
            r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
          )
          or r.canonical_commit_sha=a.rollback_commit_sha
        )
      order by
        case
          when r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
            then 0
          else 1
        end,
        r.observed_at desc,
        r.recorded_at desc,
        r.observation_id desc
      limit 1
    ) proof on true
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select
    count(*),
    count(*) filter (where rollback_deployment_id is null or rollback_commit_sha is null),
    count(*) filter (where rollback_deployment_id is not null and rollback_commit_sha is not null),
    count(*) filter (
      where rollback_commit_sha is not null
        and observation_id is not null
        and source_available
        and valid_until>now()
    ),
    count(*) filter (
      where rollback_commit_sha is not null
        and observation_id is not null
        and not source_available
        and valid_until>now()
    ),
    count(*) filter (
      where rollback_commit_sha is not null
        and observation_id is not null
        and valid_until<=now()
    ),
    count(*) filter (
      where rollback_commit_sha is not null
        and observation_id is null
    ),
    count(*) filter (
      where rollback_commit_sha is not null
        and observation_id is not null
        and source_available
        and valid_until>now()
        and proof_mode='prior-canonical-carry-forward'
    )
  into
    v_required,v_history_building,v_anchored,v_source_ready,
    v_source_unavailable,v_source_stale,v_source_missing,v_carried_forward
  from x;

  with x as (
    select
      t.target_id,
      t.metadata->>'sourceRepository' as repository,
      a.canonical_deployment_id,
      a.canonical_commit_sha,
      a.rollback_deployment_id,
      a.rollback_commit_sha,
      proof.observation_id,
      proof.source_available,
      proof.observed_at,
      proof.valid_until,
      proof.proof_mode
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_admission a using(target_id)
    left join lateral (
      select
        r.observation_id,
        r.source_available,
        r.observed_at,
        r.valid_until,
        case
          when r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
            then 'exact-current-pair'
          when r.canonical_commit_sha=a.rollback_commit_sha
            then 'prior-canonical-carry-forward'
          else null
        end as proof_mode
      from foundation.defence_rollback_source_attestations r
      where r.target_id=t.target_id
        and a.rollback_commit_sha is not null
        and (
          (
            r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
          )
          or r.canonical_commit_sha=a.rollback_commit_sha
        )
      order by
        case
          when r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
            then 0
          else 1
        end,
        r.observed_at desc,
        r.recorded_at desc,
        r.observation_id desc
      limit 1
    ) proof on true
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'targetId',target_id,
        'repository',repository,
        'canonicalDeploymentId',canonical_deployment_id,
        'canonicalCommitSha',canonical_commit_sha,
        'rollbackDeploymentId',rollback_deployment_id,
        'rollbackCommitSha',rollback_commit_sha,
        'state',case
          when rollback_commit_sha is null then 'history-building'
          when observation_id is null then 'source-proof-missing'
          when valid_until<=now() then 'source-proof-stale'
          when source_available then 'source-ready'
          else 'source-unavailable'
        end,
        'sourceProofMode',proof_mode,
        'sourceAvailable',source_available,
        'observedAt',observed_at,
        'validUntil',valid_until,
        'providerNativeRollbackVerified',false
      ) order by target_id
    ),'[]'::jsonb),
    coalesce(jsonb_agg(
      jsonb_build_object(
        'targetId',target_id,
        'rollbackCommitSha',rollback_commit_sha,
        'reasonCode',case
          when observation_id is null then 'rollback-source-proof-missing'
          when valid_until<=now() then 'rollback-source-proof-stale'
          when not source_available then 'rollback-source-unavailable'
          else null
        end
      ) order by target_id
    ) filter (
      where rollback_commit_sha is not null
        and (
          observation_id is null
          or valid_until<=now()
          or not source_available
        )
    ),'[]'::jsonb)
  into v_targets,v_attention
  from x;

  v_state := case
    when v_source_unavailable>0 then 'warning'
    when v_source_stale>0 or v_source_missing>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceRollbackReadiness','shine-defence/rollback-readiness-summary-v1',
    'schemaVersion','1.1.0',
    'state',v_state,
    'requiredTargets',v_required,
    'historyBuildingTargets',v_history_building,
    'rollbackAnchoredTargets',v_anchored,
    'sourceReadyTargets',v_source_ready,
    'sourceUnavailableTargets',v_source_unavailable,
    'sourceProofStaleTargets',v_source_stale,
    'sourceProofMissingTargets',v_source_missing,
    'carriedForwardPriorCanonicalProofTargets',v_carried_forward,
    'providerNativeRollbackVerifiedTargets',0,
    'providerNativeRollbackVerification','not-claimed-without-provider-retention-evidence',
    'attention',v_attention,
    'targets',v_targets,
    'evaluatedAt',now()
  );
end;
$$;


revoke all on function foundation.get_defence_rollback_readiness_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_rollback_readiness_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
