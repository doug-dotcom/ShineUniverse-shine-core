-- Shine Defence rollback ladder and recovery depth v1.
-- Read-only projection over qualified canonical history and explicit repo-local
-- source attestations. Defence recommends recovery points but never rolls back.

create or replace function foundation.get_defence_rollback_ladder_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, foundation
as $$
with target_base as (
  select
    t.target_id,
    t.metadata->>'sourceRepository' as repository,
    t.metadata->>'sourceBranch' as branch,
    a.serving_deployment_id,
    a.serving_commit_sha,
    a.canonical_deployment_id,
    a.canonical_commit_sha,
    a.admission_state,
    a.observed_at as current_admission_at
  from foundation.defence_estate_targets t
  left join foundation.current_defence_release_admission a using(target_id)
  where t.provider='railway'
    and t.lifecycle='active'
    and t.required_for_estate
),
historical_releases as (
  select
    a.target_id,
    a.canonical_deployment_id as deployment_id,
    lower(a.canonical_commit_sha) as commit_sha,
    max(a.observed_at) as qualified_at
  from foundation.defence_release_admission_events a
  join target_base b using(target_id)
  where a.canonical_deployment_id is not null
    and a.canonical_commit_sha is not null
    and a.admission_state in ('canonical','admitted','rollback-observed')
    and a.canonical_deployment_id is distinct from b.serving_deployment_id
    and (
      b.canonical_deployment_id is null
      or a.canonical_deployment_id is distinct from b.canonical_deployment_id
    )
  group by a.target_id,a.canonical_deployment_id,a.canonical_commit_sha
),
candidate_union as (
  select
    b.target_id,
    b.canonical_deployment_id as deployment_id,
    lower(b.canonical_commit_sha) as commit_sha,
    b.current_admission_at as qualified_at,
    0 as sort_class,
    'preserved-current-canonical'::text as origin
  from target_base b
  where b.canonical_deployment_id is not null
    and b.canonical_commit_sha is not null
    and b.canonical_deployment_id is distinct from b.serving_deployment_id

  union all

  select
    h.target_id,
    h.deployment_id,
    h.commit_sha,
    h.qualified_at,
    1 as sort_class,
    'prior-canonical'::text as origin
  from historical_releases h
),
ranked as (
  select
    c.*,
    row_number() over(
      partition by c.target_id
      order by c.sort_class,c.qualified_at desc,c.deployment_id
    )::integer as recovery_rank
  from candidate_union c
),
proofed as (
  select
    r.*,
    p.observation_id as source_proof_observation_id,
    p.proof_available as source_available,
    p.observed_at as source_proof_observed_at,
    p.valid_until as source_proof_valid_until,
    p.proof_mode as source_proof_mode,
    coalesce(
      p.observation_id is not null
      and p.proof_available
      and p.valid_until>now(),
      false
    ) as source_proof_fresh
  from ranked r
  left join lateral (
    select *
    from (
      select
        a.observation_id,
        a.source_available as proof_available,
        a.observed_at,
        a.valid_until,
        'rollback-commit-verified'::text as proof_mode,
        0::integer as proof_priority,
        a.recorded_at
      from foundation.defence_rollback_source_attestations a
      where a.target_id=r.target_id
        and lower(a.rollback_commit_sha)=r.commit_sha

      union all

      select
        a.observation_id,
        a.canonical_source_available as proof_available,
        a.observed_at,
        a.valid_until,
        'canonical-commit-verified'::text as proof_mode,
        1::integer as proof_priority,
        a.recorded_at
      from foundation.defence_rollback_source_attestations a
      where a.target_id=r.target_id
        and lower(a.canonical_commit_sha)=r.commit_sha
        and a.canonical_source_available is not null
    ) evidence
    order by evidence.proof_priority,evidence.observed_at desc,evidence.recorded_at desc,evidence.observation_id desc
    limit 1
  ) p on true
),
target_rollup as (
  select
    b.target_id,
    b.repository,
    b.branch,
    b.serving_deployment_id,
    b.serving_commit_sha,
    b.canonical_deployment_id,
    b.canonical_commit_sha,
    b.admission_state,
    count(p.deployment_id)::integer as qualified_history_depth,
    count(*) filter (
      where p.recovery_rank<=3 and p.source_proof_fresh
    )::integer as verified_source_depth,
    min(p.recovery_rank) filter (
      where p.recovery_rank<=3 and p.source_proof_fresh
    )::integer as recommended_rank,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'rank',p.recovery_rank,
          'deploymentId',p.deployment_id,
          'commitSha',p.commit_sha,
          'origin',p.origin,
          'qualifiedAt',p.qualified_at,
          'ageSeconds',greatest(
            0,
            extract(epoch from (now()-p.qualified_at))::bigint
          ),
          'sourceProofState',case
            when p.source_proof_observation_id is null then 'missing'
            when p.source_proof_valid_until<=now() then 'stale'
            when p.source_available then 'ready'
            else 'unavailable'
          end,
          'sourceProofMode',p.source_proof_mode,
          'sourceProofObservedAt',p.source_proof_observed_at,
          'sourceProofValidUntil',p.source_proof_valid_until
        )
        order by p.recovery_rank
      ) filter (where p.recovery_rank<=3),
      '[]'::jsonb
    ) as candidates
  from target_base b
  left join proofed p using(target_id)
  group by
    b.target_id,b.repository,b.branch,
    b.serving_deployment_id,b.serving_commit_sha,
    b.canonical_deployment_id,b.canonical_commit_sha,b.admission_state
),
classified as (
  select
    t.*,
    case
      when t.qualified_history_depth=0 then 'history-building'
      when t.recommended_rank=1 then 'primary-ready'
      when t.recommended_rank is not null then 'degraded-fallback-ready'
      else 'source-proof-gap'
    end as ladder_state,
    (
      select jsonb_build_object(
        'rank',p.recovery_rank,
        'deploymentId',p.deployment_id,
        'commitSha',p.commit_sha,
        'origin',p.origin,
        'qualifiedAt',p.qualified_at,
        'sourceProofMode',p.source_proof_mode,
        'sourceProofObservedAt',p.source_proof_observed_at,
        'sourceProofValidUntil',p.source_proof_valid_until
      )
      from proofed p
      where p.target_id=t.target_id
        and p.recovery_rank<=3
        and p.source_proof_fresh
      order by p.recovery_rank
      limit 1
    ) as recommended_recovery
  from target_rollup t
),
summary as (
  select
    count(*)::integer as required_targets,
    count(*) filter (where qualified_history_depth>0)::integer as rollback_capable_targets,
    count(*) filter (where ladder_state='history-building')::integer as history_building_targets,
    count(*) filter (where ladder_state='primary-ready')::integer as primary_ready_targets,
    count(*) filter (where ladder_state='degraded-fallback-ready')::integer as degraded_targets,
    count(*) filter (where ladder_state='source-proof-gap')::integer as proof_gap_targets,
    count(*) filter (where verified_source_depth>=2)::integer as verified_depth2_targets,
    count(*) filter (where verified_source_depth>=3)::integer as verified_depth3_targets,
    max(qualified_history_depth)::integer as maximum_qualified_history_depth
  from classified
)
select jsonb_build_object(
  'defenceRollbackLadder','shine-defence/rollback-ladder-v1',
  'schemaVersion','1.0.0',
  'state',case
    when s.proof_gap_targets>0 or s.degraded_targets>0 then 'warning'
    else 'pass'
  end,
  'configuredDepth',3,
  'requiredTargets',s.required_targets,
  'rollbackCapableTargets',s.rollback_capable_targets,
  'historyBuildingTargets',s.history_building_targets,
  'primaryReadyTargets',s.primary_ready_targets,
  'degradedFallbackReadyTargets',s.degraded_targets,
  'sourceProofGapTargets',s.proof_gap_targets,
  'verifiedDepth2Targets',s.verified_depth2_targets,
  'verifiedDepth3Targets',s.verified_depth3_targets,
  'maximumQualifiedHistoryDepth',coalesce(s.maximum_qualified_history_depth,0),
  'providerNativeRollbackVerification','not-claimed-without-provider-retention-evidence',
  'targets',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'targetId',c.target_id,
        'repository',c.repository,
        'branch',c.branch,
        'state',c.ladder_state,
        'servingDeploymentId',c.serving_deployment_id,
        'servingCommitSha',c.serving_commit_sha,
        'canonicalDeploymentId',c.canonical_deployment_id,
        'canonicalCommitSha',c.canonical_commit_sha,
        'admissionState',c.admission_state,
        'qualifiedHistoryDepth',c.qualified_history_depth,
        'verifiedSourceDepth',c.verified_source_depth,
        'recommendedRecovery',c.recommended_recovery,
        'candidates',c.candidates
      )
      order by c.target_id
    )
    from classified c
  ),'[]'::jsonb),
  'evaluatedAt',now()
)
from summary s;
$$;

revoke all on function foundation.get_defence_rollback_ladder_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_rollback_ladder_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
