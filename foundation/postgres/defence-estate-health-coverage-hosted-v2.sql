-- Shine Defence hosted estate health coverage v2.
-- Continuous schedule skips sleep-aware targets; on-demand probes are explicit.

create or replace function foundation.enqueue_defence_health_probe_for_target_v1(
  p_target_id text
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net
as $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_external_request_id bigint;
  v_probe_request_id uuid;
begin
  select *
    into v_target
  from foundation.current_defence_health_probe_target
  where target_id=p_target_id
    and enabled;

  if v_target.target_id is null then
    return jsonb_build_object(
      'status','skipped',
      'reasonCode','missing-or-disabled-health-target',
      'targetId',p_target_id
    );
  end if;

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
      'responseMode',v_target.response_mode,
      'probeMode',v_target.probe_mode
    )
  )
  returning probe_request_id into v_probe_request_id;

  return jsonb_build_object(
    'status','queued',
    'targetId',v_target.target_id,
    'probeMode',v_target.probe_mode,
    'probeRequestId',v_probe_request_id,
    'externalRequestId',v_external_request_id
  );
end;
$$;

revoke all on function foundation.enqueue_defence_health_probe_for_target_v1(text)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.enqueue_defence_health_probe_for_target_v1(text)
  to service_role;


create or replace function foundation.enqueue_defence_health_probes_v1()
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net
as $$
declare
  v_target foundation.defence_health_probe_targets%rowtype;
  v_result jsonb;
  v_queued integer := 0;
begin
  for v_target in
    select *
    from foundation.current_defence_health_probe_target
    where enabled
      and probe_mode='continuous'
    order by target_id
  loop
    v_result := foundation.enqueue_defence_health_probe_for_target_v1(v_target.target_id);
    if v_result->>'status'='queued' then
      v_queued := v_queued+1;
    end if;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'collector','shine-defence/estate-health-adapters-v2',
    'queued',v_queued,
    'probeMode','continuous'
  );
end;
$$;

revoke all on function foundation.enqueue_defence_health_probes_v1()
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.enqueue_defence_health_probes_v1()
  to service_role;
