-- Shine Defence hosted runtime provenance harvester v1.
-- Extends the existing pg_net health response harvest with credential-free
-- Railway serving-release identity from bounded response headers.

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
  v_provenance jsonb;
  v_harvested integer := 0;
  v_refreshed integer := 0;
  v_provenance_recorded integer := 0;
  v_provenance_rejected integer := 0;
  v_provenance_skipped integer := 0;
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
      r.headers,
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

    if v_contract_ok then
      v_provenance := foundation.record_defence_runtime_provenance_v1(
        v_row.target_id,
        coalesce(v_row.headers,'{}'::jsonb),
        v_sequence
      );

      case v_provenance->>'status'
        when 'recorded' then
          v_provenance_recorded := v_provenance_recorded+1;
        when 'rejected' then
          v_provenance_rejected := v_provenance_rejected+1;
        else
          v_provenance_skipped := v_provenance_skipped+1;
      end case;
    end if;

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
    'runtimeProvenanceCollector','shine-defence/runtime-provenance-v1',
    'harvested',v_harvested,
    'refreshed',v_refreshed,
    'runtimeProvenanceRecorded',v_provenance_recorded,
    'runtimeProvenanceRejected',v_provenance_rejected,
    'runtimeProvenanceSkipped',v_provenance_skipped
  );
end;
$$;

revoke all on function foundation.harvest_defence_health_probe_responses_v1(integer)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.harvest_defence_health_probe_responses_v1(integer)
  to service_role;
