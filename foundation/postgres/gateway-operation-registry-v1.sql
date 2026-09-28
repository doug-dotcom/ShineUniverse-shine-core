-- Foundation Layer 26: Gateway operation registry and route-drift control.

create table foundation.gateway_operation_contracts (
  operation_contract_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  contract_version text not null,
  route_symbol text not null
    check (route_symbol ~ '^[A-Za-z][A-Za-z0-9_]*(Path|Match)$'),
  http_method text not null
    check (http_method in ('GET','POST')),
  path_template text not null
    check (path_template like '/%'),
  operation_key text not null
    check (operation_key ~ '^[a-z0-9][a-z0-9._:-]*$'),
  risk_class text not null
    check (risk_class in (
      'public-read','authenticated-read','identity-write','permission-write',
      'credential-write','protected-execution','control-write','worker-control','context-write'
    )),
  effect_class text not null
    check (effect_class in ('read','write','execute','credential')),
  auth_class text not null,
  control_mode text not null
    check (control_mode in (
      'public-exempt','auth-only','service-guard','internal-worker','dependency-admission'
    )),
  control_ref text,
  exemption_reason text,
  source_ref text not null,
  effective_at timestamptz not null default now(),
  recorded_at timestamptz not null default now(),
  unique(service_id,environment,route_symbol,contract_version),
  check (
    control_mode <> 'public-exempt'
    or (effect_class='read' and auth_class='public' and exemption_reason is not null)
  ),
  check (
    control_mode <> 'auth-only'
    or effect_class='read'
  ),
  check (
    effect_class='read'
    or control_ref is not null
  ),
  check (
    risk_class <> 'protected-execution'
    or auth_class <> 'public'
  )
);

alter table foundation.gateway_operation_contracts enable row level security;

create policy foundation_runtime_gateway_operation_contracts_select
on foundation.gateway_operation_contracts
for select
to foundation_runtime
using (true);

revoke all on foundation.gateway_operation_contracts from public,anon,authenticated;
grant select on foundation.gateway_operation_contracts to foundation_runtime,foundation_gateway;
grant select,insert on foundation.gateway_operation_contracts to service_role;

create index gateway_operation_contracts_current_idx
  on foundation.gateway_operation_contracts(
    service_id,environment,route_symbol,effective_at desc,recorded_at desc
  );

create index gateway_operation_contracts_operation_idx
  on foundation.gateway_operation_contracts(
    service_id,environment,operation_key,effective_at desc
  );

create trigger gateway_operation_contracts_append_only
before update or delete on foundation.gateway_operation_contracts
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_gateway_operation_contracts
with (security_invoker=true)
as
select distinct on (service_id,environment,route_symbol)
  operation_contract_id,
  service_id,
  environment,
  contract_version,
  route_symbol,
  http_method,
  path_template,
  operation_key,
  risk_class,
  effect_class,
  auth_class,
  control_mode,
  control_ref,
  exemption_reason,
  source_ref,
  effective_at,
  recorded_at
from foundation.gateway_operation_contracts
order by
  service_id,environment,route_symbol,
  effective_at desc,recorded_at desc,operation_contract_id desc;

revoke all on foundation.current_gateway_operation_contracts from public,anon,authenticated;
grant select on foundation.current_gateway_operation_contracts to foundation_runtime,foundation_gateway;


