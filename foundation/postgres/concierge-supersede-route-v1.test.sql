do $$
declare
  r foundation.gateway_operation_contracts%rowtype;
begin
  select * into r
  from foundation.current_gateway_operation_contracts
  where service_id='foundation.gateway'
    and environment='production'
    and route_symbol='conciergeSupersedePath';

  if r.operation_contract_id is null then
    raise exception 'concierge supersede route is not registered';
  end if;
  if r.http_method<>'POST'
     or r.path_template<>'/v1/concierge/supersede'
     or r.operation_key<>'concierge.cancel'
     or r.auth_class<>'user+client'
     or r.control_ref<>'foundation.cancel_concierge_request_v1' then
    raise exception 'concierge supersede route contract mismatch';
  end if;
end;
$$;
