begin;

do $$
declare
  v jsonb;
begin
  select foundation.get_service_deployment_truth_v1('foundation.gateway','production') into v;
  if v->>'truthState' <> 'aligned' then
    raise exception 'foundation.gateway should start aligned: %',v;
  end if;
  if v->>'healthState' <> 'unknown' then
    raise exception 'runtime active state must not be promoted to health: %',v;
  end if;
end;
$$;

insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,required_for_core
) values (
  'test.gateway','Test Gateway','shine-core','internal-service','test/deployment-truth-v1',false
);

insert into foundation.service_deployment_expectations(
  service_id,environment,expected_runtime_ref,expected_version,expected_state,evidence_ref
) values (
  'test.gateway','production','internal://test.gateway','1','active','test:expectation:v1'
);

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,runtime_state,health_state,observed_at,evidence_kind,evidence_ref
) values (
  'test.gateway','production','internal://test.gateway','1','active','healthy',now(),'manual-verified','test:observation:v1'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_deployment_truth_v1('test.gateway','production') into v;
  if v->>'truthState' <> 'aligned' or v->>'healthState' <> 'healthy' then
    raise exception 'matching expectation/observation should be aligned and healthy: %',v;
  end if;
end;
$$;

insert into foundation.service_deployment_observations(
  service_id,environment,runtime_ref,runtime_version,runtime_state,health_state,observed_at,evidence_kind,evidence_ref
) values (
  'test.gateway','production','internal://test.gateway','2','active','healthy',now()+interval '1 second','manual-verified','test:observation:v2'
);

do $$
declare
  v jsonb;
begin
  select foundation.get_service_deployment_truth_v1('test.gateway','production') into v;
  if v->>'truthState' <> 'drift' then
    raise exception 'newer mismatched observation should produce drift: %',v;
  end if;
  if not (v->'reasonCodes' ? 'version-mismatch') then
    raise exception 'version mismatch reason should be explicit: %',v;
  end if;
end;
$$;

do $$
begin
  begin
    update foundation.service_deployment_observations
       set evidence_note='mutation should fail'
     where service_id='test.gateway';
    raise exception 'append-only observation update unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

do $$
begin
  if has_table_privilege('anon','foundation.service_registry','SELECT') then
    raise exception 'anon must not have service registry SELECT';
  end if;
  if has_table_privilege('authenticated','foundation.service_deployment_observations','SELECT') then
    raise exception 'authenticated must not have deployment observation SELECT';
  end if;
  if not has_function_privilege('foundation_runtime','foundation.get_service_deployment_truth_v1(text,text)','EXECUTE') then
    raise exception 'foundation_runtime must be able to execute deployment truth reader';
  end if;
  if has_function_privilege('anon','foundation.get_service_deployment_truth_v1(text,text)','EXECUTE') then
    raise exception 'anon must not execute deployment truth reader';
  end if;
end;
$$;

set local role foundation_runtime;
select foundation.get_service_deployment_truth_v1('foundation.gateway','production');
reset role;

rollback;
