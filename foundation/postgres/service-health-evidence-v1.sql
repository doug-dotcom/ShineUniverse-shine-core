-- Foundation Layer 22: health and state evidence.
-- Health is derived from explicit policy + fresh runtime evidence.
-- Missing or stale evidence returns unknown; deployment existence never implies health.

create table foundation.service_health_policies (
  policy_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  policy_version text not null,
  evaluation_window_seconds integer not null
    check (evaluation_window_seconds > 0),
  max_evidence_age_seconds integer not null
    check (max_evidence_age_seconds > 0),
  min_request_count integer not null
    check (min_request_count >= 0),
  warning_5xx_rate numeric(8,6) not null
    check (warning_5xx_rate >= 0 and warning_5xx_rate <= 1),
  critical_5xx_rate numeric(8,6) not null
    check (critical_5xx_rate >= warning_5xx_rate and critical_5xx_rate <= 1),
  warning_p95_ms numeric(12,3) not null
    check (warning_p95_ms > 0),
  critical_p95_ms numeric(12,3) not null
    check (critical_p95_ms >= warning_p95_ms),
  warning_runtime_error_count integer not null default 1
    check (warning_runtime_error_count >= 0),
  critical_runtime_error_count integer not null default 5
    check (critical_runtime_error_count >= warning_runtime_error_count),
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  unique(service_id,environment,policy_version)
);

alter table foundation.service_health_policies enable row level security;

create policy foundation_runtime_service_health_policies_select
on foundation.service_health_policies
for select
to foundation_runtime
using (true);

revoke all on foundation.service_health_policies from public,anon,authenticated;
grant select on foundation.service_health_policies to foundation_runtime;
grant select,insert on foundation.service_health_policies to service_role;

create index service_health_policies_current_idx
  on foundation.service_health_policies(service_id,environment,effective_at desc,recorded_at desc);

create trigger service_health_policies_append_only
before update or delete on foundation.service_health_policies
for each row execute function foundation.reject_append_only_mutation();


create table foundation.service_health_evidence (
  health_evidence_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  runtime_version text,
  window_started_at timestamptz not null,
  window_ended_at timestamptz not null,
  request_count integer not null
    check (request_count >= 0),
  response_4xx_count integer not null default 0
    check (response_4xx_count >= 0),
  response_5xx_count integer not null default 0
    check (response_5xx_count >= 0),
  avg_latency_ms numeric(12,3)
    check (avg_latency_ms is null or avg_latency_ms >= 0),
  p95_latency_ms numeric(12,3)
    check (p95_latency_ms is null or p95_latency_ms >= 0),
  runtime_error_count integer not null default 0
    check (runtime_error_count >= 0),
  evidence_source text not null
    check (evidence_source in ('supabase-logs','healthcheck','railway-metrics','deployment-api','manual-verified')),
  evidence_ref text not null unique,
  evidence_note text,
  metadata jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  recorded_at timestamptz not null default now(),
  check (window_ended_at >= window_started_at),
  check (response_4xx_count + response_5xx_count <= request_count),
  check (jsonb_typeof(metadata)='object')
);

alter table foundation.service_health_evidence enable row level security;

create policy foundation_runtime_service_health_evidence_select
on foundation.service_health_evidence
for select
to foundation_runtime
using (true);

revoke all on foundation.service_health_evidence from public,anon,authenticated;
grant select on foundation.service_health_evidence to foundation_runtime;
grant select,insert on foundation.service_health_evidence to service_role;

create index service_health_evidence_current_idx
  on foundation.service_health_evidence(service_id,environment,window_ended_at desc,recorded_at desc);

create trigger service_health_evidence_append_only
before update or delete on foundation.service_health_evidence
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_service_health_policy
with (security_invoker=true)
as
select distinct on (service_id,environment)
  policy_id,
  service_id,
  environment,
  policy_version,
  evaluation_window_seconds,
  max_evidence_age_seconds,
  min_request_count,
  warning_5xx_rate,
  critical_5xx_rate,
  warning_p95_ms,
  critical_p95_ms,
  warning_runtime_error_count,
  critical_runtime_error_count,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.service_health_policies
order by service_id,environment,effective_at desc,recorded_at desc,policy_id desc;

revoke all on foundation.current_service_health_policy from public,anon,authenticated;
grant select on foundation.current_service_health_policy to foundation_runtime;


create view foundation.current_service_health_evidence
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
order by service_id,environment,window_ended_at desc,recorded_at desc,health_evidence_id desc;

revoke all on foundation.current_service_health_evidence from public,anon,authenticated;
grant select on foundation.current_service_health_evidence to foundation_runtime;


