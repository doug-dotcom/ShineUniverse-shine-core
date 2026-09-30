begin;

create or replace function foundation.get_foundation_promoted_release_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer64_promoted$
  select jsonb_build_object(
    'foundationPromotedReleaseResponse','shine-foundation/promoted-release-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'available',true,
    'state','promoted',
    'reasonCode','promotion-closure-current',
    'promotionClosureState','closed',
    'promotedRelease',jsonb_build_object(
      'bindingId','64000000-0000-4000-8000-000000000001',
      'releaseRef','foundation:layer-58:eeeeeeee',
      'foundationLayer',58,
      'sourceRef','github://doug-dotcom/ShineUniverse-shine-core/commit/'||repeat('e',40),
      'sourceCommitSha',repeat('e',40),
      'runtimeVersion','90',
      'artifactSha256',repeat('f',64),
      'closureId','64000000-0000-4000-8000-000000000002',
      'closureSha256',repeat('a',64),
      'canonicalSourceTruthFingerprint',repeat('b',32),
      'closedAt','2026-09-30T00:00:00+00:00'
    ),
    'promotedReleaseSha256',repeat('c',64),
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
$layer64_promoted$;

set local role service_role;
select foundation.record_foundation_promoted_release_observation_v1(
  'production','2026-09-30T00:00:00+00:00'
);
select foundation.record_foundation_promoted_release_observation_v1(
  'production','2026-09-30T00:05:00+00:00'
);
reset role;

do $layer64_promoted_checks$
declare
  first_row foundation.foundation_promoted_release_observations%rowtype;
  second_row foundation.foundation_promoted_release_observations%rowtype;
  summary jsonb;
begin
  select * into first_row
  from foundation.foundation_promoted_release_observations
  where environment='production'
  order by observed_at,observation_sequence
  limit 1;

  select * into second_row
  from foundation.foundation_promoted_release_observations
  where environment='production'
  order by observed_at desc,observation_sequence desc
  limit 1;

  if first_row.state<>'promoted'
     or first_row.available is not true
     or first_row.release_ref<>'foundation:layer-58:eeeeeeee'
     or first_row.changed_from_previous is not true
     or second_row.changed_from_previous is not false
     or first_row.semantic_fingerprint is distinct from second_row.semantic_fingerprint then
    raise exception 'Layer 64 promoted heartbeat semantics invalid';
  end if;

  summary:=foundation.get_foundation_promoted_release_observation_summary_v1(
    'production','2026-09-30T00:05:00+00:00',600
  );

  if summary->>'state'<>'normal'
     or summary->>'observationFresh'<>'true'
     or summary->>'observationMatchesLive'<>'true'
     or summary#>>'{live,releaseRef}'<>'foundation:layer-58:eeeeeeee' then
    raise exception 'Layer 64 normal summary invalid: %',summary;
  end if;
end;
$layer64_promoted_checks$;


create or replace function foundation.get_foundation_promoted_release_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer64_hold$
  select jsonb_build_object(
    'foundationPromotedReleaseResponse','shine-foundation/promoted-release-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'available',false,
    'state','hold',
    'reasonCode','promotion-closure-no-longer-current',
    'promotionClosureState','stale',
    'promotedRelease',null,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
$layer64_hold$;

do $layer64_drift_before_record$
declare summary jsonb;
begin
  summary:=foundation.get_foundation_promoted_release_observation_summary_v1(
    'production','2026-09-30T00:10:00+00:00',600
  );

  if summary->>'state'<>'drift'
     or summary->>'reasonCode'<>'promoted-release-observation-drift'
     or summary->>'observationFresh'<>'true'
     or summary->>'observationMatchesLive'<>'false' then
    raise exception 'Layer 64 live drift must be visible before next record: %',summary;
  end if;
end;
$layer64_drift_before_record$;

set local role service_role;
select foundation.record_foundation_promoted_release_observation_v1(
  'production','2026-09-30T00:10:00+00:00'
);
reset role;

do $layer64_hold_checks$
declare
  current_row foundation.foundation_promoted_release_observations%rowtype;
  summary jsonb;
  stale_summary jsonb;
begin
  select * into current_row
  from foundation.current_foundation_promoted_release_observation
  where environment='production';

  if current_row.state<>'hold'
     or current_row.available is not false
     or current_row.release_ref is not null
     or current_row.promoted_release_sha256 is not null
     or current_row.changed_from_previous is not true then
    raise exception 'Layer 64 hold observation invalid';
  end if;

  summary:=foundation.get_foundation_promoted_release_observation_summary_v1(
    'production','2026-09-30T00:10:00+00:00',600
  );

  if summary->>'state'<>'hold'
     or summary->>'reasonCode'<>'promotion-closure-no-longer-current'
     or summary->>'observationMatchesLive'<>'true' then
    raise exception 'Layer 64 hold summary invalid: %',summary;
  end if;

  stale_summary:=foundation.get_foundation_promoted_release_observation_summary_v1(
    'production','2026-09-30T00:21:01+00:00',600
  );

  if stale_summary->>'state'<>'unknown'
     or stale_summary->>'reasonCode'<>'promoted-release-observation-stale'
     or stale_summary->>'observationFresh'<>'false' then
    raise exception 'Layer 64 stale observer must fail visibly: %',stale_summary;
  end if;
end;
$layer64_hold_checks$;


do $layer64_privileges$
begin
  if has_table_privilege(
       'service_role',
       'foundation.foundation_promoted_release_observations',
       'INSERT'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.record_foundation_promoted_release_observation_v1(text,timestamptz)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.record_foundation_promoted_release_observation_v1(text,timestamptz)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_observation_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 64 privilege boundary is incorrect';
  end if;
end;
$layer64_privileges$;

do $layer64_append_only$
declare id uuid;
begin
  select observation_id into id
  from foundation.current_foundation_promoted_release_observation
  where environment='production';

  begin
    update foundation.foundation_promoted_release_observations
    set reason_code='mutation'
    where observation_id=id;
    raise exception 'Layer 64 observation history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$layer64_append_only$;

rollback;
