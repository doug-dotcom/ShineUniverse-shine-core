begin;

do $scheduler_classifier$
declare
  t timestamptz := '2099-04-01T00:00:00Z';
begin
  if foundation.classify_defence_scheduler_age_v1(null,t,1800,7200)<>'missing' then
    raise exception 'Null scheduler observation not classified missing';
  end if;
  if foundation.classify_defence_scheduler_age_v1(t-interval '10 minutes',t,1800,7200)<>'current' then
    raise exception 'Fresh scheduler observation not classified current';
  end if;
  if foundation.classify_defence_scheduler_age_v1(t-interval '45 minutes',t,1800,7200)<>'delayed' then
    raise exception 'Delayed scheduler observation not classified delayed';
  end if;
  if foundation.classify_defence_scheduler_age_v1(t-interval '3 hours',t,1800,7200)<>'silent' then
    raise exception 'Silent scheduler observation not classified silent';
  end if;
  if foundation.classify_defence_scheduler_age_v1(t+interval '1 minute',t,1800,7200)<>'invalid_future' then
    raise exception 'Future scheduler observation not fail-closed';
  end if;
end;
$scheduler_classifier$;

do $scheduler_contract$
declare
  v jsonb;
begin
  select foundation.get_defence_control_scheduler_liveness_v1(
    clock_timestamp(),1800,7200
  ) into v;

  if v->>'defenceControlSchedulerLiveness'<>
       'shine-defence/control-scheduler-liveness-v1'
     or v->>'schemaVersion'<>'1.0.0'
     or v->>'schedulerIsEvidenceSource'<>'false'
     or v->>'refreshesProof'<>'false'
     or v->>'extendsProofTtl'<>'false'
     or v->>'mintsAuthorityState'<>'false'
     or v->>'rawEstateStateOverridden'<>'false'
     or v->>'releaseAdmissionOverridden'<>'false'
     or v->>'rollbackReadinessOverridden'<>'false'
     or jsonb_typeof(v->'targetSchedules')<>'object'
     or jsonb_typeof(v->'authoritySchedule')<>'object' then
    raise exception 'Scheduler liveness contract invalid: %',v;
  end if;
end;
$scheduler_contract$;

do $scheduler_security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_control_scheduler_liveness_v1(timestamp with time zone,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_control_scheduler_liveness_v1(timestamp with time zone,integer,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_control_scheduler_liveness_v1(timestamp with time zone,integer,integer)',
       'EXECUTE'
     ) then
    raise exception 'Scheduler liveness privilege boundary invalid';
  end if;
end;
$scheduler_security$;

do $scheduler_invalid$
begin
  begin
    perform foundation.get_defence_control_scheduler_liveness_v1(
      clock_timestamp(),120,7200
    );
    raise exception 'Invalid scheduler warning threshold accepted';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform foundation.get_defence_control_scheduler_liveness_v1(
      clock_timestamp(),1800,1700
    );
    raise exception 'Invalid scheduler critical threshold accepted';
  exception
    when sqlstate '22023' then null;
  end;
end;
$scheduler_invalid$;

rollback;