create or replace function foundation.get_service_health_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_service foundation.service_registry%rowtype;
  v_policy foundation.service_health_policies%rowtype;
  v_evidence foundation.service_health_evidence%rowtype;
  v_health_state text := 'unknown';
  v_reason_codes text[] := array[]::text[];
  v_5xx_rate numeric := null;
  v_evidence_age_seconds numeric := null;
begin
  select *
    into v_service
  from foundation.service_registry
  where service_id=p_service_id;

  if v_service.service_id is null then
    return jsonb_build_object(
      'serviceHealthResponse','shine-foundation/service-health-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'healthState','unknown',
      'reasonCodes',jsonb_build_array('unknown-service')
    );
  end if;

  select *
    into v_policy
  from foundation.current_service_health_policy
  where service_id=p_service_id
    and environment=p_environment;

  select *
    into v_evidence
  from foundation.current_service_health_evidence
  where service_id=p_service_id
    and environment=p_environment;

  if v_policy.policy_id is null then
    v_reason_codes := array_append(v_reason_codes,'missing-health-policy');
  end if;

  if v_evidence.health_evidence_id is null then
    v_reason_codes := array_append(v_reason_codes,'missing-health-evidence');
  end if;

  if v_policy.policy_id is not null and v_evidence.health_evidence_id is not null then
    v_evidence_age_seconds := greatest(0,extract(epoch from (now()-v_evidence.window_ended_at)));

    if v_evidence.request_count > 0 then
      v_5xx_rate := v_evidence.response_5xx_count::numeric / v_evidence.request_count::numeric;
    else
      v_5xx_rate := 0;
    end if;

    if v_evidence_age_seconds > v_policy.max_evidence_age_seconds then
      v_reason_codes := array_append(v_reason_codes,'health-evidence-stale');
      v_health_state := 'unknown';
    elsif v_evidence.request_count < v_policy.min_request_count then
      v_reason_codes := array_append(v_reason_codes,'insufficient-request-sample');
      v_health_state := 'unknown';
    elsif v_5xx_rate >= v_policy.critical_5xx_rate
       or coalesce(v_evidence.p95_latency_ms,0) >= v_policy.critical_p95_ms
       or v_evidence.runtime_error_count >= v_policy.critical_runtime_error_count then
      v_health_state := 'unhealthy';

      if v_5xx_rate >= v_policy.critical_5xx_rate then
        v_reason_codes := array_append(v_reason_codes,'critical-5xx-rate');
      end if;
      if coalesce(v_evidence.p95_latency_ms,0) >= v_policy.critical_p95_ms then
        v_reason_codes := array_append(v_reason_codes,'critical-p95-latency');
      end if;
      if v_evidence.runtime_error_count >= v_policy.critical_runtime_error_count then
        v_reason_codes := array_append(v_reason_codes,'critical-runtime-errors');
      end if;
    elsif v_5xx_rate >= v_policy.warning_5xx_rate
       or coalesce(v_evidence.p95_latency_ms,0) >= v_policy.warning_p95_ms
       or v_evidence.runtime_error_count >= v_policy.warning_runtime_error_count then
      v_health_state := 'degraded';

      if v_5xx_rate >= v_policy.warning_5xx_rate then
        v_reason_codes := array_append(v_reason_codes,'elevated-5xx-rate');
      end if;
      if coalesce(v_evidence.p95_latency_ms,0) >= v_policy.warning_p95_ms then
        v_reason_codes := array_append(v_reason_codes,'elevated-p95-latency');
      end if;
      if v_evidence.runtime_error_count >= v_policy.warning_runtime_error_count then
        v_reason_codes := array_append(v_reason_codes,'runtime-errors-observed');
      end if;
    else
      v_health_state := 'healthy';
    end if;
  end if;

  return jsonb_build_object(
    'serviceHealthResponse','shine-foundation/service-health-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',v_service.service_id,
    'displayName',v_service.display_name,
    'environment',p_environment,
    'healthState',v_health_state,
    'reasonCodes',to_jsonb(v_reason_codes),
    'metrics',case
      when v_evidence.health_evidence_id is null then null
      else jsonb_build_object(
        'runtimeVersion',v_evidence.runtime_version,
        'windowStartedAt',v_evidence.window_started_at,
        'windowEndedAt',v_evidence.window_ended_at,
        'evidenceAgeSeconds',v_evidence_age_seconds,
        'requestCount',v_evidence.request_count,
        'response4xxCount',v_evidence.response_4xx_count,
        'response5xxCount',v_evidence.response_5xx_count,
        'response5xxRate',v_5xx_rate,
        'avgLatencyMs',v_evidence.avg_latency_ms,
        'p95LatencyMs',v_evidence.p95_latency_ms,
        'runtimeErrorCount',v_evidence.runtime_error_count,
        'evidenceSource',v_evidence.evidence_source,
        'evidenceRef',v_evidence.evidence_ref
      )
    end,
    'policy',case
      when v_policy.policy_id is null then null
      else jsonb_build_object(
        'policyVersion',v_policy.policy_version,
        'evaluationWindowSeconds',v_policy.evaluation_window_seconds,
        'maxEvidenceAgeSeconds',v_policy.max_evidence_age_seconds,
        'minRequestCount',v_policy.min_request_count,
        'warning5xxRate',v_policy.warning_5xx_rate,
        'critical5xxRate',v_policy.critical_5xx_rate,
        'warningP95Ms',v_policy.warning_p95_ms,
        'criticalP95Ms',v_policy.critical_p95_ms,
        'warningRuntimeErrorCount',v_policy.warning_runtime_error_count,
        'criticalRuntimeErrorCount',v_policy.critical_runtime_error_count,
        'evidenceRef',v_policy.evidence_ref
      )
    end
  );