create or replace function foundation.get_gateway_operation_inventory_v1(
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
  select jsonb_build_object(
    'gatewayOperationInventoryResponse','shine-foundation/gateway-operation-inventory-response-v1',
    'schemaVersion','1.0.0',
    'serviceId','foundation.gateway',
    'environment',p_environment,
    'routeCount',count(*),
    'routes',coalesce(jsonb_agg(jsonb_build_object(
      'routeSymbol',route_symbol,
      'method',http_method,
      'path',path_template,
      'operationKey',operation_key,
      'riskClass',risk_class,
      'effectClass',effect_class,
      'authClass',auth_class,
      'controlMode',control_mode,
      'controlRef',control_ref,
      'exemptionReason',exemption_reason,
      'sourceRef',source_ref
    ) order by path_template,http_method),'[]'::jsonb)
  )
  from foundation.current_gateway_operation_contracts
  where service_id='foundation.gateway'
    and environment=p_environment;
$$;

revoke all on function foundation.get_gateway_operation_inventory_v1(text)
  from public,anon,authenticated;
grant execute on function foundation.get_gateway_operation_inventory_v1(text)
  to foundation_runtime,foundation_gateway;


create or replace function foundation.get_gateway_operation_registry_health_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_route_count integer := 0;
  v_duplicate_count integer := 0;
  v_invalid_count integer := 0;
  v_admission_missing integer := 0;
  v_control_counts jsonb := '{}'::jsonb;
  v_state text;
begin
  select count(*) into v_route_count
  from foundation.current_gateway_operation_contracts
  where service_id='foundation.gateway'
    and environment=p_environment;

  select count(*) into v_duplicate_count
  from (
    select http_method,path_template
    from foundation.current_gateway_operation_contracts
    where service_id='foundation.gateway'
      and environment=p_environment
    group by http_method,path_template
    having count(*) > 1
  ) d;

  select count(*) into v_invalid_count
  from foundation.current_gateway_operation_contracts c
  where c.service_id='foundation.gateway'
    and c.environment=p_environment
    and (
      (c.control_mode='public-exempt' and (
        c.effect_class<>'read' or c.auth_class<>'public' or c.exemption_reason is null
      ))
      or (c.control_mode='auth-only' and c.effect_class<>'read')
      or (c.effect_class<>'read' and c.control_ref is null)
      or (c.risk_class='protected-execution' and c.auth_class='public')
    );

  select count(*) into v_admission_missing
  from foundation.current_gateway_operation_contracts c
  where c.service_id='foundation.gateway'
    and c.environment=p_environment
    and c.control_mode='dependency-admission'
    and not exists (
      select 1
      from foundation.current_service_admission_bindings b
      where b.service_id=c.service_id
        and b.environment=c.environment
        and b.operation=c.operation_key
        and b.enabled=true
    );

  select coalesce(jsonb_object_agg(control_mode,cnt),'{}'::jsonb)
  into v_control_counts
  from (
    select control_mode,count(*)::integer as cnt
    from foundation.current_gateway_operation_contracts
    where service_id='foundation.gateway'
      and environment=p_environment
    group by control_mode
  ) x;

  v_state := case
    when v_route_count=0 then 'fail'
    when v_duplicate_count>0 then 'fail'
    when v_invalid_count>0 then 'fail'
    when v_admission_missing>0 then 'fail'
    else 'pass'
  end;

  return jsonb_build_object(
    'gatewayOperationRegistryHealthResponse','shine-foundation/gateway-operation-registry-health-response-v1',
    'schemaVersion','1.0.0',
    'serviceId','foundation.gateway',
    'environment',p_environment,
    'state',v_state,
    'routeCount',v_route_count,
    'duplicateMethodPathCount',v_duplicate_count,
    'invalidContractCount',v_invalid_count,
    'missingAdmissionBindingCount',v_admission_missing,
    'controlModeCounts',v_control_counts
  );
end;
$$;

revoke all on function foundation.get_gateway_operation_registry_health_v1(text)
  from public,anon,authenticated;
grant execute on function foundation.get_gateway_operation_registry_health_v1(text)
  to foundation_runtime,foundation_gateway;


with payload as (
  select *
  from jsonb_to_recordset('[{"routeSymbol":"healthPath","method":"GET","path":"/health","operationKey":"gateway.health.read","riskClass":"public-read","effectClass":"read","authClass":"public","controlMode":"public-exempt","exemptionReason":"Health is deliberately public and returns no private data."},{"routeSymbol":"integrationProtocolPath","method":"GET","path":"/v1/integration/protocol","operationKey":"integration.protocol.read","riskClass":"public-read","effectClass":"read","authClass":"public","controlMode":"public-exempt","exemptionReason":"Protocol discovery is deliberately public and non-mutating."},{"routeSymbol":"evaluatePath","method":"POST","path":"/v1/access/evaluate","operationKey":"access.evaluate","riskClass":"protected-execution","effectClass":"execute","authClass":"user+app","controlMode":"dependency-admission","controlRef":"foundation.evaluate_service_admission_v1"},{"routeSymbol":"identityClaimPath","method":"POST","path":"/v1/identity/claim","operationKey":"identity.claim","riskClass":"identity-write","effectClass":"write","authClass":"claim-source+target","controlMode":"service-guard","controlRef":"foundation.complete_identity_claim_v1"},{"routeSymbol":"grantConsentPath","method":"POST","path":"/v1/grants/consent","operationKey":"grant.consent","riskClass":"permission-write","effectClass":"write","authClass":"user+app","controlMode":"service-guard","controlRef":"foundation.issue_access_grant_v1"},{"routeSymbol":"grantRevocationPath","method":"POST","path":"/v1/grants/revoke","operationKey":"grant.revoke","riskClass":"permission-write","effectClass":"write","authClass":"user+app","controlMode":"service-guard","controlRef":"foundation.revoke_access_grant_v1"},{"routeSymbol":"revocationFeedPath","method":"GET","path":"/v1/revocations","operationKey":"revocation.feed.read","riskClass":"authenticated-read","effectClass":"read","authClass":"app","controlMode":"auth-only","controlRef":"authenticateApp"},{"routeSymbol":"revocationAckPath","method":"POST","path":"/v1/revocations/ack","operationKey":"revocation.ack","riskClass":"control-write","effectClass":"write","authClass":"app","controlMode":"service-guard","controlRef":"foundation.ack_app_revocations_v2"},{"routeSymbol":"revocationStatusPath","method":"GET","path":"/v1/revocations/status","operationKey":"revocation.status.read","riskClass":"authenticated-read","effectClass":"read","authClass":"app","controlMode":"auth-only","controlRef":"authenticateApp"},{"routeSymbol":"appStatusPath","method":"GET","path":"/v1/status","operationKey":"app.status.read","riskClass":"authenticated-read","effectClass":"read","authClass":"app","controlMode":"auth-only","controlRef":"authenticateApp"},{"routeSymbol":"capabilityDiscoveryPath","method":"GET","path":"/v1/integration/capabilities","operationKey":"capability.discovery.read","riskClass":"public-read","effectClass":"read","authClass":"public","controlMode":"public-exempt","exemptionReason":"Capability discovery is intentionally public metadata and non-mutating."},{"routeSymbol":"integrationClientStatusPath","method":"GET","path":"/v1/integration/client/status","operationKey":"integration.client.status.read","riskClass":"authenticated-read","effectClass":"read","authClass":"client","controlMode":"auth-only","controlRef":"authenticateIntegrationClient"},{"routeSymbol":"integrationGrantsPath","method":"GET","path":"/v1/integration/grants","operationKey":"integration.grants.read","riskClass":"authenticated-read","effectClass":"read","authClass":"user+client","controlMode":"auth-only","controlRef":"authenticateIntegrationUserAndClient"},{"routeSymbol":"integrationLinkConsentPath","method":"POST","path":"/v1/integration/link/consent","operationKey":"integration.link.consent","riskClass":"permission-write","effectClass":"write","authClass":"user+client","controlMode":"service-guard","controlRef":"foundation.link_integration_client_v1"},{"routeSymbol":"integrationLinkRevokePath","method":"POST","path":"/v1/integration/link/revoke","operationKey":"integration.link.revoke","riskClass":"permission-write","effectClass":"write","authClass":"user+client","controlMode":"service-guard","controlRef":"foundation.revoke_integration_client_link_v1"},{"routeSymbol":"integrationDeviceLinkRequestPath","method":"POST","path":"/v1/integration/link/request","operationKey":"integration.device-link.request","riskClass":"credential-write","effectClass":"write","authClass":"client","controlMode":"service-guard","controlRef":"foundation.create_integration_link_request_v1"},{"routeSymbol":"integrationDeviceLinkApprovePath","method":"POST","path":"/v1/integration/link/approve","operationKey":"integration.device-link.approve","riskClass":"permission-write","effectClass":"write","authClass":"user","controlMode":"service-guard","controlRef":"foundation.approve_integration_link_request_v1"},{"routeSymbol":"integrationDeviceLinkExchangePath","method":"POST","path":"/v1/integration/link/exchange","operationKey":"integration.device-link.exchange","riskClass":"credential-write","effectClass":"credential","authClass":"client+exchange-secret","controlMode":"service-guard","controlRef":"foundation.exchange_integration_link_request_v2"},{"routeSymbol":"integrationDelegationRefreshPath","method":"POST","path":"/v1/integration/delegation/refresh","operationKey":"integration.delegation.refresh","riskClass":"credential-write","effectClass":"credential","authClass":"client+refresh","controlMode":"service-guard","controlRef":"foundation.rotate_delegation_refresh_v2"},{"routeSymbol":"connectedIntegrationsPath","method":"GET","path":"/v1/integration/connections","operationKey":"integration.connections.read","riskClass":"authenticated-read","effectClass":"read","authClass":"user","controlMode":"auth-only","controlRef":"authenticateIntegrationUser"},{"routeSymbol":"userAccessHistoryPath","method":"GET","path":"/v1/integration/access-history","operationKey":"integration.access-history.read","riskClass":"authenticated-read","effectClass":"read","authClass":"user","controlMode":"auth-only","controlRef":"authenticateIntegrationUser"},{"routeSymbol":"userAccessExplanationPath","method":"GET","path":"/v1/integration/access-history/explain","operationKey":"integration.access-history.explain","riskClass":"authenticated-read","effectClass":"read","authClass":"user","controlMode":"auth-only","controlRef":"authenticateIntegrationUser"},{"routeSymbol":"userGrantRevokePath","method":"POST","path":"/v1/integration/connections/grant/revoke","operationKey":"integration.user-grant.revoke","riskClass":"permission-write","effectClass":"write","authClass":"user","controlMode":"service-guard","controlRef":"foundation.revoke_integration_client_grant_v1"},{"routeSymbol":"userLinkRevokePath","method":"POST","path":"/v1/integration/connections/revoke","operationKey":"integration.user-link.revoke","riskClass":"permission-write","effectClass":"write","authClass":"user","controlMode":"service-guard","controlRef":"foundation.revoke_integration_client_link_v1"},{"routeSymbol":"userConciergeCancelPath","method":"POST","path":"/v1/concierge/cancel","operationKey":"concierge.cancel","riskClass":"control-write","effectClass":"write","authClass":"user","controlMode":"service-guard","controlRef":"foundation.cancel_concierge_request_v1"},{"routeSymbol":"userConciergeJobsPath","method":"GET","path":"/v1/concierge/jobs","operationKey":"concierge.jobs.read","riskClass":"authenticated-read","effectClass":"read","authClass":"user","controlMode":"auth-only","controlRef":"authenticateIntegrationUser"},{"routeSymbol":"conciergeFleetStatusPath","method":"GET","path":"/v1/concierge/fleet","operationKey":"concierge.fleet.read","riskClass":"authenticated-read","effectClass":"read","authClass":"user+client","controlMode":"auth-only","controlRef":"authenticateIntegrationUserAndClient"},{"routeSymbol":"integrationDeviceLinkStatusPath","method":"GET","path":"/v1/integration/link/request/status","operationKey":"integration.device-link.status.read","riskClass":"authenticated-read","effectClass":"read","authClass":"client","controlMode":"auth-only","controlRef":"authenticateIntegrationClient"},{"routeSymbol":"integrationDeviceLinkPreviewPath","method":"GET","path":"/v1/integration/link/preview","operationKey":"integration.device-link.preview","riskClass":"authenticated-read","effectClass":"read","authClass":"user","controlMode":"auth-only","controlRef":"authenticateIntegrationUser"},{"routeSymbol":"integrationGrantConsentPath","method":"POST","path":"/v1/integration/grants/consent","operationKey":"integration.grant.consent","riskClass":"permission-write","effectClass":"write","authClass":"user+client","controlMode":"service-guard","controlRef":"foundation.grant_integration_client_capability_v1"},{"routeSymbol":"integrationGrantRevokePath","method":"POST","path":"/v1/integration/grants/revoke","operationKey":"integration.grant.revoke","riskClass":"permission-write","effectClass":"write","authClass":"user+client","controlMode":"service-guard","controlRef":"foundation.revoke_integration_client_grant_v1"},{"routeSymbol":"conciergePlanPath","method":"POST","path":"/v1/concierge/plan","operationKey":"concierge.plan","riskClass":"protected-execution","effectClass":"write","authClass":"user+client","controlMode":"service-guard","controlRef":"foundation.plan_concierge_request_v1"},{"routeSymbol":"conciergeExecutePath","method":"POST","path":"/v1/concierge/execute","operationKey":"concierge.execute","riskClass":"protected-execution","effectClass":"execute","authClass":"user+client","controlMode":"service-guard","controlRef":"foundation.gate_concierge_execution_v1"},{"routeSymbol":"conciergeResumePath","method":"POST","path":"/v1/concierge/resume","operationKey":"concierge.resume","riskClass":"protected-execution","effectClass":"execute","authClass":"user+client","controlMode":"service-guard","controlRef":"foundation.gate_concierge_execution_v1"},{"routeSymbol":"conciergeRetryClaimPath","method":"POST","path":"/v1/concierge/retry/claim","operationKey":"concierge.retry.claim","riskClass":"worker-control","effectClass":"write","authClass":"client","controlMode":"internal-worker","controlRef":"foundation.claim_due_concierge_retry_v1"},{"routeSymbol":"conciergeRetryFinishPath","method":"POST","path":"/v1/concierge/retry/finish","operationKey":"concierge.retry.finish","riskClass":"worker-control","effectClass":"write","authClass":"client","controlMode":"internal-worker","controlRef":"foundation.finish_concierge_retry_v1"},{"routeSymbol":"capabilityTicketRedeemPath","method":"POST","path":"/v1/capability/ticket/redeem","operationKey":"capability.ticket.redeem","riskClass":"protected-execution","effectClass":"execute","authClass":"one-time-ticket","controlMode":"service-guard","controlRef":"foundation.consume_capability_invocation_ticket_v2"},{"routeSymbol":"integrationContextPublishPath","method":"POST","path":"/v1/integration/context/publish","operationKey":"integration.context.publish","riskClass":"context-write","effectClass":"write","authClass":"app","controlMode":"service-guard","controlRef":"foundation.publish_integration_context_snapshot_v1"},{"routeSymbol":"defenceStatusMatch","method":"GET","path":"/v1/defence/status/:appId","operationKey":"defence.status.read","riskClass":"public-read","effectClass":"read","authClass":"public","controlMode":"public-exempt","exemptionReason":"Public Defence status is hash-qualified, read-only release metadata."}]'::jsonb) as x(
    "routeSymbol" text,
    "method" text,
    "path" text,
    "operationKey" text,
    "riskClass" text,
    "effectClass" text,
    "authClass" text,
    "controlMode" text,
    "controlRef" text,
    "exemptionReason" text
  )
)
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  exemption_reason,source_ref,effective_at
)
select
  'foundation.gateway',
  'production',
  '1.0.0',
  "routeSymbol",
  "method",
  "path",
  "operationKey",
  "riskClass",
  "effectClass",
  "authClass",
  "controlMode",
  "controlRef",
  "exemptionReason",
  'github:foundation/contracts/gateway-operation-registry-v1.json',
  now()
from payload
on conflict (service_id,environment,route_symbol,contract_version) do nothing;
