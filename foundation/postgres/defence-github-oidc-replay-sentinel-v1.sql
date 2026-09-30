-- Shine Defence GitHub OIDC replay Sentinel v1.
-- Durable escalation for changed-payload reuse of one verified GitHub OIDC
-- operation identity. Exact retries remain audit-only.

create table foundation.github_oidc_replay_alert_events (
  alert_sequence bigint generated always as identity primary key,
  alert_id uuid not null unique default gen_random_uuid(),
  replay_event_sequence bigint not null unique
    references foundation.github_oidc_operation_events(event_sequence),
  binding_id uuid not null
    references foundation.github_oidc_operation_bindings(binding_id),
  repository text not null,
  run_id text not null,
  run_attempt text not null,
  audience text not null,
  operation text not null,
  target_key text not null,
  original_request_sha256 text not null
    check (original_request_sha256 ~ '^[a-f0-9]{64}$'),
  presented_request_sha256 text not null
    check (presented_request_sha256 ~ '^[a-f0-9]{64}$'),
  severity text not null default 'fail'
    check (severity='fail'),
  observed_at timestamptz not null,
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  recorded_at timestamptz not null default clock_timestamp()
);

alter table foundation.github_oidc_replay_alert_events enable row level security;

revoke all on foundation.github_oidc_replay_alert_events
  from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant select on foundation.github_oidc_replay_alert_events
  to shine_defence_runtime,service_role;

create index github_oidc_replay_alert_events_time_idx
  on foundation.github_oidc_replay_alert_events(observed_at desc,alert_sequence desc);

create index github_oidc_replay_alert_events_target_idx
  on foundation.github_oidc_replay_alert_events(target_key,observed_at desc);

create trigger github_oidc_replay_alert_events_append_only
before update or delete on foundation.github_oidc_replay_alert_events
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.escalate_github_oidc_replay_conflict_v1()
returns trigger
language plpgsql
security definer
set search_path = ''
as $replay_alert$
declare
  v_binding foundation.github_oidc_operation_bindings%rowtype;
begin
  if new.outcome<>'rejected-conflict' then
    return new;
  end if;

  select * into v_binding
  from foundation.github_oidc_operation_bindings
  where binding_id=new.binding_id;

  if v_binding.binding_id is null then
    raise exception 'github-oidc-replay-binding-missing'
      using errcode='23503';
  end if;

  insert into foundation.github_oidc_replay_alert_events(
    replay_event_sequence,binding_id,repository,run_id,run_attempt,
    audience,operation,target_key,original_request_sha256,
    presented_request_sha256,severity,observed_at,evidence_ref,metadata
  ) values (
    new.event_sequence,
    v_binding.binding_id,
    v_binding.repository,
    v_binding.run_id,
    v_binding.run_attempt,
    v_binding.audience,
    v_binding.operation,
    v_binding.target_key,
    v_binding.request_sha256,
    new.presented_sha256,
    'fail',
    new.observed_at,
    'github-oidc-replay-conflict:'||new.event_id::text,
    jsonb_build_object(
      'replayEventId',new.event_id,
      'ref',v_binding.ref,
      'workflowRef',v_binding.workflow_ref,
      'eventName',v_binding.event_name
    )
  )
  on conflict (replay_event_sequence) do nothing;

  return new;
end;
$replay_alert$;

drop trigger if exists github_oidc_operation_events_replay_sentinel
  on foundation.github_oidc_operation_events;

create trigger github_oidc_operation_events_replay_sentinel
after insert on foundation.github_oidc_operation_events
for each row execute function foundation.escalate_github_oidc_replay_conflict_v1();


-- Backfill any conflicts that arrived between replay-guard installation and
-- Sentinel installation.
insert into foundation.github_oidc_replay_alert_events(
  replay_event_sequence,binding_id,repository,run_id,run_attempt,
  audience,operation,target_key,original_request_sha256,
  presented_request_sha256,severity,observed_at,evidence_ref,metadata
)
select
  e.event_sequence,
  b.binding_id,
  b.repository,
  b.run_id,
  b.run_attempt,
  b.audience,
  b.operation,
  b.target_key,
  b.request_sha256,
  e.presented_sha256,
  'fail',
  e.observed_at,
  'github-oidc-replay-conflict:'||e.event_id::text,
  jsonb_build_object(
    'replayEventId',e.event_id,
    'ref',b.ref,
    'workflowRef',b.workflow_ref,
    'eventName',b.event_name
  )
from foundation.github_oidc_operation_events e
join foundation.github_oidc_operation_bindings b using(binding_id)
where e.outcome='rejected-conflict'
on conflict (replay_event_sequence) do nothing;


