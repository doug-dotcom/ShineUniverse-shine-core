-- Shine Defence rollback source dual-proof v2.
-- Repo-local OIDC attestations now prove both the rollback commit and the
-- paired canonical commit exist in the registered private repository.

alter table foundation.defence_rollback_source_attestations
  add column if not exists canonical_source_available boolean;

create or replace function foundation.record_defence_rollback_source_attestation_v2(
  p_target_id text,
  p_repository text,
  p_rollback_commit_sha text,
  p_canonical_commit_sha text,
  p_rollback_source_available boolean,
  p_canonical_source_available boolean,
  p_observed_at timestamptz,
  p_valid_until timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_admission foundation.defence_release_admission_events%rowtype;
  v_id uuid;
begin
  select * into v_target
  from foundation.defence_estate_targets
  where target_id=p_target_id
    and provider='railway'
    and lifecycle='active'
    and required_for_estate;

  if v_target.target_id is null then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','rollback-target-invalid',
      'targetId',p_target_id
    );
  end if;

  select * into v_admission
  from foundation.current_defence_release_admission
  where target_id=p_target_id;

  if v_admission.event_id is null
     or v_admission.rollback_commit_sha is null
     or v_admission.canonical_commit_sha is null then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','rollback-anchor-missing',
      'targetId',p_target_id
    );
  end if;

  if p_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
     or p_rollback_commit_sha !~ '^[a-fA-F0-9]{40}$'
     or p_canonical_commit_sha !~ '^[a-fA-F0-9]{40}$'
     or p_valid_until<=p_observed_at
     or p_evidence_ref is null
     or char_length(p_evidence_ref)>1024
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-rollback-source-attestation-v2' using errcode='22023';
  end if;

  if lower(p_repository)<>lower(v_target.metadata->>'sourceRepository')
     or lower(p_rollback_commit_sha)<>lower(v_admission.rollback_commit_sha)
     or lower(p_canonical_commit_sha)<>lower(v_admission.canonical_commit_sha) then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','rollback-attestation-binding-mismatch',
      'targetId',p_target_id
    );
  end if;

  insert into foundation.defence_rollback_source_attestations(
    target_id,repository,rollback_commit_sha,canonical_commit_sha,
    source_available,canonical_source_available,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    p_target_id,p_repository,lower(p_rollback_commit_sha),lower(p_canonical_commit_sha),
    p_rollback_source_available,p_canonical_source_available,
    p_observed_at,p_valid_until,p_evidence_ref,
    p_metadata || jsonb_build_object(
      'attestationContract','shine-defence/rollback-source-attestation-v2'
    )
  )
  on conflict (evidence_ref) do nothing
  returning observation_id into v_id;

  return jsonb_build_object(
    'status',case when v_id is null then 'replayed' else 'recorded' end,
    'targetId',p_target_id,
    'rollbackCommitSha',lower(p_rollback_commit_sha),
    'canonicalCommitSha',lower(p_canonical_commit_sha),
    'rollbackSourceAvailable',p_rollback_source_available,
    'canonicalSourceAvailable',p_canonical_source_available,
    'observationId',v_id,
    'validUntil',p_valid_until
  );
end;
$$;

revoke all on function foundation.record_defence_rollback_source_attestation_v2(
  text,text,text,text,boolean,boolean,timestamptz,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_rollback_source_attestation_v2(
  text,text,text,text,boolean,boolean,timestamptz,timestamptz,text,jsonb
) to service_role;


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
      proof.rollback_source_available,
      proof.canonical_source_available,
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
        r.source_available as rollback_source_available,
        r.canonical_source_available,
        r.observed_at,
        r.valid_until,
        case
          when r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
            then 'exact-current-pair'
          when r.canonical_commit_sha=a.rollback_commit_sha
            and r.canonical_source_available is true
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
          or (
            r.canonical_commit_sha=a.rollback_commit_sha
            and r.canonical_source_available is true
          )
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
        and proof_mode is not null
    ),
    count(*) filter (
      where rollback_commit_sha is not null
        and observation_id is not null
        and not source_available
        and valid_until>now()
        and proof_mode is not null
    ),
    count(*) filter (
      where rollback_commit_sha is not null
        and observation_id is not null
        and valid_until<=now()
        and proof_mode is not null
    ),
    count(*) filter (
      where rollback_commit_sha is not null
        and (observation_id is null or proof_mode is null)
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
      proof.canonical_source_available,
      proof.observed_at,
      proof.valid_until,
      proof.proof_mode
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_admission a using(target_id)
    left join lateral (
      select
        r.observation_id,
        r.source_available,
        r.canonical_source_available,
        r.observed_at,
        r.valid_until,
        case
          when r.rollback_commit_sha=a.rollback_commit_sha
            and r.canonical_commit_sha=a.canonical_commit_sha
            then 'exact-current-pair'
          when r.canonical_commit_sha=a.rollback_commit_sha
            and r.canonical_source_available is true
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
          or (
            r.canonical_commit_sha=a.rollback_commit_sha
            and r.canonical_source_available is true
          )
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
          when observation_id is null or proof_mode is null then 'source-proof-missing'
          when valid_until<=now() then 'source-proof-stale'
          when source_available then 'source-ready'
          else 'source-unavailable'
        end,
        'sourceProofMode',proof_mode,
        'sourceAvailable',source_available,
        'canonicalSourceAvailable',canonical_source_available,
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
          when observation_id is null or proof_mode is null then 'rollback-source-proof-missing'
          when valid_until<=now() then 'rollback-source-proof-stale'
          when not source_available then 'rollback-source-unavailable'
          else null
        end
      ) order by target_id
    ) filter (
      where rollback_commit_sha is not null
        and (
          observation_id is null
          or proof_mode is null
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
    'schemaVersion','1.2.0',
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
