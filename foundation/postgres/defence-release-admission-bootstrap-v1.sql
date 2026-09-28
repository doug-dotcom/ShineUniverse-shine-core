-- Hosted upgrade: bootstrap a canonical rollback anchor from the most
-- recent prior serving release that cleared the same stability bar.

create or replace function foundation.evaluate_defence_release_admission_v1(
  p_target_id text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_serving foundation.defence_runtime_provenance_observations%rowtype;
  v_health_target foundation.defence_health_probe_targets%rowtype;
  v_health foundation.defence_health_observations%rowtype;
  v_source_head foundation.defence_release_source_head_observations%rowtype;
  v_transition foundation.defence_railway_transition_events%rowtype;
  v_last foundation.defence_release_admission_events%rowtype;
  v_previous foundation.defence_release_admission_events%rowtype;
  v_first_serving_at timestamptz;
  v_required_samples integer := 3;
  v_soak_seconds integer := 600;
  v_recent_samples integer := 0;
  v_recent_failures integer := 0;
  v_recent_first timestamptz;
  v_recent_last timestamptz;
  v_decision text;
  v_reason text;
  v_rollback_deployment text;
  v_rollback_commit text;
  v_bootstrap_deployment text;
  v_bootstrap_commit text;
  v_bootstrap_first timestamptz;
  v_bootstrap_last timestamptz;
  v_bootstrap_samples integer := 0;
  v_bootstrap_failures integer := 0;
  v_source_fresh boolean := false;
  v_serving_fresh boolean := false;
  v_health_fresh boolean := false;
  v_source_identity_ok boolean := false;
  v_transition_blocking boolean := false;
  v_on_demand_canonical_unchanged boolean := false;
begin
  select * into v_target
  from foundation.defence_estate_targets
  where target_id=p_target_id
    and provider='railway'
    and lifecycle='active'
    and required_for_estate;

  if v_target.target_id is null then
    return jsonb_build_object(
      'releaseAdmission','shine-defence/release-admission-decision-v1',
      'schemaVersion','1.0.0',
      'targetId',p_target_id,
      'decision','hold',
      'reasonCode','release-target-invalid'
    );
  end if;

  select p.* into v_serving
  from foundation.defence_runtime_provenance_observations p
  where p.target_id=p_target_id
    and p.observed_at<=p_as_of
  order by p.observed_at desc,p.recorded_at desc,p.observation_id desc
  limit 1;

  select hp.* into v_health_target
  from foundation.current_defence_health_probe_target hp
  where hp.target_id=p_target_id
    and hp.enabled;

  select h.* into v_health
  from foundation.defence_health_observations h
  where h.target_id=p_target_id
    and h.observed_at<=p_as_of
  order by h.observed_at desc,h.recorded_at desc,h.observation_id desc
  limit 1;

  select h.* into v_source_head
  from foundation.defence_release_source_head_observations h
  where h.target_id=p_target_id
    and h.observed_at<=p_as_of
  order by h.observed_at desc,h.recorded_at desc,h.observation_id desc
  limit 1;

  select a.* into v_last
  from foundation.defence_release_admission_events a
  where a.target_id=p_target_id
    and a.observed_at<=p_as_of
  order by a.observed_at desc,a.recorded_at desc,a.event_id desc
  limit 1;

  if v_last.canonical_deployment_id is not null then
    select a.* into v_previous
    from foundation.defence_release_admission_events a
    where a.target_id=p_target_id
      and a.observed_at<=p_as_of
      and a.canonical_deployment_id is not null
      and a.canonical_deployment_id<>v_last.canonical_deployment_id
    order by a.observed_at desc,a.recorded_at desc,a.event_id desc
    limit 1;
  end if;

  if v_serving.observation_id is not null then
    select min(p.observed_at)
      into v_first_serving_at
    from foundation.defence_runtime_provenance_observations p
    where p.target_id=p_target_id
      and p.deployment_id=v_serving.deployment_id
      and p.commit_sha=v_serving.commit_sha
      and p.observed_at<=p_as_of;
  end if;

  if v_health_target.target_id is not null then
    v_required_samples := case
      when v_health_target.probe_mode='on_demand'
        then greatest(coalesce(v_health_target.min_samples,1),1)
      else greatest(coalesce(v_health_target.min_samples,3),3)
    end;
    v_soak_seconds := case
      when v_health_target.probe_mode='on_demand' then 0
      else 600
    end;
  end if;

  if v_last.canonical_deployment_id is null
     and v_first_serving_at is not null then
    with prior_releases as (
      select
        p.deployment_id,
        p.commit_sha,
        min(p.observed_at) as first_seen,
        max(p.observed_at) as last_seen
      from foundation.defence_runtime_provenance_observations p
      where p.target_id=p_target_id
        and p.observed_at<v_first_serving_at
        and p.deployment_id<>v_serving.deployment_id
        and lower(p.repository)=lower(v_target.metadata->>'sourceRepository')
        and p.branch=v_target.metadata->>'sourceBranch'
      group by p.deployment_id,p.commit_sha
    ),
    qualified as (
      select
        r.deployment_id,
        r.commit_sha,
        r.first_seen,
        r.last_seen,
        s.sample_count,
        s.failure_count
      from prior_releases r
      cross join lateral (
        select
          count(*)::integer as sample_count,
          count(*) filter (where not contract_ok)::integer as failure_count
        from (
          select h.contract_ok
          from foundation.defence_health_probe_results h
          where h.target_id=p_target_id
            and h.response_at>=r.first_seen
            and h.response_at<=r.last_seen+interval '1 second'
          order by h.response_at desc,h.result_sequence desc
          limit v_required_samples
        ) recent
      ) s
      where r.last_seen-r.first_seen>=make_interval(secs=>v_soak_seconds)
        and s.sample_count>=v_required_samples
        and s.failure_count=0
      order by r.last_seen desc
      limit 1
    )
    select
      deployment_id,commit_sha,first_seen,last_seen,sample_count,failure_count
    into
      v_bootstrap_deployment,v_bootstrap_commit,
      v_bootstrap_first,v_bootstrap_last,
      v_bootstrap_samples,v_bootstrap_failures
    from qualified;
  end if;

  if v_first_serving_at is not null then
    with recent as (
      select r.contract_ok,r.response_at,r.result_sequence
      from foundation.defence_health_probe_results r
      where r.target_id=p_target_id
        and r.response_at>=v_first_serving_at
        and r.response_at<=p_as_of
      order by r.response_at desc,r.result_sequence desc
      limit v_required_samples
    )
    select
      count(*)::integer,
      count(*) filter (where not contract_ok)::integer,
      min(response_at),
      max(response_at)
    into
      v_recent_samples,
      v_recent_failures,
      v_recent_first,
      v_recent_last
    from recent;
  end if;

  if v_serving.observation_id is not null then
    select tr.* into v_transition
    from foundation.defence_railway_transition_events tr
    where tr.target_id=p_target_id
      and tr.occurred_at<=p_as_of
      and (
        tr.deployment_id::text=v_serving.deployment_id
        or tr.commit_sha=v_serving.commit_sha
      )
    order by tr.occurred_at desc,tr.recorded_at desc,tr.event_id desc
    limit 1;
  end if;

  v_serving_fresh := coalesce(
    v_serving.observation_id is not null
    and v_serving.valid_until>p_as_of,
    false
  );

  v_source_identity_ok := coalesce(
    v_serving.repository is not null
    and lower(v_serving.repository)=lower(v_target.metadata->>'sourceRepository')
    and v_serving.branch=v_target.metadata->>'sourceBranch',
    false
  );

  v_source_fresh := coalesce(
    v_source_head.observation_id is not null
    and v_source_head.valid_until>p_as_of
    and lower(v_source_head.repository)=lower(v_target.metadata->>'sourceRepository')
    and v_source_head.branch=v_target.metadata->>'sourceBranch',
    false
  );

  v_health_fresh := coalesce(
    v_health.observation_id is not null
    and v_health.valid_until>p_as_of
    and v_health.health_state='healthy',
    false
  );

  v_transition_blocking := coalesce(
    v_transition.event_id is not null
    and v_transition.transition_state in ('failed','crashed')
    and v_transition.occurred_at>v_serving.observed_at,
    false
  );

  v_on_demand_canonical_unchanged := coalesce(
    v_health_target.probe_mode='on_demand'
    and v_last.canonical_deployment_id is not null
    and v_last.canonical_deployment_id=v_serving.deployment_id
    and v_last.canonical_commit_sha=v_serving.commit_sha
    and v_recent_samples>=v_required_samples
    and v_recent_failures=0,
    false
  );

  if v_last.canonical_deployment_id is not null then
    if v_serving.commit_sha is distinct from v_last.canonical_commit_sha then
      v_rollback_deployment := v_last.canonical_deployment_id;
      v_rollback_commit := v_last.canonical_commit_sha;
    elsif v_previous.canonical_deployment_id is not null then
      v_rollback_deployment := v_previous.canonical_deployment_id;
      v_rollback_commit := v_previous.canonical_commit_sha;
    end if;
  elsif v_bootstrap_deployment is not null then
    v_rollback_deployment := v_bootstrap_deployment;
    v_rollback_commit := v_bootstrap_commit;
  end if;

  if v_serving.observation_id is null then
    v_decision := 'hold';
    v_reason := 'serving-proof-missing';
  elsif not v_serving_fresh then
    v_decision := 'hold';
    v_reason := 'serving-proof-stale';
  elsif not v_source_identity_ok then
    v_decision := 'hold';
    v_reason := 'runtime-source-identity-mismatch';
  elsif not v_source_fresh then
    v_decision := 'hold';
    v_reason := 'source-watch-not-fresh';
  elsif v_transition_blocking then
    if v_rollback_deployment is not null then
      v_decision := 'rollback-recommended';
      v_reason := 'candidate-transition-failed-after-serving-proof';
    else
      v_decision := 'hold';
      v_reason := 'candidate-transition-failed-no-rollback-anchor';
    end if;
  elsif not v_health_fresh and not v_on_demand_canonical_unchanged then
    if v_rollback_deployment is not null then
      v_decision := 'rollback-recommended';
      v_reason := 'serving-health-not-clear';
    else
      v_decision := 'hold';
      v_reason := 'serving-health-not-clear-no-rollback-anchor';
    end if;
  elsif v_recent_failures>0 then
    if v_rollback_deployment is not null then
      v_decision := 'rollback-recommended';
      v_reason := 'post-release-health-failure';
    else
      v_decision := 'hold';
      v_reason := 'post-release-health-failure-no-rollback-anchor';
    end if;
  elsif v_last.canonical_deployment_id is not null
    and v_serving.commit_sha=v_last.canonical_commit_sha then
    v_decision := 'canonical';
    v_reason := 'canonical-serving';
  elsif v_first_serving_at is null
    or v_first_serving_at+make_interval(secs=>v_soak_seconds)>p_as_of
    or v_recent_samples<v_required_samples then
    v_decision := 'soaking';
    v_reason := 'admission-soak-incomplete';
  else
    v_decision := 'admit';
    v_reason := case
      when v_last.canonical_deployment_id is null then 'baseline-evidence-clear'
      else 'candidate-evidence-clear'
    end;
  end if;

  return jsonb_build_object(
    'releaseAdmission','shine-defence/release-admission-decision-v1',
    'schemaVersion','1.0.0',
    'targetId',p_target_id,
    'decision',v_decision,
    'reasonCode',v_reason,
    'serving',case
      when v_serving.observation_id is null then null
      else jsonb_build_object(
        'deploymentId',v_serving.deployment_id,
        'commitSha',v_serving.commit_sha,
        'repository',v_serving.repository,
        'branch',v_serving.branch,
        'firstServingAt',v_first_serving_at,
        'latestServingProofAt',v_serving.observed_at,
        'validUntil',v_serving.valid_until
      )
    end,
    'canonical',case
      when v_last.canonical_deployment_id is null then null
      else jsonb_build_object(
        'deploymentId',v_last.canonical_deployment_id,
        'commitSha',v_last.canonical_commit_sha
      )
    end,
    'rollbackTarget',case
      when v_rollback_deployment is null then null
      else jsonb_build_object(
        'deploymentId',v_rollback_deployment,
        'commitSha',v_rollback_commit
      )
    end,
    'evidence',jsonb_build_object(
      'servingFresh',v_serving_fresh,
      'sourceIdentityOk',v_source_identity_ok,
      'sourceWatchFresh',v_source_fresh,
      'sourceHeadSha',v_source_head.head_sha,
      'sourceAhead',coalesce(v_source_head.head_sha is distinct from v_serving.commit_sha,false),
      'healthFreshAndHealthy',v_health_fresh,
      'requiredPassingSamples',v_required_samples,
      'recentSampleCount',v_recent_samples,
      'recentFailureCount',v_recent_failures,
      'recentSampleWindowStartedAt',v_recent_first,
      'recentSampleWindowEndedAt',v_recent_last,
      'requiredSoakSeconds',v_soak_seconds,
      'transitionBlocking',v_transition_blocking,
      'onDemandCanonicalUnchanged',v_on_demand_canonical_unchanged,
      'latestCandidateTransitionState',v_transition.transition_state,
      'latestCandidateTransitionAt',v_transition.occurred_at,
      'bootstrapRollbackFound',v_bootstrap_deployment is not null,
      'bootstrapRollbackDeploymentId',v_bootstrap_deployment,
      'bootstrapRollbackCommitSha',v_bootstrap_commit,
      'bootstrapRollbackFirstSeenAt',v_bootstrap_first,
      'bootstrapRollbackLastSeenAt',v_bootstrap_last,
      'bootstrapRollbackSampleCount',v_bootstrap_samples,
      'bootstrapRollbackFailureCount',v_bootstrap_failures
    ),
    'evaluatedAt',p_as_of
  );
end;
$$;

revoke all on function foundation.evaluate_defence_release_admission_v1(text,timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.evaluate_defence_release_admission_v1(text,timestamptz)
  to shine_defence_runtime,service_role;

create or replace function foundation.reconcile_defence_release_admission_v1(
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_eval jsonb;
  v_last foundation.defence_release_admission_events%rowtype;
  v_decision text;
  v_state text;
  v_reason text;
  v_serving_deployment text;
  v_serving_commit text;
  v_canonical_deployment text;
  v_canonical_commit text;
  v_rollback_deployment text;
  v_rollback_commit text;
  v_inserted integer := 0;
  v_skipped integer := 0;
begin
  for v_target in
    select *
    from foundation.defence_estate_targets
    where provider='railway'
      and lifecycle='active'
      and required_for_estate
    order by target_id
  loop
    v_eval := foundation.evaluate_defence_release_admission_v1(
      v_target.target_id,
      p_observed_at
    );

    v_decision := v_eval->>'decision';
    v_reason := v_eval->>'reasonCode';
    v_serving_deployment := v_eval#>>'{serving,deploymentId}';
    v_serving_commit := v_eval#>>'{serving,commitSha}';
    v_rollback_deployment := v_eval#>>'{rollbackTarget,deploymentId}';
    v_rollback_commit := v_eval#>>'{rollbackTarget,commitSha}';

    if v_serving_deployment is null or v_serving_commit is null then
      v_skipped := v_skipped+1;
      continue;
    end if;

    v_last := null;
    select a.* into v_last
    from foundation.defence_release_admission_events a
    where a.target_id=v_target.target_id
      and a.observed_at<=p_observed_at
    order by a.observed_at desc,a.recorded_at desc,a.event_id desc
    limit 1;

    if v_decision='admit' then
      v_state := 'admitted';
      v_canonical_deployment := v_serving_deployment;
      v_canonical_commit := v_serving_commit;
    elsif v_decision='canonical' then
      if v_last.admission_state='rollback-recommended'
         and v_last.canonical_commit_sha=v_serving_commit
         and v_last.serving_commit_sha is distinct from v_serving_commit then
        v_state := 'rollback-observed';
        v_reason := 'serving-rollback-observed';
      else
        v_state := 'canonical';
      end if;
      v_canonical_deployment := v_serving_deployment;
      v_canonical_commit := v_serving_commit;
    else
      v_state := v_decision;
      v_canonical_deployment := v_last.canonical_deployment_id;
      v_canonical_commit := v_last.canonical_commit_sha;

      if v_canonical_deployment is null
         and v_rollback_deployment is not null
         and v_rollback_commit is not null then
        v_canonical_deployment := v_rollback_deployment;
        v_canonical_commit := v_rollback_commit;
      end if;
    end if;

    if v_state='canonical'
       and v_last.event_id is not null
       and v_last.admission_state in ('canonical','admitted','rollback-observed')
       and v_last.serving_deployment_id=v_serving_deployment
       and v_last.serving_commit_sha=v_serving_commit
       and v_last.canonical_deployment_id=v_canonical_deployment
       and v_last.canonical_commit_sha=v_canonical_commit then
      v_skipped := v_skipped+1;
      continue;
    end if;

    if v_last.event_id is not null
       and v_last.admission_state=v_state
       and v_last.reason_code=v_reason
       and v_last.serving_deployment_id=v_serving_deployment
       and v_last.serving_commit_sha=v_serving_commit
       and v_last.canonical_deployment_id is not distinct from v_canonical_deployment
       and v_last.canonical_commit_sha is not distinct from v_canonical_commit
       and v_last.rollback_deployment_id is not distinct from v_rollback_deployment
       and v_last.rollback_commit_sha is not distinct from v_rollback_commit then
      v_skipped := v_skipped+1;
      continue;
    end if;

    insert into foundation.defence_release_admission_events(
      target_id,admission_state,reason_code,
      serving_deployment_id,serving_commit_sha,
      canonical_deployment_id,canonical_commit_sha,
      rollback_deployment_id,rollback_commit_sha,
      observed_at,evidence,evidence_ref
    ) values (
      v_target.target_id,
      v_state,
      v_reason,
      v_serving_deployment,
      lower(v_serving_commit),
      v_canonical_deployment,
      case when v_canonical_commit is null then null else lower(v_canonical_commit) end,
      v_rollback_deployment,
      case when v_rollback_commit is null then null else lower(v_rollback_commit) end,
      p_observed_at,
      v_eval,
      'defence-release-admission:' ||
        v_target.target_id || ':' ||
        extract(epoch from p_observed_at)::numeric::text || ':' ||
        v_state || ':' || v_serving_deployment
    );

    v_inserted := v_inserted+1;
  end loop;

  return jsonb_build_object(
    'releaseAdmissionReconcile','shine-defence/release-admission-reconcile-v1',
    'schemaVersion','1.0.0',
    'observedAt',p_observed_at,
    'insertedEvents',v_inserted,
    'skippedTargets',v_skipped,
    'summary',foundation.get_defence_release_admission_summary_v1()
  );
end;
$$;


revoke all on function foundation.reconcile_defence_release_admission_v1(timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.reconcile_defence_release_admission_v1(timestamptz)
  to service_role;
