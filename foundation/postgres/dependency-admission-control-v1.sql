-- Foundation Layer 25: dependency-aware admission control.
-- Converts Layer 24 dependency state into operation-scoped runtime admission.

create table foundation.service_admission_bindings (
  binding_id uuid primary key default gen_random_uuid(),
  service_id text not null references foundation.service_registry(service_id),
  environment text not null
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  operation text not null
    check (operation ~ '^[a-z0-9][a-z0-9._:-]*$'),
  binding_version text not null,
  impact_scope text not null
    check (impact_scope ~ '^[a-z0-9][a-z0-9._:-]*$'),
  enabled boolean not null default true,
  effective_at timestamptz not null default now(),
  evidence_ref text not null,
  evidence_note text,
  recorded_at timestamptz not null default now(),
  unique(service_id,environment,operation,binding_version)
);

alter table foundation.service_admission_bindings enable row level security;

create policy foundation_runtime_service_admission_bindings_select
on foundation.service_admission_bindings
for select
to foundation_runtime
using (true);

revoke all on foundation.service_admission_bindings from public,anon,authenticated;
grant select on foundation.service_admission_bindings to foundation_runtime,foundation_gateway;
grant select,insert on foundation.service_admission_bindings to service_role;

create index service_admission_bindings_current_idx
  on foundation.service_admission_bindings(service_id,environment,operation,effective_at desc,recorded_at desc);

create trigger service_admission_bindings_append_only
before update or delete on foundation.service_admission_bindings
for each row execute function foundation.reject_append_only_mutation();


create view foundation.current_service_admission_bindings
with (security_invoker=true)
as
select distinct on (service_id,environment,operation)
  binding_id,
  service_id,
  environment,
  operation,
  binding_version,
  impact_scope,
  enabled,
  effective_at,
  evidence_ref,
  evidence_note,
  recorded_at
from foundation.service_admission_bindings
order by service_id,environment,operation,effective_at desc,recorded_at desc,binding_id desc;

revoke all on foundation.current_service_admission_bindings from public,anon,authenticated;
grant select on foundation.current_service_admission_bindings to foundation_runtime,foundation_gateway;


