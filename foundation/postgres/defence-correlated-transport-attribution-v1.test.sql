begin;

do $correlated_transport_fixture$
declare
  t timestamptz := '2099-01-01T00:00:00Z';
  attribution jsonb;
begin
  insert into foundation.defence_health_probe_requests(
    probe_request_id,target_id,target_version,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  )
  select
    gen_random_uuid(),hp.target_id,hp.target_version,null,hp.target_url,
    t,'test:correlated-transport:event:'||hp.target_id,'{}'::jsonb
  from foundation.current_defence_health_probe_target hp
  where hp.target_id in (
    'railway:daash','railway:dive','railway:fiona','railway:project-l'
  );

  insert into foundation.defence_health_probe_results(
    probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
    response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  )
  select
    q.probe_request_id,
    q.target_id,
    case when q.target_id='railway:project-l' then 200 else null end,
    q.target_id<>'railway:project-l',
    case
      when q.target_id='railway:project-l' then null
      else 'Timeout of 10000 ms reached. TCP/SSL handshake time: 9300 ms'
    end,
    q.target_id='railway:project-l',
    t+interval '1 second',
    1000,
    null,
    'test:correlated-transport:event-result:'||q.target_id,
    '{}'::jsonb
  from foundation.defence_health_probe_requests q
  where q.evidence_ref like 'test:correlated-transport:event:%';

  select foundation.get_defence_correlated_transport_attribution_v1(
    t+interval '2 minutes',21600,3,0.5
  ) into attribution;

  if attribution->>'state'<>'active'
     or attribution->>'reasonCode'<>'correlated-transport-failure-active'
     or (attribution#>>'{event,resultCount}')::integer<>4
     or (attribution#>>'{event,transportFailureCount}')::integer<>3
     or (attribution#>>'{event,nonTransportFailureCount}')::integer<>0
     or attribution->>'rawHealthEvidencePreserved'<>'true'
     or attribution->>'rawEstateStateOverridden'<>'false' then
    raise exception 'Active correlated transport event misclassified: %',attribution;
  end if;

  insert into foundation.defence_health_probe_requests(
    probe_request_id,target_id,target_version,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  )
  select
    gen_random_uuid(),hp.target_id,hp.target_version,null,hp.target_url,
    t+interval '5 minutes',
    'test:correlated-transport:recovery:'||hp.target_id,
    '{}'::jsonb
  from foundation.current_defence_health_probe_target hp
  where hp.target_id in (
    'railway:daash','railway:dive','railway:fiona','railway:project-l'
  );

  insert into foundation.defence_health_probe_results(
    probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
    response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  )
  select
    q.probe_request_id,q.target_id,200,false,null,true,
    t+interval '5 minutes 1 second',500,null,
    'test:correlated-transport:recovery-result:'||q.target_id,
    '{}'::jsonb
  from foundation.defence_health_probe_requests q
  where q.evidence_ref like 'test:correlated-transport:recovery:%';

  select foundation.get_defence_correlated_transport_attribution_v1(
    t+interval '7 minutes',21600,3,0.5
  ) into attribution;

  if attribution->>'state'<>'recovered'
     or attribution->>'reasonCode'<>'correlated-transport-failure-recovered'
     or (attribution#>>'{recovery,resultCount}')::integer<>4
     or (attribution#>>'{recovery,passCount}')::integer<>4
     or (attribution#>>'{recovery,failureCount}')::integer<>0 then
    raise exception 'Recovered correlated transport event misclassified: %',attribution;
  end if;
end;
$correlated_transport_fixture$;

do $correlated_transport_security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_correlated_transport_attribution_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_correlated_transport_attribution_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_correlated_transport_attribution_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     ) then
    raise exception 'Correlated transport attribution privilege boundary invalid';
  end if;
end;
$correlated_transport_security$;

do $correlated_transport_invalid$
begin
  begin
    perform foundation.get_defence_correlated_transport_attribution_v1(
      clock_timestamp(),300,3,0.5
    );
    raise exception 'Invalid correlated transport attribution window accepted';
  exception
    when sqlstate '22023' then null;
  end;
end;
$correlated_transport_invalid$;

rollback;
