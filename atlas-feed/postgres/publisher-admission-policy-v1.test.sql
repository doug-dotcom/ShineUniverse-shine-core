begin;

do $$
declare
  registry jsonb;
  coverage jsonb;
  policy jsonb;
begin
  select foundation.get_gateway_operation_registry_health_v1('production') into registry;
  if registry->>'state' <> 'pass' then
    raise exception 'Atlas Feed route registration should keep Gateway registry healthy: %',registry;
  end if;
  if (registry->>'routeCount')::integer <> 41 then
    raise exception 'Atlas Feed Layer 2 should extend Gateway to 41 routes: %',registry;
  end if;

  select foundation.get_gateway_operation_policy_coverage_v1('production') into coverage;
  if coverage->>'state' <> 'pass' then
    raise exception 'Atlas Feed policy extension should keep coverage healthy: %',coverage;
  end if;
  if (coverage->>'privilegedOperationCount')::integer <> 25
     or (coverage->>'coveredOperationCount')::integer <> 25 then
    raise exception 'Atlas Feed Layer 2 should extend privileged route coverage to 25: %',coverage;
  end if;
  if (coverage->>'dependencyAdmissionPolicyCount')::integer <> 22
     or (coverage->>'workerOnlyPolicyCount')::integer <> 2 then
    raise exception 'Atlas Feed Layer 2 should produce 22 dependency policies + 2 worker policies: %',coverage;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'atlas-feed.publish.admit','production',now()
  ) into policy;

  if policy->>'impactScope' <> 'context-operations' then
    raise exception 'Atlas publisher policy must use context-operations: %',policy;
  end if;
  if policy->>'executionGuardRef' <> 'atlas-feed.publisher-admission-v1' then
    raise exception 'Atlas publisher policy lost its execution guard: %',policy;
  end if;
  if policy->>'policyState' not in ('admit','admit-degraded','deny','unavailable') then
    raise exception 'Atlas publisher policy must resolve through dependency admission: %',policy;
  end if;
  if policy->>'policyState'='unavailable' and policy->>'reasonCode' is null then
    raise exception 'unavailable Atlas publisher policy must preserve its fail-closed reason: %',policy;
  end if;
end;
$$;

rollback;