end;
$$;

revoke all on function foundation.get_service_health_v1(text,text) from public,anon,authenticated;
grant execute on function foundation.get_service_health_v1(text,text) to foundation_runtime;


create or replace function foundation.get_service_state_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_deployment jsonb;
  v_health jsonb;
  v_state text;
begin
  v_deployment := foundation.get_service_deployment_truth_v1(p_service_id,p_environment);
  v_health := foundation.get_service_health_v1(p_service_id,p_environment);

  v_state := case
    when v_deployment->>'truthState'='unknown' then 'unknown'
    when v_health->>'healthState'='unknown' then 'unknown'
    when v_health->>'healthState'='unhealthy' then 'unhealthy'
    when v_deployment->>'truthState'='drift' then 'drift'
    when v_health->>'healthState'='degraded' then 'degraded'
    when v_deployment->>'truthState'='aligned'
      and v_health->>'healthState'='healthy' then 'operational'
    else 'unknown'
  end;

  return jsonb_build_object(
    'serviceStateResponse','shine-foundation/service-state-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',p_service_id,
    'environment',p_environment,
    'operationalState',v_state,
    'deployment',v_deployment,
    'health',v_health
  );
end;
$$;

revoke all on function foundation.get_service_state_v1(text,text) from public,anon,authenticated;
grant execute on function foundation.get_service_state_v1(text,text) to foundation_runtime;


create or replace function foundation.get_foundation_health_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_services jsonb;
  v_overall text;
begin
  select coalesce(
    jsonb_agg(
      foundation.get_service_state_v1(s.service_id,p_environment)
      order by s.service_id
    ),
    '[]'::jsonb
  )
  into v_services
  from foundation.service_registry s
  where s.required_for_core=true
    and s.lifecycle='active';

  select case
    when jsonb_array_length(v_services)=0 then 'unknown'
    when exists (
      select 1 from jsonb_array_elements(v_services) x
      where x->>'operationalState'='unhealthy'
    ) then 'unhealthy'
    when exists (
      select 1 from jsonb_array_elements(v_services) x
      where x->>'operationalState'='drift'
    ) then 'drift'
    when exists (
      select 1 from jsonb_array_elements(v_services) x
      where x->>'operationalState'='degraded'
    ) then 'degraded'
    when exists (
      select 1 from jsonb_array_elements(v_services) x
      where x->>'operationalState'='unknown'
    ) then 'unknown'
    else 'operational'
  end
  into v_overall;

  return jsonb_build_object(
    'foundationHealthResponse','shine-foundation/foundation-health-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'operationalState',v_overall,
    'services',v_services
  );
end;
$$;

revoke all on function foundation.get_foundation_health_v1(text) from public,anon,authenticated;
grant execute on function foundation.get_foundation_health_v1(text) to foundation_runtime;


insert into foundation.service_health_policies(
  service_id,
  environment,
  policy_version,
  evaluation_window_seconds,
  max_evidence_age_seconds,
  min_request_count,
  warning_5xx_rate,
  critical_5xx_rate,
  warning_p95_ms,
  critical_p95_ms,
  warning_runtime_error_count,
  critical_runtime_error_count,
  effective_at,
  evidence_ref,
  evidence_note
)
select
  'foundation.gateway',
  'production',
  '1.0.0',
  3600,
  900,
  20,
  0.010000,
  0.050000,
  8000,
  15000,
  1,
  5,
  now(),
  'foundation:health-policy:gateway-production:v1',
  'Initial Foundation Gateway health thresholds. 5xx failures, p95 latency, runtime errors, evidence freshness and minimum sample size are evaluated independently.'
where not exists (
  select 1
  from foundation.service_health_policies
  where service_id='foundation.gateway'
    and environment='production'
    and policy_version='1.0.0'
);
