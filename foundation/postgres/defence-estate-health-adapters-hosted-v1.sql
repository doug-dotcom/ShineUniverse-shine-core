-- Shine Defence hosted estate health collector v1.
-- Supabase-hosted only: pg_net performs credential-free GET probes against
-- existing public health endpoints; response bodies are evaluated then discarded.

create or replace function foundation.enqueue_defence_health_probes_v1()
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net
as $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_external_request_id bigint;
  v_probe_request_id uuid;
  v_queued integer := 0;
begin
  for v_target in
    select *
    from foundation.current_defence_health_probe_target
    where enabled
    order by target_id
  loop
    v_external_request_id := net.http_get(
      url := v_target.target_url,
      headers := jsonb_build_object(
        'Accept','application/json, text/plain;q=0.9',
        'User-Agent','Shine-Defence-Estate-Health/1.0'
      ),
      timeout_milliseconds := v_target.timeout_milliseconds
    );

    insert into foundation.defence_health_probe_requests(
      target_id,target_version,external_request_id,target_url,queued_at,
      evidence_ref,metadata
    ) values (
      v_target.target_id,
      v_target.target_version,
      v_external_request_id,
      v_target.target_url,
      now(),
      'pg-net:defence-health-request:' || v_target.target_id || ':' || v_external_request_id::text,
      jsonb_build_object(
        'collector','shine-defence/estate-health-adapters-v1',
        'responseMode',v_target.response_mode
      )
    )
    returning probe_request_id into v_probe_request_id;

    v_queued := v_queued+1;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'collector','shine-defence/estate-health-adapters-v1',
    'queued',v_queued
  );
end;
$$;

revoke all on function foundation.enqueue_defence_health_probes_v1()
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.enqueue_defence_health_probes_v1()
  to service_role;


create or replace function foundation.harvest_defence_health_probe_responses_v1(
  p_limit integer default 200
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net, extensions
as $$
declare
  v_row record;
  v_contract_ok boolean;
  v_roundtrip_ms numeric;
  v_response_sha256 text;
  v_sequence bigint;
  v_target record;
  v_harvested integer := 0;
  v_refreshed integer := 0;
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'p_limit must be between 1 and 1000';
  end if;

  for v_row in
    select
      q.probe_request_id,
      q.target_id,
      q.queued_at,
      t.response_mode,
      t.expected_json,
      t.expected_text,
      r.status_code,
      r.content_type,
      r.content,
      coalesce(r.timed_out,false) as timed_out,
      r.error_msg,
      r.created as response_at
    from foundation.defence_health_probe_requests q
    join foundation.defence_health_probe_targets t
      on t.target_id=q.target_id
     and t.target_version=q.target_version
    join net._http_response r
      on r.id=q.external_request_id
    left join foundation.defence_health_probe_results existing
      on existing.probe_request_id=q.probe_request_id
    where existing.probe_request_id is null
      and q.external_request_id is not null
    order by q.queued_at
    limit p_limit
  loop
    v_contract_ok := foundation.defence_health_contract_matches_v1(
      v_row.response_mode,
      v_row.expected_json,
      v_row.expected_text,
      v_row.status_code,
      v_row.timed_out,
      v_row.error_msg,
      v_row.content
    );

    v_roundtrip_ms := greatest(
      0,
      extract(epoch from (v_row.response_at-v_row.queued_at))*1000
    );

    v_response_sha256 := case
      when v_row.content is null then null
      else encode(extensions.digest(convert_to(v_row.content,'UTF8'),'sha256'),'hex')
    end;

    v_sequence := foundation.record_defence_health_probe_result_v1(
      v_row.probe_request_id,
      v_row.status_code,
      v_row.timed_out,
      v_row.error_msg,
      v_contract_ok,
      v_row.response_at,
      v_roundtrip_ms,
      v_response_sha256,
      'pg-net:defence-health-result:' || v_row.probe_request_id::text,
      jsonb_build_object(
        'collector','shine-defence/estate-health-adapters-v1',
        'contentType',v_row.content_type,
        'responseMode',v_row.response_mode
      )
    );

    v_harvested := v_harvested+1;
  end loop;

  for v_target in
    select target_id
    from foundation.current_defence_health_probe_target
    where enabled
    order by target_id
  loop
    perform foundation.refresh_defence_health_from_probes_v1(
      v_target.target_id,
      clock_timestamp()
    );
    v_refreshed := v_refreshed+1;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'collector','shine-defence/estate-health-adapters-v1',
    'harvested',v_harvested,
    'refreshed',v_refreshed
  );
end;
$$;

revoke all on function foundation.harvest_defence_health_probe_responses_v1(integer)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.harvest_defence_health_probe_responses_v1(integer)
  to service_role;


select cron.schedule(
  'shine-defence-estate-health-probe-5m',
  '2,7,12,17,22,27,32,37,42,47,52,57 * * * *',
  $$select foundation.enqueue_defence_health_probes_v1();$$
);

select cron.schedule(
  'shine-defence-estate-health-harvest-1m',
  '* * * * *',
  $$select foundation.harvest_defence_health_probe_responses_v1(200);$$
);
