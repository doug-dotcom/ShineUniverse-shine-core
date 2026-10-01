begin;

do $target_recovery_fixture$
declare
  t timestamptz := '2099-03-01T00:00:00Z';
  v_target text := 'railway:translate';
  request_id uuid;
  attention jsonb;
  result jsonb;
  recovered_item jsonb;
begin
  -- One isolated failure.
  request_id := gen_random_uuid();
  insert into foundation.defence_health_probe_requests(
    probe_request_id,target_id,target_version,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  )
  select
    request_id,hp.target_id,hp.target_version,null,hp.target_url,
    t,'test:target-recovery:failure','{}'::jsonb
  from foundation.current_defence_health_probe_target hp
  where hp.target_id=v_target;

  insert into foundation.defence_health_probe_results(
    probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
    response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  )
  values(
    request_id,v_target,null,true,
    'Timeout of 10000 ms reached. Total time: 10000 ms',
    false,t+interval '1 second',10000,null,
    'test:target-recovery:failure-result','{}'::jsonb
  );

  -- Two later clean scheduled probes prove recovery.
  foreach request_id in array array[gen_random_uuid(),gen_random_uuid()] loop
    insert into foundation.defence_health_probe_requests(
      probe_request_id,target_id,target_version,external_request_id,target_url,
      queued_at,evidence_ref,metadata
    )
    select
      request_id,hp.target_id,hp.target_version,null,hp.target_url,
      case
        when not exists (
          select 1
          from foundation.defence_health_probe_requests q
          where q.evidence_ref='test:target-recovery:pass-1'
        ) then t+interval '5 minutes'
        else t+interval '10 minutes'
      end,
      case
        when not exists (
          select 1
          from foundation.defence_health_probe_requests q
          where q.evidence_ref='test:target-recovery:pass-1'
        ) then 'test:target-recovery:pass-1'
        else 'test:target-recovery:pass-2'
      end,
      '{}'::jsonb
    from foundation.current_defence_health_probe_target hp
    where hp.target_id=v_target;

    insert into foundation.defence_health_probe_results(
      probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
      response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
    )
    select
      request_id,v_target,200,false,null,true,
      q.queued_at+interval '1 second',500,null,
      replace(q.evidence_ref,'pass','pass-result'),'{}'::jsonb
    from foundation.defence_health_probe_requests q
    where q.probe_request_id=request_id;
  end loop;

  attention := jsonb_build_object(
    'defenceOperationalAttention','shine-defence/operational-attention-v1',
    'schemaVersion','1.4.0',
    'attentionState','attention_required',
    'rawEstateState','fail',
    'rawEstateStateOverridden',false,
    'rawHealthEvidencePreserved',true,
    'counts',jsonb_build_object(
      'targetSpecificTargets',1,
      'sharedTransportResidualTargets',0,
      'activeSharedClusters',0
    ),
    'estateItems','[]'::jsonb,
    'targetItems',jsonb_build_array(
      jsonb_build_object(
        'scope','target',
        'targetId',v_target,
        'appKeys',jsonb_build_array('translate'),
        'causeClass','target_specific',
        'healthState','degraded',
        'failureCount',1,
        'sampleCount',3,
        'windowStartedAt',t,
        'windowEndedAt',t+interval '10 minutes 1 second',
        'healthObservedAt',t+interval '11 minutes',
        'failedResults',1,
        'confirmedSharedFailures',0,
        'sharedClusterFailures',0,
        'targetSpecificFailures',1,
        'incidentState','fail',
        'incidentReason','health-unhealthy',
        'attentionClass','target_investigation',
        'nextAction','investigate_target_health',
        'rawHealthEvidencePreserved',true,
        'rawEstateStateOverridden',false
      )
    ),
    'queueItems','[]'::jsonb
  );

  select foundation.apply_defence_target_recovery_awareness_v1(
    attention,t+interval '12 minutes',2
  ) into result;

  select value into recovered_item
  from jsonb_array_elements(result->'targetItems')
  where value->>'targetId'=v_target;

  if result->>'schemaVersion'<>'1.5.0'
     or result->>'attentionState'<>'observe'
     or result#>>'{counts,targetSpecificTargets}'<>'1'
     or result#>>'{counts,targetSpecificRecoveredTargets}'<>'1'
     or result#>>'{counts,targetSpecificActionableTargets}'<>'0'
     or recovered_item->>'causeClass'<>'target_specific_recovered_residual'
     or recovered_item->>'attentionClass'<>'target_recovery_residual'
     or recovered_item->>'nextAction'<>'observe_residual_health_window'
     or recovered_item#>>'{recoveryEvidence,state}'<>'recovered'
     or recovered_item#>>'{recoveryEvidence,laterSampleCount}'<>'2'
     or recovered_item#>>'{recoveryEvidence,laterPassCount}'<>'2'
     or result#>>'{targetRecovery,rawEstateStateOverridden}'<>'false'
     or result#>>'{targetRecovery,automaticRestartAuthorized}'<>'false' then
    raise exception 'Recovered target-specific residual misclassified: %',result;
  end if;

  -- A newer failure invalidates recovery and restores actionable investigation.
  request_id := gen_random_uuid();
  insert into foundation.defence_health_probe_requests(
    probe_request_id,target_id,target_version,external_request_id,target_url,
    queued_at,evidence_ref,metadata
  )
  select
    request_id,hp.target_id,hp.target_version,null,hp.target_url,
    t+interval '15 minutes','test:target-recovery:failure-2','{}'::jsonb
  from foundation.current_defence_health_probe_target hp
  where hp.target_id=v_target;

  insert into foundation.defence_health_probe_results(
    probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
    response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
  )
  values(
    request_id,v_target,503,false,'health contract failed',false,
    t+interval '15 minutes 1 second',400,null,
    'test:target-recovery:failure-2-result','{}'::jsonb
  );

  attention := jsonb_set(
    attention,
    '{targetItems,0,windowEndedAt}',
    to_jsonb(t+interval '15 minutes 1 second')
  );

  select foundation.apply_defence_target_recovery_awareness_v1(
    attention,t+interval '16 minutes',2
  ) into result;

  select value into recovered_item
  from jsonb_array_elements(result->'targetItems')
  where value->>'targetId'=v_target;

  if result->>'attentionState'<>'attention_required'
     or recovered_item->>'causeClass'<>'target_specific'
     or recovered_item->>'attentionClass'<>'target_investigation'
     or recovered_item#>>'{recoveryEvidence,state}'<>'unproven'
     or result#>>'{counts,targetSpecificRecoveredTargets}'<>'0'
     or result#>>'{counts,targetSpecificActionableTargets}'<>'1' then
    raise exception 'Newer target failure incorrectly treated as recovered: %',result;
  end if;
end;
$target_recovery_fixture$;

do $target_recovery_security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_target_recovery_evidence_v1(text,timestamp with time zone,timestamp with time zone,timestamp with time zone,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.apply_defence_target_recovery_awareness_v1(jsonb,timestamp with time zone,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_operational_attention_recovery_aware_v1(timestamp with time zone,integer,integer,numeric,integer)',
       'EXECUTE'
     ) then
    raise exception 'Target recovery awareness privilege boundary invalid';
  end if;
end;
$target_recovery_security$;

do $target_recovery_invalid$
begin
  begin
    perform foundation.get_defence_target_recovery_evidence_v1(
      '',clock_timestamp(),clock_timestamp(),clock_timestamp(),2
    );
    raise exception 'Invalid empty target accepted';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform foundation.apply_defence_target_recovery_awareness_v1(
      '{}'::jsonb,clock_timestamp(),2
    );
    raise exception 'Invalid attention envelope accepted';
  exception
    when sqlstate '22023' then null;
  end;
end;
$target_recovery_invalid$;

rollback;
