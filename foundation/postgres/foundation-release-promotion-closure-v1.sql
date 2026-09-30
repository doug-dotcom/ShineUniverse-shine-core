-- Foundation Layer 60: immutable promotion-closure receipts.
-- Binding, projection repair and promotion closure remain deliberately separate.
-- A release may exist while projections converge, but it is not "closed" until
-- Layer 59 proves that the immutable binding, registry, release ledger and
-- deployment identity all agree on the exact same release.

create table foundation.foundation_release_promotion_closures (
  closure_sequence bigint generated always as identity primary key,
  closure_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  binding_id uuid not null,
  release_ref text not null
    check (release_ref ~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'),
  foundation_layer integer not null check (foundation_layer > 0),
  source_ref text not null
    check (source_ref ~ '^github://[^/]+/[^/]+/commit/[a-fA-F0-9]{40}$'),
  runtime_version text not null
    check (char_length(runtime_version) between 1 and 128),
  artifact_sha256 text not null
    check (artifact_sha256 ~ '^[a-fA-F0-9]{64}$'),
  canonical_truth_fingerprint text not null
    check (canonical_truth_fingerprint ~ '^[a-f0-9]{32}$'),
  closure jsonb not null check (jsonb_typeof(closure)='object'),
  closure_sha256 text not null check (closure_sha256 ~ '^[a-f0-9]{64}$'),
  closed_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  unique(environment,binding_id,canonical_truth_fingerprint)
);

alter table foundation.foundation_release_promotion_closures enable row level security;

create policy foundation_runtime_release_promotion_closures_select
on foundation.foundation_release_promotion_closures
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_release_promotion_closures
  from public,anon,authenticated,foundation_gateway,service_role;
grant select on foundation.foundation_release_promotion_closures
  to foundation_runtime,service_role;

create index foundation_release_promotion_closures_current_idx
  on foundation.foundation_release_promotion_closures(
    environment,binding_id,closed_at desc,closure_sequence desc
  );

create trigger foundation_release_promotion_closures_append_only
before update or delete on foundation.foundation_release_promotion_closures
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.get_foundation_release_promotion_closure_status_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer60_status$
declare
  v_truth jsonb;
  v_binding jsonb;
  v_binding_id uuid;
  v_receipt foundation.foundation_release_promotion_closures%rowtype;
  v_expected_hash text;
  v_integrity boolean := false;
  v_current boolean := false;
  v_state text := 'open';
  v_reason text := 'promotion-closure-receipt-missing';
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'promotion-closure-environment-invalid';
  end if;

  v_truth :=
    foundation.get_foundation_canonical_source_truth_v1(
      p_environment,p_as_of
    );
  v_binding := v_truth->'binding';

  begin
    v_binding_id := nullif(v_binding->>'bindingId','')::uuid;
  exception when invalid_text_representation then
    v_binding_id := null;
  end;

  if v_binding_id is not null then
    select * into v_receipt
    from foundation.foundation_release_promotion_closures
    where environment=p_environment
      and binding_id=v_binding_id
    order by closed_at desc,closure_sequence desc
    limit 1;
  end if;

  if v_receipt.closure_id is not null then
    v_expected_hash := encode(
      extensions.digest(
        convert_to(v_receipt.closure::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );
    v_integrity := v_receipt.closure_sha256 is not distinct from v_expected_hash;

    v_current :=
      v_integrity
      and v_truth->>'state'='pass'
      and v_receipt.canonical_truth_fingerprint
            is not distinct from v_truth->>'evidenceFingerprint'
      and v_receipt.release_ref
            is not distinct from v_binding->>'releaseRef'
      and v_receipt.foundation_layer
            is not distinct from nullif(v_binding->>'foundationLayer','')::integer
      and v_receipt.source_ref
            is not distinct from v_binding->>'sourceRef'
      and v_receipt.runtime_version
            is not distinct from v_binding->>'runtimeVersion'
      and lower(v_receipt.artifact_sha256)
            is not distinct from lower(coalesce(v_binding->>'artifactSha256',''));
  end if;

  if v_truth->>'state'<>'pass' then
    v_state := 'blocked';
    v_reason := 'canonical-source-truth-not-pass';
  elsif v_binding_id is null then
    v_state := 'blocked';
    v_reason := 'canonical-binding-missing';
  elsif v_receipt.closure_id is null then
    v_state := 'open';
    v_reason := 'promotion-closure-receipt-missing';
  elsif not v_integrity then
    v_state := 'invalid';
    v_reason := 'promotion-closure-integrity-failed';
  elsif not v_current then
    v_state := 'stale';
    v_reason := 'promotion-closure-no-longer-current';
  else
    v_state := 'closed';
    v_reason := 'canonical-source-truth-closed';
  end if;

  return jsonb_build_object(
    'foundationReleasePromotionClosureStatusResponse',
      'shine-foundation/release-promotion-closure-status-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'reasonCode',v_reason,
    'releaseClosed',v_state='closed',
    'canonicalSourceTruthState',v_truth->>'state',
    'canonicalSourceTruthFingerprint',v_truth->>'evidenceFingerprint',
    'binding',v_binding,
    'receipt',case
      when v_receipt.closure_id is null then null
      else jsonb_build_object(
        'closureId',v_receipt.closure_id,
        'bindingId',v_receipt.binding_id,
        'releaseRef',v_receipt.release_ref,
        'foundationLayer',v_receipt.foundation_layer,
        'sourceRef',v_receipt.source_ref,
        'runtimeVersion',v_receipt.runtime_version,
        'artifactSha256',v_receipt.artifact_sha256,
        'canonicalSourceTruthFingerprint',v_receipt.canonical_truth_fingerprint,
        'closureSha256',v_receipt.closure_sha256,
        'closedAt',v_receipt.closed_at
      )
    end,
    'integrityVerified',v_integrity,
    'receiptCurrent',v_current,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
end;
$layer60_status$;

revoke all on function foundation.get_foundation_release_promotion_closure_status_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_foundation_release_promotion_closure_status_v1(
  text,timestamptz
) to foundation_runtime,service_role;


create or replace function foundation.record_foundation_release_promotion_closure_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer60_record$
declare
  v_truth jsonb;
  v_binding jsonb;
  v_binding_id uuid;
  v_release_ref text;
  v_layer integer;
  v_source_ref text;
  v_runtime_version text;
  v_artifact_sha256 text;
  v_fingerprint text;
  v_existing foundation.foundation_release_promotion_closures%rowtype;
  v_closure jsonb;
  v_closure_hash text;
  v_closure_id uuid;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_observed_at is null then
    raise exception 'promotion-closure-input-invalid';
  end if;

  v_truth :=
    foundation.get_foundation_canonical_source_truth_v1(
      p_environment,p_observed_at
    );

  if v_truth->>'state'<>'pass' then
    return jsonb_build_object(
      'foundationReleasePromotionClosureRecordResponse',
        'shine-foundation/release-promotion-closure-record-response-v1',
      'schemaVersion','1.0.0',
      'status','not-closed',
      'releaseClosed',false,
      'reasonCode','canonical-source-truth-not-pass',
      'canonicalSourceTruth',v_truth,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  v_binding := v_truth->'binding';

  begin
    v_binding_id := nullif(v_binding->>'bindingId','')::uuid;
    v_layer := nullif(v_binding->>'foundationLayer','')::integer;
  exception when others then
    raise exception 'promotion-closure-binding-invalid';
  end;

  v_release_ref := nullif(v_binding->>'releaseRef','');
  v_source_ref := nullif(v_binding->>'sourceRef','');
  v_runtime_version := nullif(v_binding->>'runtimeVersion','');
  v_artifact_sha256 := lower(coalesce(v_binding->>'artifactSha256',''));
  v_fingerprint := lower(coalesce(v_truth->>'evidenceFingerprint',''));

  if v_binding_id is null
     or v_layer is null
     or v_layer<=0
     or v_release_ref !~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'
     or v_source_ref !~ '^github://[^/]+/[^/]+/commit/[a-fA-F0-9]{40}$'
     or v_runtime_version is null
     or v_artifact_sha256 !~ '^[a-f0-9]{64}$'
     or v_fingerprint !~ '^[a-f0-9]{32}$' then
    raise exception 'promotion-closure-source-truth-incomplete';
  end if;

  select * into v_existing
  from foundation.foundation_release_promotion_closures
  where environment=p_environment
    and binding_id=v_binding_id
    and canonical_truth_fingerprint=v_fingerprint;

  if v_existing.closure_id is not null then
    v_closure_hash := encode(
      extensions.digest(
        convert_to(v_existing.closure::text,'UTF8'),
        'sha256'
      ),
      'hex'
    );

    if v_existing.closure_sha256 is distinct from v_closure_hash then
      raise exception 'promotion-closure-existing-integrity-failed';
    end if;

    return jsonb_build_object(
      'foundationReleasePromotionClosureRecordResponse',
        'shine-foundation/release-promotion-closure-record-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'releaseClosed',true,
      'closureId',v_existing.closure_id,
      'releaseRef',v_existing.release_ref,
      'canonicalSourceTruthFingerprint',v_existing.canonical_truth_fingerprint,
      'closureSha256',v_existing.closure_sha256,
      'closedAt',v_existing.closed_at,
      'mutatesAuthoritativeTruth',false
    );
  end if;

  v_closure_id := gen_random_uuid();

  v_closure := jsonb_build_object(
    'foundationReleasePromotionClosure',
      'shine-foundation/release-promotion-closure-v1',
    'schemaVersion','1.0.0',
    'closureId',v_closure_id,
    'environment',p_environment,
    'bindingId',v_binding_id,
    'releaseRef',v_release_ref,
    'foundationLayer',v_layer,
    'sourceRef',v_source_ref,
    'runtimeVersion',v_runtime_version,
    'artifactSha256',v_artifact_sha256,
    'canonicalSourceTruthFingerprint',v_fingerprint,
    'canonicalSourceTruth',v_truth,
    'sourceTruthClosed',true,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false,
    'closedAt',p_observed_at
  );

  v_closure_hash := encode(
    extensions.digest(
      convert_to(v_closure::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.foundation_release_promotion_closures(
    closure_id,environment,binding_id,release_ref,foundation_layer,
    source_ref,runtime_version,artifact_sha256,
    canonical_truth_fingerprint,closure,closure_sha256,closed_at
  )
  values (
    v_closure_id,p_environment,v_binding_id,v_release_ref,v_layer,
    v_source_ref,v_runtime_version,v_artifact_sha256,
    v_fingerprint,v_closure,v_closure_hash,p_observed_at
  );

  return jsonb_build_object(
    'foundationReleasePromotionClosureRecordResponse',
      'shine-foundation/release-promotion-closure-record-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded-new',
    'releaseClosed',true,
    'closureId',v_closure_id,
    'releaseRef',v_release_ref,
    'canonicalSourceTruthFingerprint',v_fingerprint,
    'closureSha256',v_closure_hash,
    'closedAt',p_observed_at,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
end;
$layer60_record$;

revoke all on function foundation.record_foundation_release_promotion_closure_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.record_foundation_release_promotion_closure_v1(
  text,timestamptz
) to service_role;


create or replace function foundation.assert_foundation_release_promotion_closed_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer60_assert$
declare
  v_status jsonb;
begin
  v_status :=
    foundation.get_foundation_release_promotion_closure_status_v1(
      p_environment,p_as_of
    );

  if v_status->>'state'<>'closed' then
    raise exception using
      errcode='23514',
      message='foundation-release-promotion-not-closed',
      detail=left(v_status::text,4000);
  end if;

  return v_status;
end;
$layer60_assert$;

revoke all on function foundation.assert_foundation_release_promotion_closed_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.assert_foundation_release_promotion_closed_v1(
  text,timestamptz
) to service_role;
