-- Race-safe rollback source attestation v4.
-- The authorised immutable workflow submits the pair returned by its claim.
-- Verify that pair against append-only admission history, not mutable current state.

create or replace function foundation.record_defence_rollback_source_attestation_v4(
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
    return jsonb_build_object('status','rejected','reasonCode','rollback-target-invalid','targetId',p_target_id);
  end if;

  select * into v_admission
  from foundation.defence_release_admission_events
  where target_id=p_target_id
    and lower(rollback_commit_sha)=lower(p_rollback_commit_sha)
    and lower(canonical_commit_sha)=lower(p_canonical_commit_sha)
  order by recorded_at desc,event_id desc
  limit 1;

  if v_admission.event_id is null then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','rollback-attestation-history-binding-mismatch',
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
    raise exception 'invalid-rollback-source-attestation-v4' using errcode='22023';
  end if;

  if lower(p_repository)<>lower(v_target.metadata->>'sourceRepository') then
    return jsonb_build_object('status','rejected','reasonCode','rollback-attestation-repository-mismatch','targetId',p_target_id);
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
      'attestationContract','shine-defence/rollback-source-attestation-v4',
      'admissionEventId',v_admission.event_id
    )
  )
  on conflict (evidence_ref) do nothing
  returning observation_id into v_id;

  return jsonb_build_object(
    'status',case when v_id is null then 'replayed' else 'recorded' end,
    'targetId',p_target_id,
    'admissionEventId',v_admission.event_id,
    'rollbackCommitSha',lower(p_rollback_commit_sha),
    'canonicalCommitSha',lower(p_canonical_commit_sha),
    'rollbackSourceAvailable',p_rollback_source_available,
    'canonicalSourceAvailable',p_canonical_source_available,
    'observationId',v_id,
    'validUntil',p_valid_until
  );
end;
$$;

revoke all on function foundation.record_defence_rollback_source_attestation_v4(
  text,text,text,text,boolean,boolean,timestamptz,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_rollback_source_attestation_v4(
  text,text,text,text,boolean,boolean,timestamptz,timestamptz,text,jsonb
) to service_role;
