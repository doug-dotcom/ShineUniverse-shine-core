insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  exemption_reason,source_ref,effective_at
)
select
  'foundation.gateway','production','1.0.0','conciergeSupersedePath','POST',
  '/v1/concierge/supersede','concierge.cancel','control-write','write',
  'user+client','service-guard','foundation.cancel_concierge_request_v1',
  null,'github:foundation/contracts/gateway-operation-registry-v1.json',clock_timestamp()
where not exists (
  select 1
  from foundation.current_gateway_operation_contracts
  where service_id='foundation.gateway'
    and environment='production'
    and route_symbol='conciergeSupersedePath'
    and contract_version='1.0.0'
);