create or replace function foundation.evaluate_service_admission_v1(
  p_service_id text,
  p_environment text,
  p_operation text,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $$
declare
  v_binding foundation.service_admission_bindings%rowtype;
  v_rollup jsonb;
  v_graph jsonb;
  v_own_state text;
  v_effective_state text;
  v_safe_mode text;
  v_admission_state text;
  v_reason_code text;
  v_blocked boolean := false;
  v_guarded boolean := false;
  v_degraded boolean := false;
  v_dependency_evidence jsonb := '[]'::jsonb;
begin
  select * into v_binding
  from foundation.current_service_admission_bindings
  where service_id=p_service_id
    and environment=p_environment
    and operation=p_operation;

  if v_binding.binding_id is null then
    return jsonb_build_object(
      'admissionResponse','shine-foundation/service-admission-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'operation',p_operation,
      'admissionState','unavailable',
      'reasonCode','admission-binding-missing'
    );
  end if;

  if not v_binding.enabled then
    return jsonb_build_object(
      'admissionResponse','shine-foundation/service-admission-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'operation',p_operation,
      'impactScope',v_binding.impact_scope,
      'admissionState','unavailable',
      'reasonCode','admission-binding-disabled',
      'bindingEvidenceRef',v_binding.evidence_ref
    );
  end if;

  v_graph := foundation.get_dependency_graph_health_v1(p_environment);

  if coalesce(v_graph->>'state','fail') <> 'pass' then
    return jsonb_build_object(
      'admissionResponse','shine-foundation/service-admission-response-v1',
      'schemaVersion','1.0.0',
      'serviceId',p_service_id,
      'environment',p_environment,
      'operation',p_operation,
      'impactScope',v_binding.impact_scope,
      'admissionState','unavailable',
      'reasonCode','dependency-graph-invalid',
      'bindingEvidenceRef',v_binding.evidence_ref,
      'graphHealth',v_graph
    );
  end if;

  v_rollup := foundation.get_service_dependency_rollup_v1(
    p_service_id,p_environment,p_as_of
  );

  v_own_state := coalesce(v_rollup#>>'{ownState,operationalState}','unknown');
  v_effective_state := coalesce(v_rollup->>'effectiveState','unknown');
  v_safe_mode := coalesce(v_rollup->>'safeMode','unknown');

  select exists(
    select 1 from jsonb_array_elements_text(coalesce(v_rollup->'blockedScopes','[]'::jsonb)) x
    where x=v_binding.impact_scope
  ) into v_blocked;

  select exists(
    select 1 from jsonb_array_elements_text(coalesce(v_rollup->'guardedScopes','[]'::jsonb)) x
    where x=v_binding.impact_scope
  ) into v_guarded;

  select exists(
    select 1 from jsonb_array_elements_text(coalesce(v_rollup->'degradedScopes','[]'::jsonb)) x
    where x=v_binding.impact_scope
  ) into v_degraded;

  select coalesce(jsonb_agg(jsonb_build_object(
    'serviceId',d->>'dependencyServiceId',
    'dependencyType',d->>'dependencyType',
    'impact',d->>'impact',
    'impactScope',d->>'impactScope',
    'sourceEvidenceRef',d#>>'{nativeState,sourceEvidenceRef}',
    'nativeState',d#>>'{nativeState,operationalState}'
  ) order by d->>'dependencyServiceId'),'[]'::jsonb)
  into v_dependency_evidence
  from jsonb_array_elements(coalesce(v_rollup->'dependencies','[]'::jsonb)) d
  where d->>'impactScope'=v_binding.impact_scope;

  if v_own_state in ('unhealthy','drift','unknown') then
    v_admission_state := 'unavailable';
    v_reason_code := 'service-state-unavailable';
  elsif v_blocked then
    v_admission_state := 'deny';
    v_reason_code := 'dependency-blocked';
  elsif v_guarded then
    v_admission_state := 'deny';
    v_reason_code := 'dependency-guarded';
  elsif v_own_state='degraded' or v_degraded then
    v_admission_state := 'admit-degraded';
    v_reason_code := 'dependency-degraded';
  else
    v_admission_state := 'admit';
    v_reason_code := 'dependency-admission-clear';
  end if;

  return jsonb_build_object(
    'admissionResponse','shine-foundation/service-admission-response-v1',
    'schemaVersion','1.0.0',
    'serviceId',p_service_id,
    'environment',p_environment,
    'operation',p_operation,
    'impactScope',v_binding.impact_scope,
    'admissionState',v_admission_state,
    'reasonCode',v_reason_code,
    'ownState',v_own_state,
    'effectiveState',v_effective_state,
    'safeMode',v_safe_mode,
    'bindingEvidenceRef',v_binding.evidence_ref,
    'dependencyEvidence',v_dependency_evidence
  );
end;
$$;

revoke all on function foundation.evaluate_service_admission_v1(text,text,text,timestamptz)
  from public,anon,authenticated;
grant execute on function foundation.evaluate_service_admission_v1(text,text,text,timestamptz)
  to foundation_runtime,foundation_gateway;


insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
select
  'foundation.gateway',
  'production',
  'access.evaluate',
  '1.0.0',
  'protected-operations',
  true,
  now(),
  'foundation:admission-binding:gateway:access-evaluate:v1',
  'All Foundation Gateway access.evaluate requests are protected operations and must respect the Layer 24 dependency guard graph before Vault/grant/Defence execution.'
where not exists (
  select 1
  from foundation.service_admission_bindings
  where service_id='foundation.gateway'
    and environment='production'
    and operation='access.evaluate'
    and binding_version='1.0.0'
);