create or replace function foundation.get_defence_github_oidc_replay_summary_v1(
  p_as_of timestamptz default now(),
  p_window_seconds integer default 86400
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $replay_summary$
declare
  v_window_start timestamptz;
  v_bindings bigint := 0;
  v_accepted bigint := 0;
  v_exact bigint := 0;
  v_recent_conflicts bigint := 0;
  v_historical_conflicts bigint := 0;
  v_latest_conflict timestamptz;
  v_attention jsonb := '[]'::jsonb;
  v_state text;
begin
  if p_as_of is null
     or p_window_seconds<300
     or p_window_seconds>604800 then
    raise exception 'github-oidc-replay-summary-window-invalid'
      using errcode='22023';
  end if;

  v_window_start := p_as_of-make_interval(secs=>p_window_seconds);

  select count(*) into v_bindings
  from foundation.github_oidc_operation_bindings
  where bound_at<=p_as_of;

  select
    count(*) filter (
      where e.outcome='accepted-new'
        and e.observed_at>v_window_start
        and e.observed_at<=p_as_of
    ),
    count(*) filter (
      where e.outcome='replayed-exact'
        and e.observed_at>v_window_start
        and e.observed_at<=p_as_of
    )
  into v_accepted,v_exact
  from foundation.github_oidc_operation_events e;

  select
    count(*) filter (
      where a.observed_at>v_window_start
        and a.observed_at<=p_as_of
    ),
    count(*) filter (where a.observed_at<=p_as_of),
    max(a.observed_at) filter (where a.observed_at<=p_as_of)
  into v_recent_conflicts,v_historical_conflicts,v_latest_conflict
  from foundation.github_oidc_replay_alert_events a;

  select coalesce(jsonb_agg(item order by observed_at desc,alert_sequence desc),'[]'::jsonb)
  into v_attention
  from (
    select
      a.observed_at,
      a.alert_sequence,
      jsonb_build_object(
        'alertId',a.alert_id,
        'repository',a.repository,
        'runId',a.run_id,
        'runAttempt',a.run_attempt,
        'audience',a.audience,
        'operation',a.operation,
        'targetKey',a.target_key,
        'originalRequestSha256',a.original_request_sha256,
        'presentedRequestSha256',a.presented_request_sha256,
        'observedAt',a.observed_at,
        'evidenceRef',a.evidence_ref
      ) as item
    from foundation.github_oidc_replay_alert_events a
    where a.observed_at>v_window_start
      and a.observed_at<=p_as_of
    order by a.observed_at desc,a.alert_sequence desc
    limit 20
  ) recent;

  v_state := case when v_recent_conflicts>0 then 'fail' else 'pass' end;

  return jsonb_build_object(
    'defenceGithubOidcReplaySummary','shine-defence/github-oidc-replay-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'reasonCode',case
      when v_state='fail' then 'github-oidc-replay-conflict'
      else 'healthy'
    end,
    'windowSeconds',p_window_seconds,
    'windowStartedAt',v_window_start,
    'asOf',p_as_of,
    'bindingCount',v_bindings,
    'acceptedNewInWindow',v_accepted,
    'exactReplaysInWindow',v_exact,
    'conflictsInWindow',v_recent_conflicts,
    'historicalConflictCount',v_historical_conflicts,
    'latestConflictAt',v_latest_conflict,
    'attention',v_attention
  );
end;
$replay_summary$;

revoke all on function foundation.get_defence_github_oidc_replay_summary_v1(
  timestamptz,integer
) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_defence_github_oidc_replay_summary_v1(
  timestamptz,integer
) to foundation_runtime,shine_defence_runtime,service_role;


-- Full-estate integration: a current changed-payload replay conflict is a
-- control-plane FAIL, independent of app/runtime health.
create or replace function foundation.get_defence_full_estate_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $full_estate_replay$
declare
  v_estate jsonb;
  v_supabase jsonb;
  v_transitions jsonb;
  v_source_heads jsonb;
  v_transition_coverage jsonb;
  v_admission jsonb;
  v_rollback jsonb;
  v_ladder jsonb;
  v_oidc_replay jsonb;
  v_state text;
begin
  v_estate := foundation.get_defence_estate_summary_v1();
  v_supabase := foundation.get_defence_supabase_runtime_receipt_summary_v1();
  v_transitions := foundation.get_defence_railway_transition_summary_v1();
  v_source_heads := foundation.get_defence_release_source_head_summary_v1();
  v_transition_coverage := foundation.get_defence_release_transition_coverage_v1();
  v_admission := foundation.get_defence_release_admission_summary_v1();
  v_rollback := foundation.get_defence_rollback_readiness_summary_v1();
  v_ladder := foundation.get_defence_rollback_ladder_v1();
  v_oidc_replay := foundation.get_defence_github_oidc_replay_summary_v1(now(),86400);

  v_state := case
    when v_oidc_replay->>'state'='fail'
      or v_estate->>'state'='fail'
      or v_supabase->>'state'='fail'
      or v_transitions->>'state'='fail'
      then 'fail'
    when v_estate->>'state'='warning'
      or v_supabase->>'state'='warning'
      or v_transitions->>'state'='warning'
      or v_source_heads->>'state'='warning'
      or v_transition_coverage->>'state'='warning'
      or v_admission->>'state'='warning'
      or v_rollback->>'state'='warning'
      or v_ladder->>'state'='warning'
      then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceFullEstateSummary','shine-defence/full-estate-summary-v1',
    'schemaVersion','1.7.0',
    'state',v_state,
    'estate',v_estate,
    'supabaseRuntimeReceipts',v_supabase,
    'railwayReleaseTransitions',v_transitions,
    'releaseSourceHeads',v_source_heads,
    'releaseTransitionCoverage',v_transition_coverage,
    'releaseAdmission',v_admission,
    'rollbackReadiness',v_rollback,
    'rollbackLadder',v_ladder,
    'githubOidcReplay',v_oidc_replay,
    'evaluatedAt',now()
  );
end;
$full_estate_replay$;

revoke all on function foundation.get_defence_full_estate_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_full_estate_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;
