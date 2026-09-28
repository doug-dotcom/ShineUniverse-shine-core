begin;

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
