-- Foundation Layer 27: scope-aware operation admission policy coverage.
-- Keeps atomic service guards intact while adding dependency admission ahead of privileged operations.

create or replace view foundation.current_service_dependencies
with (security_invoker=true)
as
select distinct on (dependent_service_id,dependency_service_id,environment,impact_scope)
  dependency_id,
  dependent_service_id,
  dependency_service_id,
  environment,
  dependency_version,
  dependency_type,
  impact_scope,
  failure_mode,
  description,
  active,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.service_dependencies
order by
  dependent_service_id,
  dependency_service_id,
  environment,
  impact_scope,
  effective_at desc,
  recorded_at desc,
  dependency_id desc;

revoke all on foundation.current_service_dependencies from public,anon,authenticated;
grant select on foundation.current_service_dependencies to foundation_runtime;


create table foundation.gateway_operation_policies (
  operation_policy_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  operation_key text not null
    check (operation_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  policy_version text not null,
  policy_mode text not null
    check (policy_mode in ('dependency-admission','worker-only')),
  impact_scope text
    check (impact_scope is null or impact_scope ~ '^[a-z0-9][a-z0-9._:-]*$'),
  failure_behavior text not null
    check (failure_behavior in ('fail-closed','worker-auth-only')),
  execution_guard_ref text not null,
  enabled boolean not null default true,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  unique(service_id,environment,operation_key,policy_version),
  check (
    (policy_mode='dependency-admission' and impact_scope is not null and failure_behavior='fail-closed')
    or
    (policy_mode='worker-only' and impact_scope is null and failure_behavior='worker-auth-only')
  )
);

alter table foundation.gateway_operation_policies enable row level security;

create policy foundation_runtime_gateway_operation_policies_select
on foundation.gateway_operation_policies
for select
to foundation_runtime
using (true);

revoke all on foundation.gateway_operation_policies from public,anon,authenticated;
grant select on foundation.gateway_operation_policies to foundation_runtime;
grant select,insert on foundation.gateway_operation_policies to service_role;

create index gateway_operation_policies_current_idx
  on foundation.gateway_operation_policies(
    service_id,environment,operation_key,effective_at desc,recorded_at desc
  );

create trigger gateway_operation_policies_append_only
before update or delete on foundation.gateway_operation_policies
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_gateway_operation_policies
with (security_invoker=true)
as
select distinct on (service_id,environment,operation_key)
  operation_policy_id,
  service_id,
  environment,
  operation_key,
  policy_version,
  policy_mode,
  impact_scope,
  failure_behavior,
  execution_guard_ref,
  enabled,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.gateway_operation_policies
order by
  service_id,environment,operation_key,
  effective_at desc,recorded_at desc,operation_policy_id desc;

revoke all on foundation.current_gateway_operation_policies from public,anon,authenticated;
grant select on foundation.current_gateway_operation_policies to foundation_runtime;


create or replace function foundation.evaluate_gateway_operation_policy_v1(
  p_operation_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, foundation
as $operation_policy$
declare
  v_route foundation.gateway_operation_contracts%rowtype;
  v_policy foundation.gateway_operation_policies%rowtype;
  v_admission jsonb;
begin
  select * into v_route
  from foundation.current_gateway_operation_contracts
  where service_id='foundation.gateway'
    and environment=p_environment
    and operation_key=p_operation_key;

  if v_route.operation_contract_id is null then
    return jsonb_build_object(
      'gatewayOperationPolicyResponse','shine-foundation/gateway-operation-policy-response-v1',
      'schemaVersion','1.0.0',
      'operationKey',p_operation_key,
      'environment',p_environment,
      'policyState','unavailable',
      'reasonCode','operation-not-registered'
    );
  end if;

  if v_route.effect_class='read' then
    return jsonb_build_object(
      'gatewayOperationPolicyResponse','shine-foundation/gateway-operation-policy-response-v1',
      'schemaVersion','1.0.0',
      'operationKey',p_operation_key,
      'environment',p_environment,
      'policyState','not-required',
      'reasonCode','read-route-policy-not-required',
      'route',jsonb_build_object(
        'method',v_route.http_method,
        'path',v_route.path_template,
        'controlMode',v_route.control_mode,
        'controlRef',v_route.control_ref
      )
    );
  end if;

  select * into v_policy
  from foundation.current_gateway_operation_policies
  where service_id='foundation.gateway'
    and environment=p_environment
    and operation_key=p_operation_key;

  if v_policy.operation_policy_id is null or not v_policy.enabled then
    return jsonb_build_object(
      'gatewayOperationPolicyResponse','shine-foundation/gateway-operation-policy-response-v1',
      'schemaVersion','1.0.0',
      'operationKey',p_operation_key,
      'environment',p_environment,
      'policyState','unavailable',
      'reasonCode',case
        when v_policy.operation_policy_id is null then 'operation-policy-missing'
        else 'operation-policy-disabled'
      end,
      'route',jsonb_build_object(
        'method',v_route.http_method,
        'path',v_route.path_template,
        'riskClass',v_route.risk_class,
        'effectClass',v_route.effect_class
      )
    );
  end if;

  if v_policy.policy_mode='worker-only' then
    return jsonb_build_object(
      'gatewayOperationPolicyResponse','shine-foundation/gateway-operation-policy-response-v1',
      'schemaVersion','1.0.0',
      'operationKey',p_operation_key,
      'environment',p_environment,
      'policyState','worker-only',
      'reasonCode','worker-auth-required',
      'policyMode',v_policy.policy_mode,
      'executionGuardRef',v_policy.execution_guard_ref,
      'policyEvidenceRef',v_policy.evidence_ref
    );
  end if;

  v_admission := foundation.evaluate_service_admission_v1(
    'foundation.gateway',p_environment,p_operation_key,p_as_of
  );

  return jsonb_build_object(
    'gatewayOperationPolicyResponse','shine-foundation/gateway-operation-policy-response-v1',
    'schemaVersion','1.0.0',
    'operationKey',p_operation_key,
    'environment',p_environment,
    'policyState',coalesce(v_admission->>'admissionState','unavailable'),
    'reasonCode',coalesce(v_admission->>'reasonCode','dependency-admission-unavailable'),
    'policyMode',v_policy.policy_mode,
    'impactScope',v_policy.impact_scope,
    'failureBehavior',v_policy.failure_behavior,
    'executionGuardRef',v_policy.execution_guard_ref,
    'policyEvidenceRef',v_policy.evidence_ref,
    'admission',v_admission
  );
end;
$operation_policy$;

revoke all on function foundation.evaluate_gateway_operation_policy_v1(text,text,timestamptz)
  from public,anon,authenticated;
grant execute on function foundation.evaluate_gateway_operation_policy_v1(text,text,timestamptz)
  to foundation_runtime,foundation_gateway;


create or replace function foundation.get_gateway_operation_policy_coverage_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_privileged integer;
  v_covered integer;
  v_missing integer;
  v_binding_missing integer;
  v_scope_missing integer;
  v_worker_count integer;
  v_admission_count integer;
  v_state text;
begin
  select count(*) into v_privileged
  from foundation.current_gateway_operation_contracts
  where service_id='foundation.gateway'
    and environment=p_environment
    and effect_class<>'read';

  select count(*) into v_covered
  from foundation.current_gateway_operation_contracts r
  join foundation.current_gateway_operation_policies p
    on p.service_id=r.service_id
   and p.environment=r.environment
   and p.operation_key=r.operation_key
   and p.enabled=true
  where r.service_id='foundation.gateway'
    and r.environment=p_environment
    and r.effect_class<>'read';

  v_missing := v_privileged-v_covered;

  select count(*) into v_binding_missing
  from foundation.current_gateway_operation_policies p
  where p.service_id='foundation.gateway'
    and p.environment=p_environment
    and p.policy_mode='dependency-admission'
    and p.enabled=true
    and not exists (
      select 1
      from foundation.current_service_admission_bindings b
      where b.service_id=p.service_id
        and b.environment=p.environment
        and b.operation=p.operation_key
        and b.impact_scope=p.impact_scope
        and b.enabled=true
    );

  select count(*) into v_scope_missing
  from foundation.current_gateway_operation_policies p
  where p.service_id='foundation.gateway'
    and p.environment=p_environment
    and p.policy_mode='dependency-admission'
    and p.enabled=true
    and not exists (
      select 1
      from foundation.current_service_dependencies d
      where d.dependent_service_id=p.service_id
        and d.environment=p.environment
        and d.impact_scope=p.impact_scope
        and d.active=true
    );

  select count(*) filter (where policy_mode='worker-only'),
         count(*) filter (where policy_mode='dependency-admission')
    into v_worker_count,v_admission_count
  from foundation.current_gateway_operation_policies
  where service_id='foundation.gateway'
    and environment=p_environment
    and enabled=true;

  v_state := case
    when v_privileged=0 then 'fail'
    when v_missing>0 then 'fail'
    when v_binding_missing>0 then 'fail'
    when v_scope_missing>0 then 'fail'
    else 'pass'
  end;

  return jsonb_build_object(
    'gatewayOperationPolicyCoverageResponse','shine-foundation/gateway-operation-policy-coverage-response-v1',
    'schemaVersion','1.0.0',
    'serviceId','foundation.gateway',
    'environment',p_environment,
    'state',v_state,
    'privilegedOperationCount',v_privileged,
    'coveredOperationCount',v_covered,
    'missingPolicyCount',v_missing,
    'missingAdmissionBindingCount',v_binding_missing,
    'missingDependencyScopeCount',v_scope_missing,
    'dependencyAdmissionPolicyCount',coalesce(v_admission_count,0),
    'workerOnlyPolicyCount',coalesce(v_worker_count,0)
  );
end;
$$;

revoke all on function foundation.get_gateway_operation_policy_coverage_v1(text)
  from public,anon,authenticated;
grant execute on function foundation.get_gateway_operation_policy_coverage_v1(text)
  to foundation_runtime;


-- Add scope-aware Defence guard edges. The existing protected-operations edge remains valid.
insert into foundation.service_dependencies(
  dependent_service_id,dependency_service_id,environment,dependency_version,
  dependency_type,impact_scope,failure_mode,description,active,
  effective_at,evidence_ref,evidence_note
)
values
  (
    'foundation.gateway','foundation.defence','production','1.1.0-permission',
    'guard','permission-operations','fail-closed',
    'Permission mutations depend on current Shine Defence posture.',true,
    now(),'foundation:dependency:gateway:defence:permission:v1',
    'Scope-aware Layer 27 Defence guard.'
  ),
  (
    'foundation.gateway','foundation.defence','production','1.1.0-credential',
    'guard','credential-operations','fail-closed',
    'Credential issuance/rotation depends on current Shine Defence posture.',true,
    now(),'foundation:dependency:gateway:defence:credential:v1',
    'Scope-aware Layer 27 Defence guard.'
  ),
  (
    'foundation.gateway','foundation.defence','production','1.1.0-identity',
    'guard','identity-operations','fail-closed',
    'Canonical identity mutation depends on current Shine Defence posture.',true,
    now(),'foundation:dependency:gateway:defence:identity:v1',
    'Scope-aware Layer 27 Defence guard.'
  ),
  (
    'foundation.gateway','foundation.defence','production','1.1.0-context',
    'guard','context-operations','fail-closed',
    'Context publication depends on current Shine Defence posture.',true,
    now(),'foundation:dependency:gateway:defence:context:v1',
    'Scope-aware Layer 27 Defence guard.'
  ),
  (
    'foundation.gateway','foundation.defence','production','1.1.0-control',
    'guard','control-operations','fail-closed',
    'Privileged control mutations depend on current Shine Defence posture.',true,
    now(),'foundation:dependency:gateway:defence:control:v1',
    'Scope-aware Layer 27 Defence guard.'
  )
on conflict do nothing;


-- Add admission bindings for every privileged non-worker route.
with payload as (
  select *
  from jsonb_to_recordset('[{"operationKey":"access.evaluate","impactScope":"protected-operations"},{"operationKey":"capability.ticket.redeem","impactScope":"protected-operations"},{"operationKey":"concierge.plan","impactScope":"protected-operations"},{"operationKey":"concierge.execute","impactScope":"protected-operations"},{"operationKey":"concierge.resume","impactScope":"protected-operations"},{"operationKey":"grant.consent","impactScope":"permission-operations"},{"operationKey":"grant.revoke","impactScope":"permission-operations"},{"operationKey":"integration.device-link.approve","impactScope":"permission-operations"},{"operationKey":"integration.grant.consent","impactScope":"permission-operations"},{"operationKey":"integration.grant.revoke","impactScope":"permission-operations"},{"operationKey":"integration.link.consent","impactScope":"permission-operations"},{"operationKey":"integration.link.revoke","impactScope":"permission-operations"},{"operationKey":"integration.user-grant.revoke","impactScope":"permission-operations"},{"operationKey":"integration.user-link.revoke","impactScope":"permission-operations"},{"operationKey":"integration.device-link.request","impactScope":"credential-operations"},{"operationKey":"integration.device-link.exchange","impactScope":"credential-operations"},{"operationKey":"integration.delegation.refresh","impactScope":"credential-operations"},{"operationKey":"identity.claim","impactScope":"identity-operations"},{"operationKey":"integration.context.publish","impactScope":"context-operations"},{"operationKey":"concierge.cancel","impactScope":"control-operations"},{"operationKey":"revocation.ack","impactScope":"control-operations"}]'::jsonb) as x(
    "operationKey" text,
    "impactScope" text
  )
)
insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
select
  'foundation.gateway',
  'production',
  "operationKey",
  case
    when "operationKey"='access.evaluate' then '1.0.0'
    else '2.0.0'
  end,
  "impactScope",
  true,
  now(),
  'foundation:admission-binding:gateway:' || replace("operationKey",'.','-') || ':v2',
  'Layer 27 scope-aware privileged operation admission binding.'
from payload
where not (
  "operationKey"='access.evaluate'
  and exists (
    select 1 from foundation.service_admission_bindings
    where service_id='foundation.gateway'
      and environment='production'
      and operation='access.evaluate'
      and binding_version='1.0.0'
  )
)
on conflict do nothing;


-- Persist policies for all privileged operations while preserving the atomic execution guard behind admission.
with policy_source as (
  select
    r.operation_key,
    case
      when r.operation_key='access.evaluate'
        then 'gateway-core:permission-engine+runtime-defence'
      else r.control_ref
    end as execution_guard_ref,
    case
      when r.operation_key in ('concierge.retry.claim','concierge.retry.finish')
        then 'worker-only'
      else 'dependency-admission'
    end as policy_mode,
    case
      when r.operation_key in ('concierge.retry.claim','concierge.retry.finish')
        then null
      when r.operation_key in ('access.evaluate','capability.ticket.redeem','concierge.plan','concierge.execute','concierge.resume')
        then 'protected-operations'
      when r.operation_key in (
        'grant.consent','grant.revoke','integration.device-link.approve',
        'integration.grant.consent','integration.grant.revoke',
        'integration.link.consent','integration.link.revoke',
        'integration.user-grant.revoke','integration.user-link.revoke'
      ) then 'permission-operations'
      when r.operation_key in (
        'integration.device-link.request','integration.device-link.exchange','integration.delegation.refresh'
      ) then 'credential-operations'
      when r.operation_key='identity.claim' then 'identity-operations'
      when r.operation_key='integration.context.publish' then 'context-operations'
      when r.operation_key in ('concierge.cancel','revocation.ack') then 'control-operations'
      else null
    end as impact_scope
  from foundation.current_gateway_operation_contracts r
  where r.service_id='foundation.gateway'
    and r.environment='production'
    and r.effect_class<>'read'
)
insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
select
  'foundation.gateway',
  'production',
  operation_key,
  '1.0.0',
  policy_mode,
  impact_scope,
  case when policy_mode='worker-only' then 'worker-auth-only' else 'fail-closed' end,
  execution_guard_ref,
  true,
  now(),
  'foundation:operation-policy:gateway:' || replace(operation_key,'.','-') || ':v1',
  case
    when policy_mode='worker-only'
      then 'Internal worker operation remains client-authenticated and is not exposed as user/app dependency admission.'
    else 'Privileged operation requires scope-aware dependency admission before its existing atomic execution guard.'
  end
from policy_source
where impact_scope is not null or policy_mode='worker-only'
on conflict do nothing;
