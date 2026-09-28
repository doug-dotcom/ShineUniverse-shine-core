-- Foundation Layer 23: automatic health collector core.
-- Portable persistence and aggregation. Hosted pg_net/pg_cron wiring lives separately.

create table foundation.service_health_probe_targets (
  target_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  target_version text not null,
  target_url text not null
    check (target_url ~ '^https://'),
  expected_service text not null,
  expected_status text not null default 'ok',
  expected_schema_version text not null default '1.0.0',
  timeout_milliseconds integer not null default 10000
    check (timeout_milliseconds between 1000 and 30000),
  enabled boolean not null default true,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  unique(service_id,environment,target_version)
);

alter table foundation.service_health_probe_targets enable row level security;

create policy foundation_runtime_service_health_probe_targets_select
on foundation.service_health_probe_targets
for select
to foundation_runtime
using (true);

revoke all on foundation.service_health_probe_targets from public,anon,authenticated;
grant select on foundation.service_health_probe_targets to foundation_runtime;
grant select,insert on foundation.service_health_probe_targets to service_role;

create index service_health_probe_targets_current_idx
  on foundation.service_health_probe_targets(service_id,environment,effective_at desc,recorded_at desc);

create trigger service_health_probe_targets_append_only
before update or delete on foundation.service_health_probe_targets
for each row execute function foundation.reject_append_only_mutation();


