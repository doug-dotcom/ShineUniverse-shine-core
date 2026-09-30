begin;

-- Layer 60 tests closure semantics against deterministic Layer-59 source truth.
-- Replacing the reader is rollback-only and does not grant mutation authority.

create or replace function foundation.get_foundation_canonical_source_truth_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer60_truth_a$
  select jsonb_build_object(
    'foundationCanonicalSourceTruthResponse','shine-foundation/canonical-source-truth-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','pass',
    'reasonCodes','[]'::jsonb,
    'evidenceFingerprint',repeat('a',32),
    'binding',jsonb_build_object(
      'bindingId','60000000-0000-4000-8000-000000000001',
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('f',64)
    ),
    'runtimeHealthAffectsSourceTruth',false
  );
$layer60_truth_a$;

set local role service_role;
select foundation.record_foundation_release_promotion_closure_v1(
  'production',now()
);
reset role;

do $layer60_recorded$
declare
  r foundation.foundation_release_promotion_closures%rowtype;
  expected_hash text;
  s jsonb;
begin
  select * into r
  from foundation.foundation_release_promotion_closures
  where binding_id='60000000-0000-4000-8000-000000000001'::uuid
    and canonical_truth_fingerprint=repeat('a',32);

  if r.closure_id is null
     or r.release_ref<>'foundation:layer-58:eeeeeeee'
     or r.foundation_layer<>58
     or r.source_ref<>
       'github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40)
     or r.runtime_version<>'90'
     or r.artifact_sha256<>repeat('f',64) then
    raise exception 'Layer 60 closure receipt missing or wrong';
  end if;

  expected_hash:=encode(
    extensions.digest(convert_to(r.closure::text,'UTF8'),'sha256'),
    'hex'
  );

  if r.closure_sha256<>expected_hash
     or r.closure->>'sourceTruthClosed'<>'true'
     or r.closure->>'runtimeReadinessClaimed'<>'false'
     or r.closure->>'mutatesAuthoritativeTruth'<>'false' then
    raise exception 'Layer 60 closure receipt integrity/authority invalid';
  end if;

  s:=foundation.get_foundation_release_promotion_closure_status_v1(
    'production',now()
  );

  if s->>'state'<>'closed'
     or s->>'releaseClosed'<>'true'
     or s->>'integrityVerified'<>'true'
     or s->>'receiptCurrent'<>'true'
     or s->>'runtimeReadinessClaimed'<>'false'
     or s->>'mutatesAuthoritativeTruth'<>'false' then
    raise exception 'Layer 60 current closure status invalid: %',s;
  end if;
end;
$layer60_recorded$;

set local role service_role;
select foundation.record_foundation_release_promotion_closure_v1(
  'production',now()
);
select foundation.assert_foundation_release_promotion_closed_v1(
  'production',now()
);
reset role;

do $layer60_replay$
declare c integer;
begin
  select count(*) into c
  from foundation.foundation_release_promotion_closures
  where binding_id='60000000-0000-4000-8000-000000000001'::uuid
    and canonical_truth_fingerprint=repeat('a',32);

  if c<>1 then
    raise exception 'Layer 60 replay must not duplicate closure receipt';
  end if;
end;
$layer60_replay$;


-- Same immutable binding, new source-truth fingerprint: old closure becomes stale.
create or replace function foundation.get_foundation_canonical_source_truth_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer60_truth_b$
  select jsonb_build_object(
    'foundationCanonicalSourceTruthResponse','shine-foundation/canonical-source-truth-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','pass',
    'reasonCodes','[]'::jsonb,
    'evidenceFingerprint',repeat('b',32),
    'binding',jsonb_build_object(
      'bindingId','60000000-0000-4000-8000-000000000001',
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('f',64)
    ),
    'runtimeHealthAffectsSourceTruth',false
  );
$layer60_truth_b$;

