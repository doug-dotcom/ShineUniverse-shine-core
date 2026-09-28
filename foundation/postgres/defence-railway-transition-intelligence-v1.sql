-- Shine Defence Railway release-transition intelligence v1.
-- Railway project webhooks are best-effort and unsigned. Events are advisory
-- transition evidence only; serving-runtime provenance remains authoritative.

create table foundation.defence_railway_transition_events (
  event_id uuid primary key default gen_random_uuid(),
  target_id text not null references foundation.defence_estate_targets(target_id),
  project_id uuid not null,
  environment_id uuid not null,
  service_id uuid not null,
  deployment_id uuid not null,
  event_type text not null
    check (event_type ~ '^Deployment\.[A-Za-z0-9_-]+$'),
  transition_state text not null
    check (transition_state in (
      'waiting','needs_approval','queued','initializing','skipped',
      'building','deploying','success','failed','removed','crashed',
      'removing','sleeping','unknown'
    )),
  severity text
    check (severity is null or severity in ('INFO','WARNING','ERROR','CRITICAL')),
  source_kind text,
  branch text,
  commit_sha text
    check (commit_sha is null or commit_sha ~ '^[a-fA-F0-9]{40}$'),
  occurred_at timestamptz not null,
  payload_sha256 text not null
    check (payload_sha256 ~ '^[a-fA-F0-9]{64}$'),
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.defence_railway_transition_events enable row level security;

create policy shine_defence_runtime_railway_transition_select
on foundation.defence_railway_transition_events
for select
to shine_defence_runtime
using (true);

revoke all on foundation.defence_railway_transition_events
  from public,anon,authenticated;
grant select on foundation.defence_railway_transition_events
  to shine_defence_runtime,service_role;
grant insert on foundation.defence_railway_transition_events
  to service_role;

create index defence_railway_transition_target_time_idx
  on foundation.defence_railway_transition_events(
    target_id,occurred_at desc,recorded_at desc
  );

create index defence_railway_transition_deployment_idx
  on foundation.defence_railway_transition_events(
    deployment_id,occurred_at desc
  );

create trigger defence_railway_transition_events_append_only
before update or delete on foundation.defence_railway_transition_events
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_defence_railway_transition
with (security_invoker=true)
as
select distinct on (target_id)
  event_id,target_id,project_id,environment_id,service_id,deployment_id,
  event_type,transition_state,severity,source_kind,branch,commit_sha,
  occurred_at,payload_sha256,evidence_ref,metadata,recorded_at
from foundation.defence_railway_transition_events
order by target_id,occurred_at desc,recorded_at desc,event_id desc;

revoke all on foundation.current_defence_railway_transition
  from public,anon,authenticated;
grant select on foundation.current_defence_railway_transition
  to shine_defence_runtime,service_role;


create or replace function foundation.record_defence_railway_transition_v1(
  p_project_id uuid,
  p_environment_id uuid,
  p_service_id uuid,
  p_deployment_id uuid,
  p_event_type text,
  p_transition_state text,
  p_severity text,
  p_source_kind text,
  p_branch text,
  p_commit_sha text,
  p_occurred_at timestamptz,
  p_payload_sha256 text,
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
  v_event_id uuid;
begin
  if p_event_type !~ '^Deployment\.[A-Za-z0-9_-]+$'
     or p_transition_state not in (
       'waiting','needs_approval','queued','initializing','skipped',
       'building','deploying','success','failed','removed','crashed',
       'removing','sleeping','unknown'
     )
     or (p_severity is not null and p_severity not in ('INFO','WARNING','ERROR','CRITICAL'))
     or (p_commit_sha is not null and p_commit_sha !~ '^[a-fA-F0-9]{40}$')
     or p_payload_sha256 !~ '^[a-fA-F0-9]{64}$'
     or p_evidence_ref is null
     or char_length(p_evidence_ref)>1024
     or p_metadata is null
     or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'invalid-railway-transition-event' using errcode='22023';
  end if;

  select * into v_target
  from foundation.defence_estate_targets
  where provider='railway'
    and lifecycle='active'
    and provider_project_ref=p_project_id::text
    and environment_ref=p_environment_id::text
    and service_ref=p_service_id::text;

  if v_target.target_id is null then
    return jsonb_build_object(
      'status','ignored',
      'reasonCode','unregistered-railway-target'
    );
  end if;

  insert into foundation.defence_railway_transition_events(
    target_id,project_id,environment_id,service_id,deployment_id,
    event_type,transition_state,severity,source_kind,branch,commit_sha,
    occurred_at,payload_sha256,evidence_ref,metadata
  ) values (
    v_target.target_id,p_project_id,p_environment_id,p_service_id,p_deployment_id,
    p_event_type,p_transition_state,p_severity,p_source_kind,p_branch,
    case when p_commit_sha is null then null else lower(p_commit_sha) end,
    p_occurred_at,lower(p_payload_sha256),p_evidence_ref,p_metadata
  )
  on conflict (evidence_ref) do nothing
  returning event_id into v_event_id;

  return jsonb_build_object(
    'status',case when v_event_id is null then 'replayed' else 'recorded' end,
    'targetId',v_target.target_id,
    'eventId',v_event_id,
    'transitionState',p_transition_state,
    'deploymentId',p_deployment_id
  );
end;
$$;

revoke all on function foundation.record_defence_railway_transition_v1(
  uuid,uuid,uuid,uuid,text,text,text,text,text,text,timestamptz,text,text,jsonb
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.record_defence_railway_transition_v1(
  uuid,uuid,uuid,uuid,text,text,text,text,text,text,timestamptz,text,text,jsonb
) to service_role;


create or replace function foundation.get_defence_railway_transition_summary_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $$
declare
  v_failed_attempts integer := 0;
  v_crashed_serving integer := 0;
  v_inflight integer := 0;
  v_stuck integer := 0;
  v_pending_success integer := 0;
  v_state text;
  v_attention jsonb := '[]'::jsonb;
begin
  with latest as (
    select
      t.target_id,
      t.deployment_id,
      t.transition_state,
      t.commit_sha,
      t.occurred_at,
      rp.deployment_id as serving_deployment_id,
      rp.commit_sha as serving_commit_sha,
      rp.valid_until as serving_valid_until
    from foundation.current_defence_railway_transition t
    left join foundation.current_defence_runtime_provenance rp using(target_id)
  )
  select
    count(*) filter (
      where transition_state='failed'
        and deployment_id::text is distinct from serving_deployment_id
    ),
    count(*) filter (
      where transition_state='crashed'
        and deployment_id::text = serving_deployment_id
    ),
    count(*) filter (
      where transition_state in (
        'waiting','needs_approval','queued','initializing','building','deploying'
      )
        and occurred_at>now()-interval '20 minutes'
    ),
    count(*) filter (
      where transition_state in (
        'waiting','needs_approval','queued','initializing','building','deploying'
      )
        and occurred_at<=now()-interval '20 minutes'
    ),
    count(*) filter (
      where transition_state='success'
        and deployment_id::text is distinct from serving_deployment_id
        and occurred_at<=now()-interval '10 minutes'
    )
  into
    v_failed_attempts,v_crashed_serving,v_inflight,v_stuck,v_pending_success
  from latest;

  with latest as (
    select
      t.target_id,
      t.deployment_id,
      t.transition_state,
      t.commit_sha,
      t.occurred_at,
      rp.deployment_id as serving_deployment_id,
      rp.commit_sha as serving_commit_sha,
      rp.valid_until as serving_valid_until
    from foundation.current_defence_railway_transition t
    left join foundation.current_defence_runtime_provenance rp using(target_id)
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'targetId',target_id,
      'deploymentId',deployment_id,
      'transitionState',transition_state,
      'commitSha',commit_sha,
      'occurredAt',occurred_at,
      'servingDeploymentId',serving_deployment_id,
      'servingCommitSha',serving_commit_sha,
      'reasonCode',case
        when transition_state='crashed'
          and deployment_id::text=serving_deployment_id
          then 'serving-deployment-crashed'
        when transition_state='failed'
          and deployment_id::text is distinct from serving_deployment_id
          then 'release-attempt-failed'
        when transition_state in (
          'waiting','needs_approval','queued','initializing','building','deploying'
        )
          and occurred_at<=now()-interval '20 minutes'
          then 'release-transition-stuck'
        when transition_state='success'
          and deployment_id::text is distinct from serving_deployment_id
          and occurred_at<=now()-interval '10 minutes'
          then 'successful-release-not-serving'
        else 'transitioning'
      end
    ) order by occurred_at desc
  ),'[]'::jsonb)
  into v_attention
  from latest
  where
    (
      transition_state='crashed'
      and deployment_id::text=serving_deployment_id
    )
    or (
      transition_state='failed'
      and deployment_id::text is distinct from serving_deployment_id
    )
    or (
      transition_state in (
        'waiting','needs_approval','queued','initializing','building','deploying'
      )
      and occurred_at<=now()-interval '20 minutes'
    )
    or (
      transition_state='success'
      and deployment_id::text is distinct from serving_deployment_id
      and occurred_at<=now()-interval '10 minutes'
    );

  v_state := case
    when v_crashed_serving>0 then 'fail'
    when v_failed_attempts>0 or v_stuck>0 or v_pending_success>0 then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceRailwayTransitionSummary','shine-defence/railway-transition-summary-v1',
    'schemaVersion','1.0.0',
    'state',v_state,
    'failedNonServingAttempts',v_failed_attempts,
    'crashedServingDeployments',v_crashed_serving,
    'inFlightDeployments',v_inflight,
    'stuckTransitions',v_stuck,
    'successfulNotServing',v_pending_success,
    'attention',v_attention,
    'evaluatedAt',now()
  );
end;
$$;

revoke all on function foundation.get_defence_railway_transition_summary_v1()
  from public,anon,authenticated;
grant execute on function foundation.get_defence_railway_transition_summary_v1()
  to foundation_runtime,shine_defence_runtime,service_role;


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
  v_state text;
begin
  v_estate := foundation.get_defence_estate_summary_v1();
  v_supabase := foundation.get_defence_supabase_runtime_receipt_summary_v1();
  v_transitions := foundation.get_defence_railway_transition_summary_v1();

  v_state := case
    when v_estate->>'state'='fail'
      or v_supabase->>'state'='fail'
      or v_transitions->>'state'='fail'
      then 'fail'
    when v_estate->>'state'='warning'
      or v_supabase->>'state'='warning'
      or v_transitions->>'state'='warning'
      then 'warning'
    else 'pass'
  end;

  return jsonb_build_object(
    'defenceFullEstateSummary','shine-defence/full-estate-summary-v1',
    'schemaVersion','1.1.0',
    'state',v_state,
    'estate',v_estate,
    'supabaseRuntimeReceipts',v_supabase,
    'railwayReleaseTransitions',v_transitions,
    'evaluatedAt',now()
  );
end;
$$;
