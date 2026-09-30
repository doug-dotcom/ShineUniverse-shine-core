begin;

-- Layer 61 tests the downstream projection against deterministic Layer-60 status.

create or replace function foundation.get_foundation_release_promotion_closure_status_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer61_closed$
  select jsonb_build_object(
    'foundationReleasePromotionClosureStatusResponse',
      'shine-foundation/release-promotion-closure-status-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','closed',
    'reasonCode','canonical-source-truth-closed',
    'releaseClosed',true,
    'integrityVerified',true,
    'receiptCurrent',true,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false,
    'binding',jsonb_build_object(
      'bindingId','61000000-0000-4000-8000-000000000001',
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceRef',
        'github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('f',64)
    ),
    'receipt',jsonb_build_object(
      'closureId','61000000-0000-4000-8000-000000000002',
      'closureSha256',repeat('a',64),
      'canonicalSourceTruthFingerprint',repeat('b',32),
      'closedAt','2026-09-30T00:00:00+00:00'
    )
  );
$layer61_closed$;

do $layer61_available$
declare
  v jsonb;
  expected jsonb;
  expected_hash text;
begin
  v:=foundation.get_foundation_promoted_release_v1(
    'production',now()
  );

  expected:=jsonb_build_object(
    'bindingId','61000000-0000-4000-8000-000000000001',
    'releaseRef','foundation:layer-58:eeeeeeee',
    'foundationLayer',58,
    'sourceRef',
      'github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
    'sourceCommitSha',repeat('e',40),
    'runtimeVersion','90',
    'artifactSha256',repeat('f',64),
    'closureId','61000000-0000-4000-8000-000000000002',
    'closureSha256',repeat('a',64),
    'canonicalSourceTruthFingerprint',repeat('b',32),
    'closedAt','2026-09-30T00:00:00+00:00'
  );

  expected_hash:=encode(
    extensions.digest(convert_to(expected::text,'UTF8'),'sha256'),
    'hex'
  );

  if v->>'available'<>'true'
     or v->>'state'<>'promoted'
     or v->>'reasonCode'<>'promotion-closure-current'
     or v->'promotedRelease'<>expected
     or v->>'promotedReleaseSha256'<>expected_hash
     or v->>'runtimeReadinessClaimed'<>'false'
     or v->>'mutatesAuthoritativeTruth'<>'false' then
    raise exception 'Layer 61 promoted release projection invalid: %',v;
  end if;
end;
$layer61_available$;

set local role foundation_runtime;
select foundation.assert_foundation_promoted_release_v1(
  'production',now()
);
reset role;

set local role shine_defence_runtime;
select foundation.assert_foundation_promoted_release_v1(
  'production',now()
);
reset role;


-- A stale closure is never projected as a promoted release.
create or replace function foundation.get_foundation_release_promotion_closure_status_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer61_stale$
  select jsonb_build_object(
    'state','stale',
    'reasonCode','promotion-closure-no-longer-current',
    'releaseClosed',false,
    'integrityVerified',true,
    'receiptCurrent',false,
    'binding',jsonb_build_object(
      'bindingId','61000000-0000-4000-8000-000000000001',
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee'
    )
  );
$layer61_stale$;

do $layer61_hold$
declare v jsonb;
begin
  v:=foundation.get_foundation_promoted_release_v1(
    'production',now()
  );

  if v->>'available'<>'false'
     or v->>'state'<>'hold'
     or v->>'reasonCode'<>'promotion-closure-no-longer-current'
     or v->'promotedRelease' <> 'null'::jsonb then
    raise exception 'Layer 61 stale closure must fail closed: %',v;
  end if;
end;
$layer61_hold$;

set local role foundation_runtime;
do $layer61_runtime_assert_blocks$
begin
  begin
    perform foundation.assert_foundation_promoted_release_v1(
      'production',now()
    );
    raise exception 'Layer 61 runtime assertion unexpectedly passed stale closure';
  exception when sqlstate '23514' then
    null;
  end;
end;
$layer61_runtime_assert_blocks$;
reset role;

set local role shine_defence_runtime;
do $layer61_defence_assert_blocks$
begin
  begin
    perform foundation.assert_foundation_promoted_release_v1(
      'production',now()
    );
    raise exception 'Layer 61 Defence assertion unexpectedly passed stale closure';
  exception when sqlstate '23514' then
    null;
  end;
end;
$layer61_defence_assert_blocks$;
reset role;


do $layer61_privileges$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_foundation_promoted_release_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.assert_foundation_promoted_release_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.assert_foundation_promoted_release_v1(text,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 61 privilege boundary is incorrect';
  end if;
end;
$layer61_privileges$;

rollback;
