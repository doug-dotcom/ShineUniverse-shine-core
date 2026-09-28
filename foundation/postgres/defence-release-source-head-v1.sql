-- Shine Defence release source-head watch v1.
-- Credential-free fallback for Railway deployment transition visibility.

create table foundation.defence_release_source_head_observations (
  observation_id uuid primary key default gen_random_uuid(),
  target_id text not null references foundation.defence_estate_targets(target_id),
  repository text not null
    check (repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'),
  branch text not null
    check (length(branch) between 1 and 200 and branch !~ '[[:cntrl:]]'),
  head_sha text not null
    check (head_sha ~ '^[a-fA-F0-9]{40}$'),
  head_committed_at timestamptz not null,
  observed_at timestamptz not null,
  valid_until timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (valid_until>observed_at),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_release_source_head_observations enable row level security;

create policy shine_defence_runtime_release_source_head_select
on foundation.defence_release_source_head_observations
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_release_source_head_observations
  from public,anon,authenticated;
grant select on foundation.defence_release_source_head_observations
  to shine_defence_runtime,service_role;
grant insert on foundation.defence_release_source_head_observations
  to service_role;

create index defence_release_source_head_target_time_idx
  on foundation.defence_release_source_head_observations(
    target_id,observed_at desc,recorded_at desc
  );

create trigger defence_release_source_head_append_only
before update or delete on foundation.defence_release_source_head_observations
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_release_source_heads
with (security_invoker=true)
as
select distinct on (target_id)
  observation_id,target_id,repository,branch,head_sha,head_committed_at,
  observed_at,valid_until,evidence_ref,metadata,recorded_at
from foundation.defence_release_source_head_observations
order by target_id,observed_at desc,recorded_at desc,observation_id desc;

revoke all on foundation.current_defence_release_source_heads
  from public,anon,authenticated;
grant select on foundation.current_defence_release_source_heads
  to shine_defence_runtime,service_role;


update foundation.defence_estate_targets
set metadata = metadata || jsonb_build_object(
  'sourceHeadWatchRequired',true,
  'sourceHeadWatchEffectiveAt',now(),
  'sourceHeadWatchContract','shine-defence/release-source-watch-v1'
),
updated_at=now()
where provider='railway'
  and lifecycle='active'
  and required_for_estate;


create or replace function foundation.record_defence_release_source_head_v1(
  p_target_id text,
  p_repository text,
  p_branch text,
  p_head_sha text,
  p_head_committed_at timestamptz,
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
  v_id uuid;
begin
  select * into v_target
  from foundation.defence_estate_targets
  where target_id=p_target_id
    and provider='railway'
    and lifecycle='active';

  if v_target.target_id is null then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','release-source-target-invalid',
      'targetId',p_target_id
    );
  end if;

  if p_repository !~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
     or p_branch is null
     or length(p_branch) not between 1 and 200
     or p_branch ~ '[[:cntrl:]]'
     or p_head_sha !~ '^[a-fA-F0-9]{40}$'
     or p_valid_until<=p_observed_at
     or p_evidence_ref is null
     or char_length(p_evidence_ref)>1024
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-release-source-head' using errcode='22023';
  end if;

  if lower(p_repository)<>lower(v_target.metadata->>'sourceRepository')
     or p_branch<>v_target.metadata->>'sourceBranch' then
    return jsonb_build_object(
      'status','rejected',
      'reasonCode','release-source-identity-mismatch',
      'targetId',p_target_id
    );
  end if;

  insert into foundation.defence_release_source_head_observations(
    target_id,repository,branch,head_sha,head_committed_at,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    p_target_id,p_repository,p_branch,lower(p_head_sha),p_head_committed_at,
    p_observed_at,p_valid_until,p_evidence_ref,p_metadata
  )
  on conflict (evidence_ref) do nothing
  returning observation_id into v_id;

  return jsonb_build_object(
    'status',case when v_id is null then 'replayed' else 'recorded' end,
    'targetId',p_target_id,
    'headSha',lower(p_head_sha),
    'observationId',v_id,
    'validUntil',p_valid_until
  );
end;
$$;

revoke all on function foundation.record_defence_release_source_head_v1(
  text,text,text,text,timestamptz,timestamptz,timestamptz,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_release_source_head_v1(
  text,text,text,text,timestamptz,timestamptz,timestamptz,text,jsonb
) to service_role;


alter table foundation.defence_estate_incident_events
  drop constraint if exists defence_estate_incident_events_reason_code_check;

alter table foundation.defence_estate_incident_events
  add constraint defence_estate_incident_events_reason_code_check
  check (reason_code in (
    'healthy',
    'missing-observation',
    'stale-observation',
    'runtime-failure',
    'unexpected-runtime-state',
    'health-coverage-missing',
    'health-degraded',
    'health-unhealthy',
    'health-observation-missing',
    'health-observation-stale',
    'runtime-provenance-coverage-missing',
    'runtime-provenance-missing',
    'runtime-provenance-stale',
    'supabase-runtime-receipt-coverage-missing',
    'supabase-runtime-receipt-missing',
    'supabase-runtime-receipt-stale',
    'supabase-runtime-receipt-database-unhealthy',
    'serving-deployment-crashed',
    'release-attempt-failed',
    'release-transition-stuck',
    'successful-release-not-serving',
    'release-source-watch-missing',
    'release-source-watch-stale',
    'release-source-head-not-serving'
  ));


create or replace function foundation.get_defence_release_source_head_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_required integer := 0;
  v_fresh integer := 0;
  v_missing integer := 0;
  v_stale integer := 0;
  v_ahead integer := 0;
  v_overdue integer := 0;
  v_state text;
  v_attention jsonb := '[]'::jsonb;
begin
  with x as (
    select
      t.target_id,
      t.metadata,
      h.observation_id,
      h.repository,
      h.branch,
      h.head_sha,
      h.head_committed_at,
      h.observed_at,
      h.valid_until,
      rp.commit_sha as serving_commit_sha,
      tr.transition_state,
      tr.commit_sha as transition_commit_sha,
      tr.occurred_at as transition_occurred_at,
      case
        when t.metadata ? 'sourceHeadWatchEffectiveAt'
          then (t.metadata->>'sourceHeadWatchEffectiveAt')::timestamptz
        else t.updated_at
      end as effective_at
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_source_heads h using(target_id)
    left join foundation.current_defence_runtime_provenance rp using(target_id)
    left join foundation.current_defence_railway_transition tr using(target_id)
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select
    count(*),
    count(*) filter (where observation_id is not null and valid_until>now()),
    count(*) filter (
      where observation_id is null
        and now()>effective_at+interval '20 minutes'
    ),
    count(*) filter (
      where observation_id is not null
        and valid_until<=now()
        and now()>effective_at+interval '20 minutes'
    ),
    count(*) filter (
      where observation_id is not null
        and valid_until>now()
        and serving_commit_sha is not null
        and head_sha<>serving_commit_sha
    ),
    count(*) filter (
      where observation_id is not null
        and valid_until>now()
        and serving_commit_sha is not null
        and head_sha<>serving_commit_sha
        and head_committed_at<=now()-interval '30 minutes'
        and not coalesce(
          transition_commit_sha=head_sha
          and transition_state in (
            'waiting','needs_approval','queued','initializing','building','deploying'
          )
          and transition_occurred_at>now()-interval '30 minutes',
          false
        )
    )
  into v_required,v_fresh,v_missing,v_stale,v_ahead,v_overdue
  from x;

  with x as (
    select
      t.target_id,
      t.metadata,
      h.observation_id,
      h.repository,
      h.branch,
      h.head_sha,
      h.head_committed_at,
      h.observed_at,
      h.valid_until,
      rp.commit_sha as serving_commit_sha,
      tr.transition_state,
      tr.commit_sha as transition_commit_sha,
      tr.occurred_at as transition_occurred_at,
      case
        when t.metadata ? 'sourceHeadWatchEffectiveAt'
          then (t.metadata->>'sourceHeadWatchEffectiveAt')::timestamptz
        else t.updated_at
      end as effective_at
    from foundation.defence_estate_targets t
    left join foundation.current_defence_release_source_heads h using(target_id)
    left join foundation.current_defence_runtime_provenance rp using(target_id)
    left join foundation.current_defence_railway_transition tr using(target_id)
    where t.provider='railway'
      and t.lifecycle='active'
      and t.required_for_estate
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'targetId',target_id,
      'repository',repository,
      'branch',branch,
      'headSha',head_sha,
      'servingCommitSha',serving_commit_sha,
      'headCommittedAt',head_committed_at,
      'observedAt',observed_at,
      'validUntil',valid_until,
      'transitionState',transition_state,
      'reasonCode',case
        when observation_id is null
          and now()>effective_at+interval '20 minutes'
          then 'release-source-watch-missing'
        when observation_id is not null
          and valid_until<=now()
          and now()>effective_at+interval '20 minutes'
          then 'release-source-watch-stale'
        when observation_id is not null
          and valid_until>now()
          and serving_commit_sha is not null
          and head_sha<>serving_commit_sha
          and head_committed_at<=now()-interval '30 minutes'
          and not coalesce(
            transition_commit_sha=head_sha
            and transition_state in (
              'waiting','needs_approval','queued','initializing','building','deploying'
            )
            and transition_occurred_at>now()-interval '30 minutes',
            false
          )
          then 'release-source-head-not-serving'
        else 'source-ahead-within-grace'
      end
    ) order by target_id
  ),'[]'::jsonb)
  into v_attention
  from x
  where
    (
      observation_id is null
      and now()>effective_at+interval '20 minutes'
    )
    or (
      observation_id is not null
      and valid_until<=now()
      and now()>effective_at+interval '20 minutes'
    )
    or (
      observation_id is not null
      and valid_until>now()
      and serving_commit_sha is not null
      and head_sha<>serving_commit_sha
      and head_committed_at<=now()-interval '30 minutes'
      and not coalesce(
        transition_commit_sha=head_sha
        and transition_state in (
          'waiting','needs_approval','queued','initializing','building','deploying'
        )
        and transition_occurred_at>now()-interval '30 minutes',
        false
      )
    );

  v_state := case
    when v_missing>0 or v_stale>0 or v_overdue>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceReleaseSourceHeadSummary','shine-defence/release-source-head-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'requiredTargets',v_required,
    'freshTargets',v_fresh,
    'missingTargets',v_missing,
    'staleTargets',v_stale,
    'sourceAheadTargets',v_ahead,
    'overdueNotServingTargets',v_overdue,
    'attention',v_attention,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_release_source_head_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_release_source_head_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;


create or replace function foundation.run_defence_release_source_head_sentinel_v1(
  p_observed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_head foundation.defence_release_source_head_observations%rowtype;
  v_provenance foundation.defence_runtime_provenance_observations%rowtype;
  v_transition foundation.defence_railway_transition_events%rowtype;
  v_prior foundation.defence_estate_incident_events%rowtype;
  v_effective_at timestamptz;
  v_state text;
  v_reason text;
  v_event_type text;
  v_incident_key text;
  v_created integer := 0;
  v_active integer := 0;
begin
  for v_target in
    select *
    from foundation.defence_estate_targets
    where provider='railway'
      and lifecycle='active'
      and required_for_estate
    order by target_id
  loop
    v_head := null;
    v_provenance := null;
    v_transition := null;

    select h.* into v_head
    from foundation.defence_release_source_head_observations h
    where h.target_id=v_target.target_id
      and h.observed_at<=p_observed_at
    order by h.observed_at desc,h.recorded_at desc,h.observation_id desc
    limit 1;

    select rp.* into v_provenance
    from foundation.defence_runtime_provenance_observations rp
    where rp.target_id=v_target.target_id
      and rp.observed_at<=p_observed_at
    order by rp.observed_at desc,rp.recorded_at desc,rp.observation_id desc
    limit 1;

    select tr.* into v_transition
    from foundation.defence_railway_transition_events tr
    where tr.target_id=v_target.target_id
      and tr.occurred_at<=p_observed_at
    order by tr.occurred_at desc,tr.recorded_at desc,tr.event_id desc
    limit 1;

    v_effective_at := case
      when v_target.metadata ? 'sourceHeadWatchEffectiveAt'
        then (v_target.metadata->>'sourceHeadWatchEffectiveAt')::timestamptz
      else v_target.updated_at
    end;

    if v_head.observation_id is null
      and p_observed_at>v_effective_at+interval '20 minutes' then
      v_state := 'warning';
      v_reason := 'release-source-watch-missing';
    elsif v_head.observation_id is not null
      and v_head.valid_until<=p_observed_at
      and p_observed_at>v_effective_at+interval '20 minutes' then
      v_state := 'warning';
      v_reason := 'release-source-watch-stale';
    elsif v_head.observation_id is not null
      and v_head.valid_until>p_observed_at
      and v_provenance.observation_id is not null
      and v_head.head_sha<>v_provenance.commit_sha
      and v_head.head_committed_at<=p_observed_at-interval '30 minutes'
      and not coalesce(
        v_transition.event_id is not null
        and v_transition.commit_sha=v_head.head_sha
        and v_transition.transition_state in (
          'waiting','needs_approval','queued','initializing','building','deploying'
        )
        and v_transition.occurred_at>p_observed_at-interval '30 minutes',
        false
      ) then
      v_state := 'warning';
      v_reason := 'release-source-head-not-serving';
    else
      v_state := 'pass';
      v_reason := 'healthy';
    end if;

    v_incident_key := v_target.target_id||':release-source-head';
    v_prior := null;

    select i.* into v_prior
    from foundation.defence_estate_incident_events i
    where i.incident_key=v_incident_key
    order by i.occurred_at desc,i.recorded_at desc,i.event_id desc
    limit 1;

    v_event_type := null;
    if v_state='warning' then
      if v_prior.event_id is null or v_prior.event_type='recovered' then
        v_event_type := 'opened';
      elsif v_prior.reason_code is distinct from v_reason then
        v_event_type := 'changed';
      end if;
    elsif v_prior.event_id is not null and v_prior.event_type<>'recovered' then
      v_event_type := 'recovered';
    end if;

    if v_event_type is not null then
      insert into foundation.defence_estate_incident_events(
        incident_key,target_id,event_type,state,reason_code,
        observation_id,health_observation_id,occurred_at,evidence_ref
      ) values (
        v_incident_key,v_target.target_id,v_event_type,v_state,v_reason,
        null,null,p_observed_at,
        'sentinel:shine-defence:release-source-head:v1'
      );
      v_created := v_created+1;
    end if;
  end loop;

  select count(*) into v_active
  from foundation.current_defence_estate_incidents
  where incident_key like 'railway:%:release-source-head';

  return jsonb_build_object(
    'defenceReleaseSourceHeadSentinel','shine-defence/release-source-head-sentinel-v1',
    'schemaVersion','1.0.0',
    'observedAt',p_observed_at,
    'incidentEventsCreated',v_created,
    'activeIncidentCount',v_active,
    'summary',foundation.get_defence_release_source_head_summary_v1()
  );
end;
$$;

revoke all on function foundation.run_defence_release_source_head_sentinel_v1(timestamptz)
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.run_defence_release_source_head_sentinel_v1(timestamptz)
  to shine_defence_runtime,service_role;


create or replace function foundation.get_defence_full_estate_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_estate jsonb;
  v_supabase jsonb;
  v_transitions jsonb;
  v_source_heads jsonb;
  v_state text;
begin
  v_estate := foundation.get_defence_estate_summary_v1();
  v_supabase := foundation.get_defence_supabase_runtime_receipt_summary_v1();
  v_transitions := foundation.get_defence_railway_transition_summary_v1();
  v_source_heads := foundation.get_defence_release_source_head_summary_v1();

  v_state := case
    when v_estate->>'state'='fail'
      or v_supabase->>'state'='fail'
      or v_transitions->>'state'='fail'
      then 'fail'
    when v_estate->>'state'='warning'
      or v_supabase->>'state'='warning'
      or v_transitions->>'state'='warning'
      or v_source_heads->>'state'='warning'
      then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceFullEstateSummary','shine-defence/full-estate-summary-v1',
    'schemaVersion','1.2.0',
    'state',v_state,
    'estate',v_estate,
    'supabaseRuntimeReceipts',v_supabase,
    'railwayReleaseTransitions',v_transitions,
    'releaseSourceHeads',v_source_heads,
    'evaluatedAt',now()
  );
end;
$$;
