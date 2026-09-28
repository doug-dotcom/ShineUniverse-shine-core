-- Atlas Feed Layer 2: register the publisher admission boundary with Foundation's
-- existing route registry, Defence-backed dependency admission and operation policy.
-- No Atlas Feed event persistence is created by this migration.

insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishAdmitPath','POST',
  '/v1/atlas-feed/publish/admit','atlas-feed.publish.admit',
  'context-write','execute','app-or-user+app','service-guard',
  'atlas-feed.publisher-admission-v1',
  'github:atlas-feed/contracts/publisher-admission-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish.admit','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:publisher:v1',
  'Atlas Feed publisher admission shares the existing Defence-backed context-operation dependency scope.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish.admit','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'atlas-feed.publisher-admission-v1',true,now(),
  'atlas-feed:operation-policy:publisher:v1',
  'Publisher admission must pass current context-operation dependency admission before the Atlas-specific app/capability/owner/grant guard runs.'
)
on conflict do nothing;
