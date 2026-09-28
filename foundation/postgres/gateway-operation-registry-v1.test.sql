begin;

do $$
declare
  v jsonb;
begin
  select foundation.get_gateway_operation_registry_health_v1('production') into v;

  if v->>'state' <> 'pass' then
    raise exception 'production Gateway operation registry should pass: %',v;
  end if;

  if (v->>'routeCount')::integer <> 40 then
    raise exception 'production Gateway registry should contain 40 routes: %',v;
  end if;

  if (v->>'duplicateMethodPathCount')::integer <> 0 then
    raise exception 'Gateway registry must not contain duplicate method/path pairs: %',v;
  end if;

  if (v->>'invalidContractCount')::integer <> 0 then
    raise exception 'Gateway registry should have no invalid contracts: %',v;
  end if;

  if (v->>'missingAdmissionBindingCount')::integer <> 0 then
    raise exception 'dependency-admission routes must have live bindings: %',v;
  end if;

  if (v#>>'{controlModeCounts,dependency-admission}')::integer <> 1 then
    raise exception 'exactly one route should currently use dependency admission: %',v;
  end if;
end;
$$;


do $$
declare
  v jsonb;
begin
  select foundation.get_gateway_operation_inventory_v1('production') into v;

  if (v->>'routeCount')::integer <> 40 then
    raise exception 'Gateway inventory should expose all 40 routes: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'routes') x
    where x->>'operationKey'='access.evaluate'
      and x->>'controlMode'='dependency-admission'
      and x->>'path'='/v1/access/evaluate'
      and x->>'method'='POST'
  ) then
    raise exception 'access.evaluate registry contract missing or wrong: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'routes') x
    where x->>'operationKey'='grant.revoke'
      and x->>'effectClass'='write'
      and x->>'controlMode'='service-guard'
  ) then
    raise exception 'grant revoke route should be explicitly guarded: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'routes') x
    where x->>'routeSymbol'='conciergeSupersedePath'
      and x->>'operationKey'='concierge.cancel'
      and x->>'path'='/v1/concierge/supersede'
      and x->>'method'='POST'
      and x->>'authClass'='user+client'
      and x->>'controlMode'='service-guard'
      and x->>'controlRef'='foundation.cancel_concierge_request_v1'
  ) then
    raise exception 'Concierge supersede route contract missing or wrong: %',v;
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(v->'routes') x
    where x->>'operationKey'='gateway.health.read'
      and x->>'controlMode'='public-exempt'
      and x->>'effectClass'='read'
  ) then
    raise exception 'health route public exemption should be explicit: %',v;
  end if;
end;
$$;


insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','test-gap','1.0.0','testGapPath','POST','/test/gap',
  'test.gap.execute','protected-execution','execute','user+app',
  'dependency-admission','foundation.evaluate_service_admission_v1',
  'test:layer26:missing-binding',now()
);

do $$
declare
  v jsonb;
begin
  select foundation.get_gateway_operation_registry_health_v1('test-gap') into v;

  if v->>'state' <> 'fail' then
    raise exception 'missing admission binding should fail registry health: %',v;
  end if;

  if (v->>'missingAdmissionBindingCount')::integer <> 1 then
    raise exception 'missing admission binding count should be explicit: %',v;
  end if;
end;
$$;


do $$
begin
  begin
    insert into foundation.gateway_operation_contracts(
      service_id,environment,contract_version,route_symbol,http_method,path_template,
      operation_key,risk_class,effect_class,auth_class,control_mode,source_ref
    )
    values (
      'foundation.gateway','test-invalid','1.0.0','badPublicPath','POST','/bad/public',
      'bad.public.write','permission-write','write','public','public-exempt','test:invalid'
    );
    raise exception 'invalid public mutating exemption unexpectedly succeeded';
  exception
    when sqlstate '23514' then
      null;
  end;
end;
$$;


do $$
begin
  begin
    update foundation.gateway_operation_contracts
    set path_template='/mutated'
    where service_id='foundation.gateway'
      and environment='production'
      and route_symbol='healthPath';
    raise exception 'append-only Gateway operation mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;

  if has_table_privilege('anon','foundation.gateway_operation_contracts','SELECT') then
    raise exception 'anon must not read Gateway operation registry';
  end if;

  if not has_table_privilege('foundation_gateway','foundation.gateway_operation_contracts','SELECT') then
    raise exception 'foundation_gateway must read Gateway operation registry';
  end if;

  if not has_function_privilege(
    'foundation_gateway',
    'foundation.get_gateway_operation_registry_health_v1(text)',
    'EXECUTE'
  ) then
    raise exception 'foundation_gateway must execute operation registry health reader';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.get_gateway_operation_registry_health_v1(text)',
    'EXECUTE'
  ) then
    raise exception 'anon must not execute operation registry health reader';
  end if;
end;
$$;

rollback;