do $layer60_stale$
declare s jsonb;
begin
  s:=foundation.get_foundation_release_promotion_closure_status_v1(
    'production',now()
  );

  if s->>'state'<>'stale'
     or s->>'releaseClosed'<>'false'
     or s->>'integrityVerified'<>'true'
     or s->>'receiptCurrent'<>'false' then
    raise exception 'Layer 60 changed source truth must stale old receipt: %',s;
  end if;
end;
$layer60_stale$;

set local role service_role;
do $layer60_assert_stale$
begin
  begin
    perform foundation.assert_foundation_release_promotion_closed_v1(
      'production',now()
    );
    raise exception 'Layer 60 stale assertion unexpectedly passed';
  exception when sqlstate '23514' then
    null;
  end;
end;
$layer60_assert_stale$;

select foundation.record_foundation_release_promotion_closure_v1(
  'production',now()
);
select foundation.assert_foundation_release_promotion_closed_v1(
  'production',now()
);
reset role;

do $layer60_refreshed$
declare s jsonb;c integer;
begin
  s:=foundation.get_foundation_release_promotion_closure_status_v1(
    'production',now()
  );
  select count(*) into c
  from foundation.foundation_release_promotion_closures
  where binding_id='60000000-0000-4000-8000-000000000001'::uuid;

  if s->>'state'<>'closed'
     or s->>'canonicalSourceTruthFingerprint'<>repeat('b',32)
     or c<>2 then
    raise exception 'Layer 60 refreshed closure invalid: % count %',s,c;
  end if;
end;
$layer60_refreshed$;


-- A failing Layer-59 source truth can never mint a closure receipt.
create or replace function foundation.get_foundation_canonical_source_truth_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer60_truth_fail$
  select jsonb_build_object(
    'foundationCanonicalSourceTruthResponse','shine-foundation/canonical-source-truth-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','fail',
    'reasonCodes',jsonb_build_array('registry-layer-mismatch'),
    'evidenceFingerprint',repeat('c',32),
    'binding',jsonb_build_object(
      'bindingId','60000000-0000-4000-8000-000000000001',
      'foundationLayer',58,
      'releaseRef','foundation:layer-58:eeeeeeee',
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('f',64)
    )
  );
$layer60_truth_fail$;

set local role service_role;
do $layer60_blocked_record$
declare v jsonb;
begin
  v:=foundation.record_foundation_release_promotion_closure_v1(
    'production',now()
  );

  if v->>'status'<>'not-closed'
     or v->>'releaseClosed'<>'false'
     or v->>'reasonCode'<>'canonical-source-truth-not-pass' then
    raise exception 'Layer 60 failing truth must not record closure: %',v;
  end if;
end;
$layer60_blocked_record$;
reset role;

do $layer60_blocked_status$
declare s jsonb;c integer;
begin
  s:=foundation.get_foundation_release_promotion_closure_status_v1(
    'production',now()
  );
  select count(*) into c
  from foundation.foundation_release_promotion_closures;

  if s->>'state'<>'blocked'
     or s->>'releaseClosed'<>'false'
     or c<>2 then
    raise exception 'Layer 60 failing truth must block without mutation: % count %',s,c;
  end if;
end;
$layer60_blocked_status$;


do $layer60_privileges$
begin
  if has_table_privilege(
       'service_role',
       'foundation.foundation_release_promotion_closures',
       'INSERT'
     )
     or has_table_privilege(
       'foundation_runtime',
       'foundation.foundation_release_promotion_closures',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_release_promotion_closure_status_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.record_foundation_release_promotion_closure_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.assert_foundation_release_promotion_closed_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.record_foundation_release_promotion_closure_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.assert_foundation_release_promotion_closed_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_release_promotion_closure_status_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_release_promotion_closure_status_v1(text,timestamptz)',
       'EXECUTE'
     ) then
    raise exception 'Layer 60 privilege boundary is incorrect';
  end if;
end;
$layer60_privileges$;

rollback;
