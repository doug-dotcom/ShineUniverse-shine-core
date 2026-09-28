-- Foundation Layer 28: universal privileged route admission broker.
-- Resolves a live HTTP route to its registered operation policy before route execution.

create or replace function foundation.evaluate_gateway_route_policy_v1(
  p_http_method text,
  p_path text,
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $layer28$
declare
  v_route foundation.gateway_operation_contracts%rowtype;
  v_policy jsonb;
begin
  if upper(coalesce(p_http_method,'')) not in ('GET','POST')
     or p_path is null
     or p_path not like '/%' then
    return jsonb_build_object(
      'gatewayRoutePolicyResponse','shine-foundation/gateway-route-policy-response-v1',
      'schemaVersion','1.0.0',
      'policyState','unavailable',
      'reasonCode','invalid-route-policy-request'
    );
  end if;

  select * into v_route
  from foundation.current_gateway_operation_contracts c
  where c.service_id='foundation.gateway'
    and c.environment=p_environment
    and c.http_method=upper(p_http_method)
    and (
      p_path=c.path_template
      or p_path like '%/foundation-gateway' || c.path_template
    )
  limit 1;

  if v_route.operation_contract_id is null then
    return jsonb_build_object(
      'gatewayRoutePolicyResponse','shine-foundation/gateway-route-policy-response-v1',
      'schemaVersion','1.0.0',
      'environment',p_environment,
      'method',upper(p_http_method),
      'path',p_path,
      'policyState','not-registered',
      'reasonCode','operation-not-registered'
    );
  end if;

  v_policy := foundation.evaluate_gateway_operation_policy_v1(
    v_route.operation_key,
    p_environment,
    p_as_of
  );

  return jsonb_build_object(
    'gatewayRoutePolicyResponse','shine-foundation/gateway-route-policy-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'method',v_route.http_method,
    'path',v_route.path_template,
    'routeSymbol',v_route.route_symbol,
    'operationKey',v_route.operation_key,
    'riskClass',v_route.risk_class,
    'effectClass',v_route.effect_class,
    'policyState',coalesce(v_policy->>'policyState','unavailable'),
    'reasonCode',coalesce(v_policy->>'reasonCode','operation-policy-unavailable'),
    'policy',v_policy
  );
end;
$layer28$;

revoke all on function foundation.evaluate_gateway_route_policy_v1(text,text,text,timestamptz)
  from public,anon,authenticated;
grant execute on function foundation.evaluate_gateway_route_policy_v1(text,text,text,timestamptz)
  to foundation_runtime,foundation_gateway;
