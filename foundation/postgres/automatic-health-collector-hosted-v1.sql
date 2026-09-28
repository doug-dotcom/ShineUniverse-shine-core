-- Foundation Layer 23: hosted automatic health collector wiring.
-- Supabase-hosted only: pg_net + pg_cron invoke the public Foundation Gateway health endpoint.

create extension if not exists pg_net;

create or replace function foundation.enqueue_service_health_probe_v1(
  p_service_id text,
  p_environment text default 'production'
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net
as $$
declare
  v_target foundation.service_health_probe_targets%rowtype;
  v_request_id bigint;
  v_probe_request_id uuid;
  v_queued_at timestamptz := now();
  v_evidence_ref text;
begin
  select *
    into v_target
  from foundation.current_service_health_probe_target
  where service_id=p_service_id
    and environment=p_environment;

  if v_target.target_id is null then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','missing-probe-target',
      'serviceId',p_service_id,
      'environment',p_environment
    );
  end if;

  if not v_target.enabled then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','probe-target-disabled',
      'serviceId',p_service_id,
      'environment',p_environment
    );
  end if;

  v_request_id := net.http_get(
    url := v_target.target_url,
    headers := jsonb_build_object(
      'Accept','application/json',
      'User-Agent','Shine-Foundation-Health-Collector/1.0'
    ),
    timeout_milliseconds := v_target.timeout_milliseconds
  );

  v_evidence_ref :=
    'pg-net:health-probe-request:' ||
    p_service_id || ':' || p_environment || ':' || v_request_id::text;

  v_probe_request_id := foundation.record_service_health_probe_request_v1(
    p_service_id,
    p_environment,
    v_target.target_id,
    v_request_id,
    v_target.target_url,
    v_queued_at,
    v_evidence_ref,
    jsonb_build_object(
      'collector','shine-foundation/automatic-health-collector-v1',
      'targetVersion',v_target.target_version
    )
  );

  return jsonb_build_object(
    'status','queued',
    'serviceId',p_service_id,
    'environment',p_environment,
    'probeRequestId',v_probe_request_id,
    'externalRequestId',v_request_id,
    'targetUrl',v_target.target_url
  );
end;
$$;

revoke all on function foundation.enqueue_service_health_probe_v1(text,text)
  from public,anon,authenticated,foundation_runtime;
grant execute on function foundation.enqueue_service_health_probe_v1(text,text)
  to service_role;


create or replace function foundation.harvest_service_health_probe_responses_v1(
  p_limit integer default 100
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net, extensions
as $$
declare
  v_row record;
  v_body jsonb;
  v_contract_ok boolean;
  v_roundtrip_ms numeric;
  v_response_sha256 text;
  v_result_sequence bigint;
  v_target_row record;
  v_harvested integer := 0;
  v_refreshed integer := 0;
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000';
  end if;

  for v_row in
    select
      q.probe_request_id,
      q.service_id,
      q.environment,
      q.queued_at,
      q.external_request_id,
      t.expected_service,
      t.expected_status,
      t.expected_schema_version,
      r.status_code,
      r.content_type,
      r.content,
      coalesce(r.timed_out,false) as timed_out,
      r.error_msg,
      r.created as response_at
    from foundation.service_health_probe_requests q
    join foundation.service_health_probe_targets t
      on t.target_id=q.target_id
    join net._http_response r
      on r.id=q.external_request_id
    left join foundation.service_health_probe_results existing
      on existing.probe_request_id=q.probe_request_id
    where existing.probe_request_id is null
      and q.external_request_id is not null
    order by q.queued_at
    limit p_limit
  loop
    v_body := null;
    v_contract_ok := false;

    if v_row.content is not null then
      begin
        v_body := v_row.content::jsonb;
      exception
        when others then
          v_body := null;
      end;
    end if;

    if v_row.status_code between 200 and 299
       and not v_row.timed_out
       and v_row.error_msg is null
       and v_body is not null
       and v_body->>'service'=v_row.expected_service
       and v_body->>'status'=v_row.expected_status
       and v_body->>'schemaVersion'=v_row.expected_schema_version then
      v_contract_ok := true;
    end if;

    v_roundtrip_ms := greatest(
      0,
      extract(epoch from (v_row.response_at-v_row.queued_at))*1000
    );

    v_response_sha256 := case
      when v_row.content is null then null
      else encode(extensions.digest(convert_to(v_row.content,'UTF8'),'sha256'),'hex')
    end;

    v_result_sequence := foundation.record_service_health_probe_result_v1(
      v_row.probe_request_id,
      v_row.status_code,
      v_row.timed_out,
      v_row.error_msg,
      v_contract_ok,
      v_row.response_at,
      v_roundtrip_ms,
      v_response_sha256,
      'pg-net:health-probe-result:' || v_row.external_request_id::text,
      jsonb_build_object(
        'collector','shine-foundation/automatic-health-collector-v1',
        'contentType',v_row.content_type
      )
    );

    v_harvested := v_harvested + 1;
  end loop;

  for v_target_row in
    select service_id,environment
    from foundation.current_service_health_probe_target
    where enabled=true
  loop
    perform foundation.refresh_service_health_from_probes_v1(
      v_target_row.service_id,
      v_target_row.environment,
      clock_timestamp()
    );
    v_refreshed := v_refreshed + 1;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'harvested',v_harvested,
    'refreshed',v_refreshed
  );
end;
$$;

revoke all on function foundation.harvest_service_health_probe_responses_v1(integer)
  from public,anon,authenticated,foundation_runtime;
grant execute on function foundation.harvest_service_health_probe_responses_v1(integer)
  to service_role;


select cron.schedule(
  'shine-foundation-health-probe-5m',
  '*/5 * * * *',
  $$select foundation.enqueue_service_health_probe_v1('foundation.gateway','production');$$
);

select cron.schedule(
  'shine-foundation-health-harvest-1m',
  '* * * * *',
  $$select foundation.harvest_service_health_probe_responses_v1(100);$$
);
