begin;

do $$
declare
  v_audit uuid := '29000000-0000-4000-8000-000000000001';
  v_request uuid := '29000000-0000-4000-8000-000000000101';
  v_policy jsonb;
  v_result jsonb;
  v_trace jsonb;
  v_policy_hash text;
  v_outcome_prev text;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/consent','production',now()
  ) into v_policy;

  if v_policy->>'policyState' not in ('admit','admit-degraded','deny','unavailable') then
    raise exception 'grant consent should resolve a dependency policy: %',v_policy;
  end if;

  select foundation.record_gateway_operation_audit_event_v1(
    v_audit,
    'policy',
    'POST',
    '/v1/grants/consent',
    'production',
    v_policy,
    null,
    null,
    null,
    now()-interval '1 second'
  ) into v_result;

  if v_result->>'status' <> 'recorded' then
    raise exception 'policy event should record: %',v_result;
  end if;

  select foundation.record_gateway_operation_audit_event_v1(
    v_audit,
    'policy',
    'POST',
    '/v1/grants/consent',
    'production',
    v_policy,
    null,
    null,
    null,
    now()-interval '1 second'
  ) into v_result;

  if v_result->>'status' <> 'replayed' then
    raise exception 'identical policy replay should be idempotent: %',v_result;
  end if;

  select foundation.record_gateway_operation_audit_event_v1(
    v_audit,
    'outcome',
    'POST',
    '/v1/grants/consent',
    'production',
    null,
    403,
    'test-denied',
    v_request::text,
    now()
  ) into v_result;

  if v_result->>'status' <> 'recorded' then
    raise exception 'outcome event should record: %',v_result;
  end if;

  select event_hash into v_policy_hash
  from foundation.gateway_operation_audit_events
  where operation_audit_id=v_audit and phase='policy';

  select previous_event_hash into v_outcome_prev
  from foundation.gateway_operation_audit_events
  where operation_audit_id=v_audit and phase='outcome';

  if v_policy_hash is null or char_length(v_policy_hash)<>64 then
    raise exception 'policy hash should be SHA-256';
  end if;

  if v_outcome_prev<>v_policy_hash then
    raise exception 'outcome event must chain to policy hash';
  end if;

  insert into foundation.grant_consent_events(
    consent_id,request_id,owner_shine_id,app_id,scope,purpose,
    resource_category,outcome,reason_code,grant_id,occurred_at
  )
  values (
    '29000000-0000-4000-8000-000000000201'::uuid,
    v_request,
    '29000000-0000-4000-8000-000000000301'::uuid,
    'test.layer29',
    'test.read',
    'layer29-audit-test',
    'test-resource',
    'denied',
    'test-denied',
    null,
    now()
  );

  select foundation.get_gateway_operation_audit_trace_v1(v_audit) into v_trace;

  if jsonb_array_length(v_trace->'events')<>2 then
    raise exception 'audit trace should contain policy and outcome: %',v_trace;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v_trace->'domainEvidence') x
    where x->>'source'='grant_consent_events'
      and x->>'reasonCode'='test-denied'
  ) then
    raise exception 'audit trace should link domain event evidence: %',v_trace;
  end if;
end;
$$;


do $audit_fallback$
declare
  v_audit uuid := '29000000-0000-4000-8000-000000000004';
  v_result jsonb;
  v_state text;
begin
  -- Canonical policy evidence must remain recordable even when the Edge driver
  -- omits or loses the optional policy snapshot. The recorder recomputes it
  -- authoritatively from route + timestamp.
  select foundation.record_gateway_operation_audit_event_v1(
    v_audit,
    'policy',
    'POST',
    '/v1/grants/consent',
    'production',
    null,
    null,
    null,
    null,
    now()
  ) into v_result;

  if v_result->>'status' <> 'recorded' then
    raise exception 'authoritative policy fallback should record: %',v_result;
  end if;

  select policy_state into v_state
  from foundation.gateway_operation_audit_events
  where operation_audit_id=v_audit
    and phase='policy';

  if v_state not in ('admit','admit-degraded','deny','unavailable') then
    raise exception 'authoritative policy fallback should resolve a real policy state: %',v_state;
  end if;
end;
$audit_fallback$;


do $audit_order$
declare
  v_audit uuid := '29000000-0000-4000-8000-000000000002';
begin
  begin
    perform foundation.record_gateway_operation_audit_event_v1(
      v_audit,
      'outcome',
      'POST',
      '/v1/grants/revoke',
      'production',
      null,
      403,
      'should-not-record',
      null,
      now()
    );
    raise exception 'outcome-before-policy unexpectedly succeeded';
  exception
    when others then
      if sqlerrm='outcome-before-policy unexpectedly succeeded' then
        raise;
      end if;
      if position('operation-audit-policy-event-missing' in sqlerrm)=0 then
        raise;
      end if;
  end;
end;
$audit_order$;


do $$
declare
  v_audit uuid := '29000000-0000-4000-8000-000000000003';
  v_policy jsonb;
  v_health jsonb;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST','/v1/grants/revoke','production',now()
  ) into v_policy;

  perform foundation.record_gateway_operation_audit_event_v1(
    v_audit,
    'policy',
    'POST',
    '/v1/grants/revoke',
    'production',
    v_policy,
    null,
    null,
    null,
    now()-interval '10 minutes'
  );

  select foundation.get_gateway_operation_audit_health_v1('production',300) into v_health;

  if v_health->>'state' <> 'degraded' then
    raise exception 'stale policy-only trace should degrade audit health: %',v_health;
  end if;

  if (v_health->>'openTraceCount')::integer < 1 then
    raise exception 'open audit trace count should be explicit: %',v_health;
  end if;
end;
$$;


do $$
begin
  begin
    update foundation.gateway_operation_audit_events
    set response_reason_code='mutation'
    where operation_audit_id='29000000-0000-4000-8000-000000000001'::uuid
      and phase='outcome';
    raise exception 'append-only audit mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;

  if has_table_privilege(
    'foundation_gateway',
    'foundation.gateway_operation_audit_events',
    'INSERT'
  ) then
    raise exception 'foundation_gateway must not have direct audit table INSERT';
  end if;

  if not has_function_privilege(
    'foundation_gateway',
    'foundation.record_gateway_operation_audit_event_v1(uuid,text,text,text,text,jsonb,integer,text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_gateway must execute narrow audit recorder';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.record_gateway_operation_audit_event_v1(uuid,text,text,text,text,jsonb,integer,text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute audit recorder';
  end if;

  if has_table_privilege(
    'anon',
    'foundation.gateway_operation_audit_events',
    'SELECT'
  ) then
    raise exception 'anon must not read privileged operation audit';
  end if;
end;
$$;

rollback;
