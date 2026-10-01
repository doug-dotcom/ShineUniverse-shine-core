begin;

do $operational_attention_fixture$
declare
  t timestamptz := clock_timestamp()-interval '15 minutes';
  nowish timestamptz := clock_timestamp();
  attention jsonb;
  hp foundation.defence_health_probe_targets%rowtype;
begin
  -- Confirmed shared transport cycle: 3 failures of 4 results.
  insert into foundation.defence_health_probe_requests(
    probe_request_id,target_id,target_version,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  )
  select
    gen_random_uuid(),p.target_id,p.target_version,null,p.target_url,
    t,'test:operational-attention:shared:'||p.target_id,'{}'::jsonb
  from foundation.current_defence_health_probe_target p
  where p.target_id in (
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
    case when q.target_id='railway:project-l' then null
      else 'Timeout of 10000 ms reached. TCP/SSL handshake time: 9300 ms' end,
    q.target_id='railway:project-l',
    t+interval '1 second',
    900,null,
    'test:operational-attention:shared-result:'||q.target_id,
    '{}'::jsonb
  from foundation.defence_health_probe_requests q
  where q.evidence_ref like 'test:operational-attention:shared:%';

  -- Complete recovery cycle five minutes later.
  insert into foundation.defence_health_probe_requests(
    probe_request_id,target_id,target_version,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  )
  select
    gen_random_uuid(),p.target_id,p.target_version,null,p.target_url,
    t+interval '5 minutes',
    'test:operational-attention:recovery:'||p.target_id,'{}'::jsonb
  from foundation.current_defence_health_probe_target p
  where p.target_id in (
    'railway:daash','railway:dive','railway:fiona','railway:project-l'
  );

  insert into foundation.defence_health_probe_results(
    probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
    response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  )
  select
    q.probe_request_id,q.target_id,200,false,null,true,
    t+interval '5 minutes 1 second',400,null,
    'test:operational-attention:recovery-result:'||q.target_id,
    '{}'::jsonb
  from foundation.defence_health_probe_requests q
  where q.evidence_ref like 'test:operational-attention:recovery:%';

  -- Residual degraded health for DaAsh contains only the shared failed sample.
  insert into foundation.defence_health_observations(
    target_id,health_state,sample_count,failure_count,
    window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    'railway:daash','degraded',2,1,
    t-interval '1 minute',t+interval '6 minutes',650,900,
    nowish,nowish+interval '10 minutes',
    'test:operational-attention:daash-health',
    '{"test":true}'::jsonb
  );

  -- Target-specific failure for Fish outside any shared cluster.
  select * into hp
  from foundation.current_defence_health_probe_target
  where target_id='railway:fish';

  insert into foundation.defence_health_probe_requests(
    probe_request_id,target_id,target_version,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  ) values (
    gen_random_uuid(),hp.target_id,hp.target_version,null,hp.target_url,
    t+interval '9 minutes',
    'test:operational-attention:fish-specific','{}'::jsonb
  );

  insert into foundation.defence_health_probe_results(
    probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
    response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  )
  select
    q.probe_request_id,q.target_id,null,true,
    'Timeout of 10000 ms reached. TCP/SSL handshake time: 9400 ms',
    false,t+interval '9 minutes 1 second',1000,null,
    'test:operational-attention:fish-specific-result','{}'::jsonb
  from foundation.defence_health_probe_requests q
  where q.evidence_ref='test:operational-attention:fish-specific';

  insert into foundation.defence_health_observations(
    target_id,health_state,sample_count,failure_count,
    window_started_at,window_ended_at,avg_roundtrip_ms,p95_roundtrip_ms,
    observed_at,valid_until,evidence_ref,metadata
  ) values (
    'railway:fish','degraded',1,1,
    t+interval '8 minutes',t+interval '10 minutes',1000,1000,
    nowish+interval '1 millisecond',nowish+interval '10 minutes',
    'test:operational-attention:fish-health',
    '{"test":true}'::jsonb
  );

  select foundation.get_defence_operational_attention_v1(
    nowish+interval '2 milliseconds',2700,3,0.5
  ) into attention;

  if attention->>'rawEstateStateOverridden'<>'false'
     or attention->>'rawHealthEvidencePreserved'<>'true'
     or not exists (
       select 1
       from jsonb_array_elements(attention->'estateItems') x
       where x->>'causeClass'='confirmed_shared_transport'
         and x->>'clusterState'='recovered'
     )
     or not exists (
       select 1
       from jsonb_array_elements(attention->'targetItems') x
       where x->>'targetId'='railway:daash'
         and x->>'causeClass'='confirmed_shared_transport_residual'
         and x->>'nextAction'='observe_residual_health_window'
     )
     or not exists (
       select 1
       from jsonb_array_elements(attention->'targetItems') x
       where x->>'targetId'='railway:fish'
         and x->>'causeClass'='target_specific'
         and x->>'nextAction'='investigate_target_health'
     ) then
    raise exception 'Operational attention classification failed: %',attention;
  end if;
end;
$operational_attention_fixture$;

do $operational_attention_security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_operational_attention_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_operational_attention_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_operational_attention_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     ) then
    raise exception 'Operational attention privilege boundary invalid';
  end if;
end;
$operational_attention_security$;

do $operational_attention_invalid$
begin
  begin
    perform foundation.get_defence_operational_attention_v1(
      clock_timestamp(),300,3,0.5
    );
    raise exception 'Invalid operational attention window accepted';
  exception
    when sqlstate '22023' then null;
  end;
end;
$operational_attention_invalid$;

rollback;