create table foundation.service_health_probe_requests (
  probe_request_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null,
  target_id uuid not null references foundation.service_health_probe_targets(target_id),
  external_request_id bigint,
  target_url text not null,
  queued_at timestamptz not null default now(),
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  unique(external_request_id),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.service_health_probe_requests enable row level security;

create policy foundation_runtime_service_health_probe_requests_select
on foundation.service_health_probe_requests
for select
to foundation_runtime
using (true);

revoke all on foundation.service_health_probe_requests from public,anon,authenticated;
grant select on foundation.service_health_probe_requests to foundation_runtime;
grant select,insert on foundation.service_health_probe_requests to service_role;

create index service_health_probe_requests_pending_idx
  on foundation.service_health_probe_requests(queued_at,external_request_id)
  where external_request_id is not null;

create index service_health_probe_requests_service_idx
  on foundation.service_health_probe_requests(service_id,environment,queued_at desc);

create index service_health_probe_requests_target_idx
  on foundation.service_health_probe_requests(target_id);

create trigger service_health_probe_requests_append_only
before update or delete on foundation.service_health_probe_requests
for each row execute function foundation.reject_append_only_mutation();


create table foundation.service_health_probe_results (
  result_sequence bigint generated always as identity primary key,
  probe_result_id uuid not null unique default gen_random_uuid(),
  probe_request_id uuid not null unique references foundation.service_health_probe_requests(probe_request_id),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null,
  http_status integer,
  timed_out boolean not null default false,
  error_message text,
  contract_ok boolean not null default false,
  response_at timestamptz not null,
  roundtrip_ms numeric(12,3)
    check (roundtrip_ms is null or roundtrip_ms >= 0),
  response_sha256 text
    check (response_sha256 is null or response_sha256 ~ '^[a-fA-F0-9]{64}$'),
  evidence_ref text not null unique,
  metadata jsonb not null default '{}'::jsonb,
  recorded_at timestamptz not null default now(),
  check (http_status is null or http_status between 100 and 599),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.service_health_probe_results enable row level security;

create policy foundation_runtime_service_health_probe_results_select
on foundation.service_health_probe_results
for select
to foundation_runtime
using (true);

revoke all on foundation.service_health_probe_results from public,anon,authenticated;
grant select on foundation.service_health_probe_results to foundation_runtime;
grant select,insert on foundation.service_health_probe_results to service_role;

create index service_health_probe_results_window_idx
  on foundation.service_health_probe_results(service_id,environment,response_at desc,result_sequence desc);

create trigger service_health_probe_results_append_only
before update or delete on foundation.service_health_probe_results
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_service_health_probe_target
with (security_invoker=true)
as
select distinct on (service_id,environment)
  target_id,
  service_id,
  environment,
  target_version,
  target_url,
  expected_service,
  expected_status,
  expected_schema_version,
  timeout_milliseconds,
  enabled,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.service_health_probe_targets
order by service_id,environment,effective_at desc,recorded_at desc,target_id desc;

revoke all on foundation.current_service_health_probe_target from public,anon,authenticated;
grant select on foundation.current_service_health_probe_target to foundation_runtime;


create or replace function foundation.record_service_health_probe_request_v1(
  p_service_id text,
  p_environment text,
  p_target_id uuid,
  p_external_request_id bigint,
  p_target_url text,
  p_queued_at timestamptz,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_id uuid;
begin
  insert into foundation.service_health_probe_requests(
    service_id,environment,target_id,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  )
  values (
    p_service_id,p_environment,p_target_id,p_external_request_id,p_target_url,
    p_queued_at,p_evidence_ref,coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (evidence_ref) do nothing
  returning probe_request_id into v_id;

  if v_id is null then
    select probe_request_id into v_id
    from foundation.service_health_probe_requests
    where evidence_ref=p_evidence_ref;
  end if;

  return v_id;
end;
$$;

revoke all on function foundation.record_service_health_probe_request_v1(text,text,uuid,bigint,text,timestamptz,text,jsonb)
  from public,anon,authenticated,foundation_runtime;
grant execute on function foundation.record_service_health_probe_request_v1(text,text,uuid,bigint,text,timestamptz,text,jsonb)
  to service_role;


create or replace function foundation.record_service_health_probe_result_v1(
  p_probe_request_id uuid,
  p_http_status integer,
  p_timed_out boolean,
  p_error_message text,
  p_contract_ok boolean,
  p_response_at timestamptz,
  p_roundtrip_ms numeric,
  p_response_sha256 text,
  p_evidence_ref text,
  p_metadata jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_sequence bigint;
  v_request foundation.service_health_probe_requests%rowtype;
begin
  select *
    into v_request
  from foundation.service_health_probe_requests
  where probe_request_id=p_probe_request_id;

  if v_request.probe_request_id is null then
    raise exception 'unknown health probe request';
  end if;

  insert into foundation.service_health_probe_results(
    probe_request_id,service_id,environment,http_status,timed_out,error_message,
    contract_ok,response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  )
  values (
    p_probe_request_id,v_request.service_id,v_request.environment,p_http_status,
    coalesce(p_timed_out,false),p_error_message,coalesce(p_contract_ok,false),
    p_response_at,p_roundtrip_ms,p_response_sha256,p_evidence_ref,
    coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (probe_request_id) do nothing
  returning result_sequence into v_sequence;

  if v_sequence is null then
    select result_sequence into v_sequence
    from foundation.service_health_probe_results
    where probe_request_id=p_probe_request_id;
  end if;

  return v_sequence;
end;
$$;

revoke all on function foundation.record_service_health_probe_result_v1(uuid,integer,boolean,text,boolean,timestamptz,numeric,text,text,jsonb)
  from public,anon,authenticated,foundation_runtime;
grant execute on function foundation.record_service_health_probe_result_v1(uuid,integer,boolean,text,boolean,timestamptz,numeric,text,text,jsonb)
  to service_role;


create or replace function foundation.refresh_service_health_from_probes_v1(
  p_service_id text,
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_policy foundation.service_health_policies%rowtype;
  v_runtime_version text;
  v_deployment_observed_at timestamptz;
  v_window_floor timestamptz;
  v_window_start timestamptz;
  v_window_end timestamptz;
  v_request_count integer;
  v_4xx_count integer;
  v_5xx_count integer;
  v_avg_ms numeric;
  v_p95_ms numeric;
  v_runtime_error_count integer;
  v_latest_sequence bigint;
  v_evidence_ref text;
  v_inserted boolean := false;
begin
  select *
    into v_policy
  from foundation.current_service_health_policy
  where service_id=p_service_id
    and environment=p_environment;

  if v_policy.policy_id is null then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','missing-health-policy',
      'serviceId',p_service_id,
      'environment',p_environment
    );
  end if;

  select o.runtime_version,o.observed_at
    into v_runtime_version,v_deployment_observed_at
  from foundation.current_service_deployment_observations o
  where o.service_id=p_service_id
    and o.environment=p_environment;

  v_window_floor := greatest(
    p_as_of - make_interval(secs=>v_policy.evaluation_window_seconds),
    coalesce(v_deployment_observed_at,'-infinity'::timestamptz)
  );

  select
    min(r.response_at),
    max(r.response_at),
    count(*)::integer,
    count(*) filter (where r.http_status between 400 and 499)::integer,
    count(*) filter (where r.http_status between 500 and 599)::integer,
    round(avg(r.roundtrip_ms),3),
    round((percentile_cont(0.95) within group (order by r.roundtrip_ms))::numeric,3),
    count(*) filter (
      where r.timed_out
         or r.error_message is not null
         or r.http_status is null
         or r.http_status < 200
         or r.http_status >= 400
         or (r.http_status between 200 and 299 and not r.contract_ok)
    )::integer,
    max(r.result_sequence)
  into
    v_window_start,
    v_window_end,
    v_request_count,
    v_4xx_count,
    v_5xx_count,
    v_avg_ms,
    v_p95_ms,
    v_runtime_error_count,
    v_latest_sequence
  from foundation.service_health_probe_results r
  where r.service_id=p_service_id
    and r.environment=p_environment
    and r.response_at >= v_window_floor
    and r.response_at <= p_as_of;

  if coalesce(v_request_count,0)=0 then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','no-probe-results',
      'serviceId',p_service_id,
      'environment',p_environment
    );
  end if;

  v_evidence_ref := 'health-probe-window:' || p_service_id || ':' || p_environment || ':' ||
    coalesce(v_runtime_version,'unknown') || ':' || v_latest_sequence::text;

  insert into foundation.service_health_evidence(
    service_id,environment,runtime_version,window_started_at,window_ended_at,
    request_count,response_4xx_count,response_5xx_count,avg_latency_ms,p95_latency_ms,
    runtime_error_count,evidence_source,evidence_ref,evidence_note,metadata,observed_at
  )
  values (
    p_service_id,p_environment,v_runtime_version,v_window_start,v_window_end,
    v_request_count,v_4xx_count,v_5xx_count,v_avg_ms,v_p95_ms,
    v_runtime_error_count,'healthcheck',v_evidence_ref,
    'Automatically aggregated public health probes for the current health-policy evaluation window.',
    jsonb_build_object(
      'collector','shine-foundation/automatic-health-collector-v1',
      'latestProbeResultSequence',v_latest_sequence,
      'syntheticProbe',true,
      'deploymentObservedAt',v_deployment_observed_at,
      'windowFloor',v_window_floor
    ),
    p_as_of
  )
  on conflict (evidence_ref) do nothing;

  get diagnostics v_request_count = row_count;
  v_inserted := v_request_count > 0;

  return jsonb_build_object(
    'status',case when v_inserted then 'recorded' else 'already-recorded' end,
    'serviceId',p_service_id,
    'environment',p_environment,
    'evidenceRef',v_evidence_ref,
    'health',foundation.get_service_health_v1(p_service_id,p_environment)
  );
end;
$$;

revoke all on function foundation.refresh_service_health_from_probes_v1(text,text,timestamptz)
  from public,anon,authenticated,foundation_runtime;
grant execute on function foundation.refresh_service_health_from_probes_v1(text,text,timestamptz)
  to service_role;


insert into foundation.service_health_probe_targets(
  service_id,environment,target_version,target_url,
  expected_service,expected_status,expected_schema_version,
  timeout_milliseconds,enabled,effective_at,evidence_ref,evidence_note
)
select
  'foundation.gateway',
  'production',
  '1.0.0',
  'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/foundation-gateway/health',
  'shine-foundation-gateway',
  'ok',
  '1.0.0',
  10000,
  true,
  now(),
  'foundation:health-probe-target:gateway-production:v1',
  'Public Foundation Gateway health endpoint. No credential is required or stored.'
where not exists (
  select 1
  from foundation.service_health_probe_targets
  where service_id='foundation.gateway'
    and environment='production'
    and target_version='1.0.0'
);

insert into foundation.service_health_policies(
  service_id,environment,policy_version,evaluation_window_seconds,max_evidence_age_seconds,
  min_request_count,warning_5xx_rate,critical_5xx_rate,warning_p95_ms,critical_p95_ms,
  warning_runtime_error_count,critical_runtime_error_count,effective_at,evidence_ref,evidence_note
)
select
  'foundation.gateway',
  'production',
  '1.1.0',
  3600,
  600,
  3,
  0.100000,
  0.500000,
  5000,
  10000,
  1,
  2,
  now(),
  'foundation:health-policy:gateway-production:v1.1',
  'Automatic collector policy: three fresh synthetic probes are enough to evaluate; one-of-three failure degrades, two-of-three failures are critical. Live traffic telemetry may still contribute when it is newer.'
where not exists (
  select 1
  from foundation.service_health_policies
  where service_id='foundation.gateway'
    and environment='production'
    and policy_version='1.1.0'
);


-- Layer 23 deterministic tie-breaker for batched health evidence.
-- Probe windows can share window_ended_at/recorded_at inside one transaction;
-- prefer the highest monotonic probe result sequence before UUID ordering.
create or replace view foundation.current_service_health_evidence
with (security_invoker=true)
as
select distinct on (service_id,environment)
  health_evidence_id,
  service_id,
  environment,
  runtime_version,
  window_started_at,
  window_ended_at,
  request_count,
  response_4xx_count,
  response_5xx_count,
  avg_latency_ms,
  p95_latency_ms,
  runtime_error_count,
  evidence_source,
  evidence_ref,
  evidence_note,
  metadata,
  observed_at,
  recorded_at
from foundation.service_health_evidence
order by
  service_id,
  environment,
  window_ended_at desc,
  case
    when evidence_source='healthcheck'
     and coalesce(metadata->>'latestProbeResultSequence','') ~ '^[0-9]+$'
    then (metadata->>'latestProbeResultSequence')::bigint
    else 0
  end desc,
  observed_at desc,
  recorded_at desc,
  health_evidence_id desc;

revoke all on foundation.current_service_health_evidence from public,anon,authenticated;
grant select on foundation.current_service_health_evidence to foundation_runtime;

