-- Foundation Layer 64: durable promoted-release observations.
-- Consumer trust can disappear even while the older release-projection incident
-- domain is merely degraded. Observe promoted/hold directly without gaining
-- repair or release-mutation authority.

create or replace function foundation.foundation_promoted_release_semantic_fingerprint_v1(
  p_snapshot jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $layer64_fingerprint$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'contract',p_snapshot->>'foundationPromotedReleaseResponse',
          'schemaVersion',p_snapshot->>'schemaVersion',
          'environment',p_snapshot->>'environment',
          'available',p_snapshot->'available',
          'state',p_snapshot->>'state',
          'reasonCode',p_snapshot->>'reasonCode',
          'promotionClosureState',p_snapshot->>'promotionClosureState',
          'promotedReleaseSha256',p_snapshot->>'promotedReleaseSha256',
          'bindingId',p_snapshot#>>'{promotedRelease,bindingId}',
          'releaseRef',p_snapshot#>>'{promotedRelease,releaseRef}',
          'sourceCommitSha',p_snapshot#>>'{promotedRelease,sourceCommitSha}',
          'artifactSha256',p_snapshot#>>'{promotedRelease,artifactSha256}',
          'closureId',p_snapshot#>>'{promotedRelease,closureId}',
          'closureSha256',p_snapshot#>>'{promotedRelease,closureSha256}',
          'canonicalSourceTruthFingerprint',
            p_snapshot#>>'{promotedRelease,canonicalSourceTruthFingerprint}'
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$layer64_fingerprint$;

revoke all on function foundation.foundation_promoted_release_semantic_fingerprint_v1(jsonb)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime,service_role;


create table foundation.foundation_promoted_release_observations (
  observation_sequence bigint generated always as identity primary key,
  observation_id uuid not null unique default gen_random_uuid(),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  state text not null
    check (state in ('promoted','hold')),
  available boolean not null,
  reason_code text not null
    check (char_length(reason_code) between 1 and 160),
  promotion_closure_state text not null
    check (promotion_closure_state in ('closed','open','stale','invalid','blocked')),
  release_ref text
    check (
      release_ref is null
      or release_ref ~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'
    ),
  promoted_release_sha256 text
    check (
      promoted_release_sha256 is null
      or promoted_release_sha256 ~ '^[a-f0-9]{64}$'
    ),
  semantic_fingerprint text not null
    check (semantic_fingerprint ~ '^[a-f0-9]{64}$'),
  changed_from_previous boolean not null,
  snapshot jsonb not null
    check (jsonb_typeof(snapshot)='object'),
  observed_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  check (
    (
      state='promoted'
      and available
      and promotion_closure_state='closed'
      and release_ref is not null
      and promoted_release_sha256 is not null
    )
    or
    (
      state='hold'
      and not available
      and release_ref is null
      and promoted_release_sha256 is null
    )
  )
);

alter table foundation.foundation_promoted_release_observations enable row level security;

create policy foundation_runtime_promoted_release_observations_select
on foundation.foundation_promoted_release_observations
for select
to foundation_runtime
using (true);

revoke all on foundation.foundation_promoted_release_observations
  from public,anon,authenticated,foundation_gateway,shine_defence_runtime,service_role;
grant select on foundation.foundation_promoted_release_observations
  to foundation_runtime,service_role;

create index foundation_promoted_release_observations_env_time_idx
  on foundation.foundation_promoted_release_observations(
    environment,observed_at desc,observation_sequence desc
  );

create trigger foundation_promoted_release_observations_append_only
before update or delete on foundation.foundation_promoted_release_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_foundation_promoted_release_observation
with (security_invoker=true)
as
select distinct on (environment)
  observation_sequence,
  observation_id,
  environment,
  state,
  available,
  reason_code,
  promotion_closure_state,
  release_ref,
  promoted_release_sha256,
  semantic_fingerprint,
  changed_from_previous,
  snapshot,
  observed_at,
  recorded_at
from foundation.foundation_promoted_release_observations
order by environment,observed_at desc,observation_sequence desc;

revoke all on foundation.current_foundation_promoted_release_observation
  from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant select on foundation.current_foundation_promoted_release_observation
  to foundation_runtime,service_role;


create or replace function foundation.record_foundation_promoted_release_observation_v1(
  p_environment text default 'production',
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer64_record$
declare
  v_snapshot jsonb;
  v_prior foundation.foundation_promoted_release_observations%rowtype;
  v_fingerprint text;
  v_state text;
  v_available boolean;
  v_release_ref text;
  v_promoted_sha text;
  v_changed boolean;
  v_observation_id uuid;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_observed_at is null then
    raise exception 'promoted-release-observation-input-invalid';
  end if;

  v_snapshot :=
    foundation.get_foundation_promoted_release_v1(
      p_environment,p_observed_at
    );

  if v_snapshot->>'foundationPromotedReleaseResponse'
       is distinct from 'shine-foundation/promoted-release-response-v1'
     or v_snapshot->>'schemaVersion' is distinct from '1.0.0' then
    raise exception 'promoted-release-observation-contract-invalid';
  end if;

  v_state := v_snapshot->>'state';
  v_available := coalesce((v_snapshot->>'available')::boolean,false);
  v_release_ref := nullif(v_snapshot#>>'{promotedRelease,releaseRef}','');
  v_promoted_sha := nullif(v_snapshot->>'promotedReleaseSha256','');

  if (
       v_state='promoted'
       and v_available
       and v_snapshot->>'promotionClosureState'='closed'
       and v_release_ref ~ '^foundation:layer-[0-9]+:[a-f0-9]{8}$'
       and v_promoted_sha ~ '^[a-f0-9]{64}$'
     ) is not true
     and (
       v_state='hold'
       and not v_available
       and v_release_ref is null
       and v_promoted_sha is null
     ) is not true then
    raise exception 'promoted-release-observation-state-invalid';
  end if;

  v_fingerprint :=
    foundation.foundation_promoted_release_semantic_fingerprint_v1(
      v_snapshot
    );

  select * into v_prior
  from foundation.current_foundation_promoted_release_observation
  where environment=p_environment;

  v_changed :=
    v_prior.observation_id is null
    or v_prior.semantic_fingerprint is distinct from v_fingerprint;

  insert into foundation.foundation_promoted_release_observations(
    environment,
    state,
    available,
    reason_code,
    promotion_closure_state,
    release_ref,
    promoted_release_sha256,
    semantic_fingerprint,
    changed_from_previous,
    snapshot,
    observed_at
  )
  values (
    p_environment,
    v_state,
    v_available,
    v_snapshot->>'reasonCode',
    v_snapshot->>'promotionClosureState',
    v_release_ref,
    v_promoted_sha,
    v_fingerprint,
    v_changed,
    v_snapshot,
    p_observed_at
  )
  returning observation_id into v_observation_id;

  return jsonb_build_object(
    'foundationPromotedReleaseObservationRecordResponse',
      'shine-foundation/promoted-release-observation-record-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'observationId',v_observation_id,
    'observedAt',p_observed_at,
    'state',v_state,
    'available',v_available,
    'reasonCode',v_snapshot->>'reasonCode',
    'releaseRef',v_release_ref,
    'semanticFingerprint',v_fingerprint,
    'changedFromPrevious',v_changed,
    'status',case when v_changed then 'recorded-change' else 'recorded-heartbeat' end,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
end;
$layer64_record$;

revoke all on function foundation.record_foundation_promoted_release_observation_v1(
  text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_defence_runtime;
grant execute on function foundation.record_foundation_promoted_release_observation_v1(
  text,timestamptz
) to service_role;


create or replace function foundation.get_foundation_promoted_release_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer64_summary$
declare
  v_live jsonb;
  v_live_fingerprint text;
  v_current foundation.foundation_promoted_release_observations%rowtype;
  v_age_seconds integer;
  v_fresh boolean := false;
  v_matches_live boolean := false;
  v_state text;
  v_reason text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_max_age_seconds<60
     or p_max_age_seconds>3600 then
    raise exception 'promoted-release-observation-summary-input-invalid';
  end if;

  v_live :=
    foundation.get_foundation_promoted_release_v1(
      p_environment,p_as_of
    );
  v_live_fingerprint :=
    foundation.foundation_promoted_release_semantic_fingerprint_v1(v_live);

  select * into v_current
  from foundation.current_foundation_promoted_release_observation
  where environment=p_environment;

  if v_current.observation_id is not null then
    v_age_seconds := greatest(
      0,
      floor(extract(epoch from (p_as_of-v_current.observed_at)))::integer
    );
    v_fresh :=
      v_current.observed_at<=p_as_of
      and v_age_seconds<=p_max_age_seconds;
    v_matches_live :=
      v_current.semantic_fingerprint is not distinct from v_live_fingerprint;
  end if;

  if v_current.observation_id is null then
    v_state := 'unknown';
    v_reason := 'promoted-release-observation-missing';
  elsif not v_fresh then
    v_state := 'unknown';
    v_reason := 'promoted-release-observation-stale';
  elsif not v_matches_live then
    v_state := 'drift';
    v_reason := 'promoted-release-observation-drift';
  elsif v_live->>'state'='hold' then
    v_state := 'hold';
    v_reason := v_live->>'reasonCode';
  else
    v_state := 'normal';
    v_reason := 'promoted-release-current';
  end if;

  return jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'reasonCode',v_reason,
    'observationFresh',v_fresh,
    'observationMatchesLive',v_matches_live,
    'maxAgeSeconds',p_max_age_seconds,
    'observationAgeSeconds',v_age_seconds,
    'live',jsonb_build_object(
      'state',v_live->>'state',
      'available',v_live->'available',
      'reasonCode',v_live->>'reasonCode',
      'promotionClosureState',v_live->>'promotionClosureState',
      'releaseRef',v_live#>>'{promotedRelease,releaseRef}',
      'promotedReleaseSha256',v_live->>'promotedReleaseSha256',
      'semanticFingerprint',v_live_fingerprint
    ),
    'observation',case
      when v_current.observation_id is null then null
      else jsonb_build_object(
        'observationId',v_current.observation_id,
        'state',v_current.state,
        'available',v_current.available,
        'reasonCode',v_current.reason_code,
        'promotionClosureState',v_current.promotion_closure_state,
        'releaseRef',v_current.release_ref,
        'promotedReleaseSha256',v_current.promoted_release_sha256,
        'semanticFingerprint',v_current.semantic_fingerprint,
        'changedFromPrevious',v_current.changed_from_previous,
        'observedAt',v_current.observed_at
      )
    end,
    'recommendedAction',case v_state
      when 'normal' then 'none'
      when 'hold' then 'investigate-promotion-closure-state'
      when 'drift' then 'record-fresh-promoted-release-observation'
      else 'restore-promoted-release-observation-freshness'
    end,
    'automaticRepair',false,
    'runtimeReadinessClaimed',false,
    'mutatesAuthoritativeTruth',false
  );
end;
$layer64_summary$;

revoke all on function foundation.get_foundation_promoted_release_observation_summary_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_observation_summary_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
