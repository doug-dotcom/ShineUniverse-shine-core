-- Foundation Layer 61: consumer-safe promoted release projection.
-- Downstream consumers must not infer promotion completion from a raw immutable
-- binding. The only consumer-safe release is one backed by a current, integrity-
-- verified Layer-60 closure receipt for Layer-59 canonical source truth.

create or replace function foundation.get_foundation_promoted_release_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer61_promoted$
declare
  v_closure jsonb;
  v_binding jsonb;
  v_receipt jsonb;
  v_source_ref text;
  v_source_sha text;
  v_projection jsonb;
  v_projection_sha256 text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null then
    raise exception 'promoted-release-input-invalid';
  end if;

  v_closure :=
    foundation.get_foundation_release_promotion_closure_status_v1(
      p_environment,p_as_of
    );

  if v_closure->>'state'<>'closed'
     or v_closure->>'releaseClosed'<>'true'
     or v_closure->>'integrityVerified'<>'true'
     or v_closure->>'receiptCurrent'<>'true' then
    return jsonb_build_object(
      'foundationPromotedReleaseResponse',
        'shine-foundation/promoted-release-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'evaluatedAt',p_as_of,
      'available',false,
      'state','hold',
      'reasonCode',coalesce(
        v_closure->>'reasonCode',
        'promotion-closure-not-closed'
      ),
      'promotionClosureState',v_closure->>'state',
      'promotedRelease',null,
      'runtimeReadinessClaimed',false,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  v_binding := v_closure->'binding';
  v_receipt := v_closure->'receipt';
  v_source_ref := nullif(v_binding->>'sourceRef','');
  v_source_sha := lower(
    substring(coalesce(v_source_ref,'')
      from '/commit/([a-fA-F0-9]{40})$')
  );

  if nullif(v_binding->>'bindingId','') is null
     or nullif(v_binding->>'releaseRef','') is null
     or nullif(v_binding->>'foundationLayer','') is null
     or v_source_sha is null
     or nullif(v_binding->>'runtimeVersion','') is null
     or lower(coalesce(v_binding->>'artifactSha256',''))
          !~ '^[a-f0-9]{64}$'
     or nullif(v_receipt->>'closureId','') is null
     or lower(coalesce(v_receipt->>'closureSha256',''))
          !~ '^[a-f0-9]{64}$'
     or lower(coalesce(
          v_receipt->>'canonicalSourceTruthFingerprint',''
        )) !~ '^[a-f0-9]{32}$' then
    return jsonb_build_object(
      'foundationPromotedReleaseResponse',
        'shine-foundation/promoted-release-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'evaluatedAt',p_as_of,
      'available',false,
      'state','hold',
      'reasonCode','promotion-closure-evidence-incomplete',
      'promotionClosureState',v_closure->>'state',
      'promotedRelease',null,
      'runtimeReadinessClaimed',false,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  v_projection := jsonb_build_object(
    'bindingId',v_binding->>'bindingId',
    'releaseRef',v_binding->>'releaseRef',
    'foundationLayer',(v_binding->>'foundationLayer')::integer,
    'sourceRef',v_source_ref,
    'sourceCommitSha',v_source_sha,
    'runtimeVersion',v_binding->>'runtimeVersion',
    'artifactSha256',lower(v_binding->>'artifactSha256'),
    'closureId',v_receipt->>'closureId',
    'closureSha256',lower(v_receipt->>'closureSha256'),
    'canonicalSourceTruthFingerprint',
      lower(v_receipt->>'canonicalSourceTruthFingerprint'),
    'closedAt',v_receipt->>'closedAt'
  );

  v_projection_sha256 := encode(
    extensions.digest(
      convert_to(v_projection::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  return jsonb_build_object(
    'foundationPromotedReleaseResponse',
      'shine-foundation/promoted-release-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'available',true,
    'state','promoted',
    'reasonCode','promotion-closure-current',
    'promotionClosureState','closed',
    'promotedRelease',v_projection,
    'promotedReleaseSha256',v_projection_sha256,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
end;
$layer61_promoted$;

revoke all on function foundation.get_foundation_promoted_release_v1(
  text,timestamptz
) from public,anon,authenticated;
grant execute on function foundation.get_foundation_promoted_release_v1(
  text,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role;


create or replace function foundation.assert_foundation_promoted_release_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer61_assert$
declare
  v_release jsonb;
begin
  v_release :=
    foundation.get_foundation_promoted_release_v1(
      p_environment,p_as_of
    );

  if v_release->>'available'<>'true'
     or v_release->>'state'<>'promoted' then
    raise exception using
      errcode='23514',
      message='foundation-promoted-release-not-available',
      detail=left(v_release::text,4000);
  end if;

  return v_release;
end;
$layer61_assert$;

revoke all on function foundation.assert_foundation_promoted_release_v1(
  text,timestamptz
) from public,anon,authenticated;
grant execute on function foundation.assert_foundation_promoted_release_v1(
  text,timestamptz
) to foundation_runtime,shine_defence_runtime,service_role;
