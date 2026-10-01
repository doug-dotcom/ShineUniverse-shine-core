begin;

do $transport_recurrence_fixture$
declare
  t timestamptz := '2099-02-01T00:00:00Z';
  target_ids text[] := array[
    'railway:daash','railway:dive','railway:fiona','railway:project-l'
  ];
  cycle_offset integer;
  v_target_id text;
  request_id uuid;
  sentinel jsonb;
begin
  -- Three qualifying shared transport cycles: three TLS transport failures and
  -- one passing target in each cycle.
  foreach cycle_offset in array array[0,5,10] loop
    foreach v_target_id in array target_ids loop
      request_id := gen_random_uuid();
      insert into foundation.defence_health_probe_requests(
        probe_request_id,target_id,target_version,external_request_id,target_url,
        queued_at,evidence_ref,metadata
      )
      select
        request_id,hp.target_id,hp.target_version,null,hp.target_url,
        t+make_interval(mins=>cycle_offset),
        'test:transport-recurrence:event:'||cycle_offset||':'||hp.target_id,
        '{}'::jsonb
      from foundation.current_defence_health_probe_target hp
      where hp.target_id=v_target_id;

      insert into foundation.defence_health_probe_results(
        probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
        response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
      )
      values(
        request_id,
        v_target_id,
        case when v_target_id='railway:project-l' then 200 else null end,
        v_target_id<>'railway:project-l',
        case
          when v_target_id='railway:project-l' then null
          else 'Timeout of 10000 ms reached. TCP/SSL handshake time: 9300 ms'
        end,
        v_target_id='railway:project-l',
        t+make_interval(mins=>cycle_offset)+interval '1 second',
        1000,
        null,
        'test:transport-recurrence:event-result:'||cycle_offset||':'||v_target_id,
        '{}'::jsonb
      );
    end loop;
  end loop;

  -- A mixed cycle has the same transport cluster plus a genuine HTTP contract
  -- failure. It must remain visible in raw evidence but must not count as a
  -- shared-transport recurrence cycle.
  foreach v_target_id in array target_ids loop
    request_id := gen_random_uuid();
    insert into foundation.defence_health_probe_requests(
      probe_request_id,target_id,target_version,external_request_id,target_url,
      queued_at,evidence_ref,metadata
    )
    select
      request_id,hp.target_id,hp.target_version,null,hp.target_url,
      t+interval '15 minutes',
      'test:transport-recurrence:mixed:'||hp.target_id,
      '{}'::jsonb
    from foundation.current_defence_health_probe_target hp
    where hp.target_id=v_target_id;

    insert into foundation.defence_health_probe_results(
      probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
      response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
    )
    values(
      request_id,
      v_target_id,
      case
        when v_target_id='railway:project-l' then 503
        else null
      end,
      v_target_id<>'railway:project-l',
      case
        when v_target_id='railway:project-l' then 'health contract failed'
        else 'Timeout of 10000 ms reached. TCP/SSL handshake time: 9300 ms'
      end,
      false,
      t+interval '15 minutes 1 second',
      1000,
      null,
      'test:transport-recurrence:mixed-result:'||v_target_id,
      '{}'::jsonb
    );
  end loop;

  select foundation.get_defence_transport_recurrence_sentinel_v1(
    t+interval '17 minutes',3600,3,0.5,3
  ) into sentinel;

  if sentinel->>'state'<>'recurrent'
     or sentinel->>'reasonCode'<>'shared-transport-recurrence-detected'
     or (sentinel->>'qualifyingCycleCount')::integer<>3
     or (sentinel->>'tlsDominantCycleCount')::integer<>3
     or sentinel->>'latestEventState'<>'active'
     or sentinel->>'rawHealthEvidencePreserved'<>'true'
     or sentinel->>'rawEstateStateOverridden'<>'false'
     or sentinel->>'targetSpecificFailuresExcludedFromQualification'<>'true'
     or sentinel->>'automaticRetryAuthorized'<>'false'
     or sentinel->>'automaticRestartAuthorized'<>'false' then
    raise exception 'Transport recurrence sentinel misclassified recurrence: %',sentinel;
  end if;

  -- Full-pass recovery changes only the latest event state; recurrence history
  -- remains visible for the lookback window.
  foreach v_target_id in array target_ids loop
    request_id := gen_random_uuid();
    insert into foundation.defence_health_probe_requests(
      probe_request_id,target_id,target_version,external_request_id,target_url,
      queued_at,evidence_ref,metadata
    )
    select
      request_id,hp.target_id,hp.target_version,null,hp.target_url,
      t+interval '20 minutes',
      'test:transport-recurrence:recovery:'||hp.target_id,
      '{}'::jsonb
    from foundation.current_defence_health_probe_target hp
    where hp.target_id=v_target_id;

    insert into foundation.defence_health_probe_results(
      probe_request_id,target_id,http_status,timed_out,error_message,contract_ok,
      response_at,roundtrip_ms,response_sha256,evidence_ref,metadata
    )
    values(
      request_id,v_target_id,200,false,null,true,
      t+interval '20 minutes 1 second',500,null,
      'test:transport-recurrence:recovery-result:'||v_target_id,
      '{}'::jsonb
    );
  end loop;

  select foundation.get_defence_transport_recurrence_sentinel_v1(
    t+interval '22 minutes',3600,3,0.5,3
  ) into sentinel;

  if sentinel->>'state'<>'recurrent'
     or sentinel->>'latestEventState'<>'recovered'
     or (sentinel#>>'{latestRecovery,passCount}')::integer<>4 then
    raise exception 'Transport recurrence recovery misclassified: %',sentinel;
  end if;
end;
$transport_recurrence_fixture$;

do $transport_recurrence_security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_transport_recurrence_sentinel_v1(timestamp with time zone,integer,integer,numeric,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_transport_recurrence_sentinel_v1(timestamp with time zone,integer,integer,numeric,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_transport_recurrence_sentinel_v1(timestamp with time zone,integer,integer,numeric,integer)',
       'EXECUTE'
     ) then
    raise exception 'Transport recurrence sentinel privilege boundary invalid';
  end if;
end;
$transport_recurrence_security$;

do $transport_recurrence_invalid$
begin
  begin
    perform foundation.get_defence_transport_recurrence_sentinel_v1(
      clock_timestamp(),300,3,0.5,3
    );
    raise exception 'Invalid transport recurrence lookback accepted';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform foundation.get_defence_transport_recurrence_sentinel_v1(
      clock_timestamp(),3600,3,0.5,1
    );
    raise exception 'Invalid transport recurrence threshold accepted';
  exception
    when sqlstate '22023' then null;
  end;
end;
$transport_recurrence_invalid$;

rollback;
