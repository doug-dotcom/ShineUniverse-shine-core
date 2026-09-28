begin;

-- Universal route admission depends on the live service-state contract.
-- Seed a fresh healthy Gateway window so this test isolates route-policy
-- behaviour instead of accidentally testing missing health evidence.
insert into foundation.service_health_evidence(
  service_id,environment,runtime_version,
  window_started_at,window_ended_at,
  request_count,response_4xx_count,response_5xx_count,
  avg_latency_ms,p95_latency_ms,runtime_error_count,
  evidence_source,evidence_ref,evidence_note,metadata,observed_at
)
values (
  'foundation.gateway','production','71',
  now()-interval '3 minutes',now(),
  100,0,0,
  100,150,0,
  'manual-verified',
  'test:layer28:gateway-healthy',
  'Synthetic fresh healthy Gateway evidence for universal route admission acceptance.',
  '{"test":true}'::jsonb,
  now()
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST',
    '/functions/v1/foundation-gateway/v1/grants/consent',
    'production',
    now()
  ) into v;

  if v->>'operationKey' <> 'grant.consent' then
    raise exception 'route broker should resolve grant.consent: %',v;
  end if;

  if v->>'policyState' not in ('admit','admit-degraded') then
    raise exception 'current grant consent route should be admitted: %',v;
  end if;

  select foundation.evaluate_gateway_route_policy_v1(
    'POST',
    '/v1/concierge/retry/claim',
    'production',
    now()
  ) into v;

  if v->>'policyState' <> 'worker-only' then
    raise exception 'worker retry route should remain worker-only: %',v;
  end if;

  select foundation.evaluate_gateway_route_policy_v1(
    'POST',
    '/v1/not-a-real-route',
    'production',
    now()
  ) into v;

  if v->>'policyState' <> 'not-registered' then
    raise exception 'unknown route should fall through as not registered: %',v;
  end if;
end;
$$;


insert into foundation.defence_posture_observations(
  observation_id,posture_version,environment,overall_state,
  observed_at,valid_until,checks,evidence_ref,recorded_at
)
values (
  gen_random_uuid(),'1.0.0','production','fail',
  now()+interval '10 seconds',
  now()+interval '30 minutes',
  '{"test":true}'::jsonb,
  'test:layer28:defence-fail',
  now()+interval '10 seconds'
);

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_gateway_route_policy_v1(
    'POST',
    '/foundation-gateway/v1/grants/consent',
    'production',
    now()+interval '11 seconds'
  ) into v;

  if v->>'policyState' <> 'deny' then
    raise exception 'failed Defence posture should deny privileged route: %',v;
  end if;

  if v->>'reasonCode' <> 'dependency-guarded' then
    raise exception 'route denial should preserve dependency reason: %',v;
  end if;

  select foundation.evaluate_gateway_route_policy_v1(
    'POST',
    '/foundation-gateway/v1/concierge/retry/claim',
    'production',
    now()+interval '11 seconds'
  ) into v;

  if v->>'policyState' <> 'worker-only' then
    raise exception 'worker-only route must not inherit user/app dependency denial: %',v;
  end if;
end;
$$;


do $$
begin
  if not has_function_privilege(
    'foundation_gateway',
    'foundation.evaluate_gateway_route_policy_v1(text,text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'foundation_gateway must execute route policy broker';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.evaluate_gateway_route_policy_v1(text,text,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute route policy broker';
  end if;
end;
$$;

set local role foundation_gateway;
select foundation.evaluate_gateway_route_policy_v1(
  'POST',
  '/v1/grants/revoke',
  'production',
  now()
);
reset role;

rollback;
