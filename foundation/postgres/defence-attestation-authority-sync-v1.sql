-- Shine Defence signed attestation-authority synchronization v1.
-- Only a validated Core publisher may append authority state. Database rules
-- independently prevent predecessor skips, promotion replay and altered rollback bytes.

create or replace function foundation.record_defence_attestation_authority_activation_v1(
  p_authority_sha text,
  p_authority_ref text,
  p_workflow_blob_sha text,
  p_activation_kind text,
  p_activated_at timestamptz,
  p_predecessor_authority_sha text,
  p_restore_from_sequence bigint,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_current foundation.defence_attestation_authority_activations%rowtype;
  v_restore foundation.defence_attestation_authority_activations%rowtype;
  v_existing foundation.defence_attestation_authority_activations%rowtype;
  v_sequence bigint;
  v_lineage_sequence bigint;
  v_expected_ref text;
begin
  if p_authority_sha !~ '^[a-fA-F0-9]{40}$'
     or p_workflow_blob_sha !~ '^[a-fA-F0-9]{40}$'
     or p_activation_kind not in ('promotion','rollback')
     or p_activated_at is null
     or p_predecessor_authority_sha !~ '^[a-fA-F0-9]{40}$'
     or p_evidence_ref is null
     or length(p_evidence_ref) not between 1 and 1024
     or p_evidence_ref ~ '[[:cntrl:]]'
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-attestation-authority-activation' using errcode='22023';
  end if;

  if not (p_metadata ? 'lineageSequence')
     or coalesce(p_metadata->>'lineageSequence','') !~ '^[0-9]{1,18}$' then
    raise exception 'invalid-attestation-authority-lineage-sequence' using errcode='22023';
  end if;

  v_lineage_sequence := (p_metadata->>'lineageSequence')::bigint;

  v_expected_ref :=
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/' ||
    'shine-defence-release-attestation-v1.yml@' ||
    lower(p_authority_sha);

  if p_authority_ref<>v_expected_ref then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','authority-ref-mismatch'
    );
  end if;

  select * into v_existing
  from foundation.defence_attestation_authority_activations
  where evidence_ref=p_evidence_ref
  limit 1;

  if v_existing.activation_sequence is not null then
    if lower(v_existing.authority_sha)=lower(p_authority_sha)
       and v_existing.authority_ref=p_authority_ref
       and lower(v_existing.workflow_blob_sha)=lower(p_workflow_blob_sha)
       and v_existing.activation_kind=p_activation_kind
       and v_existing.activated_at=p_activated_at then
      return jsonb_build_object(
        'status','replayed',
        'activationSequence',v_existing.activation_sequence,
        'authoritySha',lower(v_existing.authority_sha)
      );
    end if;

    return jsonb_build_object(
      'status','rejected',
      'reasonCode','authority-evidence-ref-conflict'
    );
  end if;

  select * into v_current
  from foundation.defence_attestation_authority_activations
  order by activated_at desc,activation_sequence desc
  limit 1
  for share;

  if v_current.activation_sequence is null then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','active-authority-missing'
    );
  end if;

  if v_lineage_sequence<>v_current.activation_sequence+1 then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','authority-lineage-sequence-gap',
      'expectedLineageSequence',v_current.activation_sequence+1
    );
  end if;

  if lower(p_predecessor_authority_sha)<>lower(v_current.authority_sha) then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','authority-predecessor-mismatch',
      'expectedPredecessorAuthoritySha',lower(v_current.authority_sha)
    );
  end if;

  if p_activated_at<=v_current.activated_at then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','authority-activation-time-regression'
    );
  end if;

  if p_activation_kind='promotion' then
    if p_restore_from_sequence is not null then
      return jsonb_build_object(
        'status','rejected',
        'reasonCode','promotion-restore-sequence-forbidden'
      );
    end if;

    if exists (
      select 1
      from foundation.defence_attestation_authority_activations a
      where lower(a.authority_sha)=lower(p_authority_sha)
    ) then
      return jsonb_build_object(
        'status','rejected',
        'reasonCode','promotion-authority-replay'
      );
    end if;
  else
    if p_restore_from_sequence is null then
      return jsonb_build_object(
        'status','rejected',
        'reasonCode','rollback-source-sequence-required'
      );
    end if;

    select * into v_restore
    from foundation.defence_attestation_authority_activations
    where activation_sequence=p_restore_from_sequence
      and activation_sequence<v_current.activation_sequence
    limit 1;

    if v_restore.activation_sequence is null then
      return jsonb_build_object(
        'status','rejected',
        'reasonCode','rollback-source-sequence-invalid'
      );
    end if;

    if lower(v_restore.authority_sha)<>lower(p_authority_sha) then
      return jsonb_build_object(
        'status','rejected',
        'reasonCode','rollback-authority-mismatch'
      );
    end if;

    if lower(v_restore.workflow_blob_sha)<>lower(p_workflow_blob_sha) then
      return jsonb_build_object(
        'status','rejected',
        'reasonCode','rollback-workflow-blob-mismatch'
      );
    end if;
  end if;

  insert into foundation.defence_attestation_authority_activations(
    authority_sha,authority_ref,workflow_blob_sha,activation_kind,
    activated_at,evidence_ref,metadata
  ) values (
    lower(p_authority_sha),p_authority_ref,lower(p_workflow_blob_sha),
    p_activation_kind,p_activated_at,p_evidence_ref,p_metadata
  )
  returning activation_sequence into v_sequence;

  return jsonb_build_object(
    'status','recorded',
    'activationSequence',v_sequence,
    'authoritySha',lower(p_authority_sha),
    'activationKind',p_activation_kind,
    'activatedAt',p_activated_at
  );
end;
$$;

revoke all on function foundation.record_defence_attestation_authority_activation_v1(
  text,text,text,text,timestamptz,text,bigint,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;

grant execute on function foundation.record_defence_attestation_authority_activation_v1(
  text,text,text,text,timestamptz,text,bigint,text,jsonb
) to service_role;
