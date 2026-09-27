create table foundation.app_capabilities (
  capability_id text primary key
    check (capability_id ~ '^[a-z0-9][a-z0-9._:-]*$'),
  app_id text not null references foundation.app_registry(app_id),
  capability_version text not null default '1.0.0',
  display_name text not null,
  description text not null,
  capability_mode text not null
    check (capability_mode in ('read','advisory','action')),
  input_schema jsonb not null default '{}'::jsonb,
  output_schema jsonb not null default '{}'::jsonb,
  required_permissions jsonb not null default '[]'::jsonb,
  invocation_state text not null default 'declared'
    check (invocation_state in ('declared','adapter-ready','live','disabled')),
  discoverable boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(app_id,capability_id),
  check (jsonb_typeof(input_schema)='object'),
  check (jsonb_typeof(output_schema)='object'),
  check (jsonb_typeof(required_permissions)='array')
);

comment on table foundation.app_capabilities is
  'Portable capability catalogue for Shine specialist apps. Consumers discover capabilities here; app data and execution remain behind Foundation/Concierge permission gates.';

alter table foundation.app_capabilities enable row level security;

create policy foundation_runtime_app_capabilities_select
on foundation.app_capabilities
for select
to foundation_runtime
using (true);

revoke all on foundation.app_capabilities from public,anon,authenticated;
grant select on foundation.app_capabilities to foundation_runtime,service_role;
grant insert,update on foundation.app_capabilities to service_role;

create index app_capabilities_app_state_idx
  on foundation.app_capabilities(app_id,invocation_state)
  where discoverable=true;

create table foundation.integration_clients (
  client_id text primary key
    check (client_id ~ '^[a-z0-9][a-z0-9._:-]*$'),
  display_name text not null,
  client_kind text not null
    check (client_kind in ('first-party-companion','external-companion','developer-agent','service')),
  status text not null default 'active'
    check (status in ('active','disabled')),
  metadata jsonb not null default '{}'::jsonb,
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(metadata)='object')
);

comment on table foundation.integration_clients is
  'Registered callers of the open Shine integration surface. Shine Companion is one client class, not a privileged exception.';

alter table foundation.integration_clients enable row level security;

create policy foundation_runtime_integration_clients_select
on foundation.integration_clients
for select
to foundation_runtime
using (true);

revoke all on foundation.integration_clients from public,anon,authenticated;
grant select on foundation.integration_clients to foundation_runtime,service_role;
grant insert,update on foundation.integration_clients to service_role;

create table foundation.integration_client_credentials (
  credential_id uuid primary key,
  client_id text not null references foundation.integration_clients(client_id),
  token_hash text not null unique
    check (token_hash ~ '^[a-fA-F0-9]{64}$'),
  label text,
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at is null or expires_at > issued_at)
);

alter table foundation.integration_client_credentials enable row level security;

create policy foundation_runtime_integration_client_credentials_select
on foundation.integration_client_credentials
for select
to foundation_runtime
using (true);

revoke all on foundation.integration_client_credentials from public,anon,authenticated;
grant select on foundation.integration_client_credentials to foundation_runtime,service_role;
grant insert on foundation.integration_client_credentials to service_role;

create table foundation.integration_client_credential_revocations (
  revocation_id uuid primary key,
  credential_id uuid not null unique
    references foundation.integration_client_credentials(credential_id),
  revoked_at timestamptz not null default now(),
  reason text not null
    check (reason in ('rotated','compromised','client-disabled','administrative')),
  detail text,
  created_at timestamptz not null default now()
);

alter table foundation.integration_client_credential_revocations enable row level security;

create policy foundation_runtime_integration_client_credential_revocations_select
on foundation.integration_client_credential_revocations
for select
to foundation_runtime
using (true);

revoke all on foundation.integration_client_credential_revocations from public,anon,authenticated;
grant select on foundation.integration_client_credential_revocations to foundation_runtime,service_role;
grant insert on foundation.integration_client_credential_revocations to service_role;

create trigger integration_client_credentials_append_only
before update or delete on foundation.integration_client_credentials
for each row execute function foundation.reject_append_only_mutation();

create trigger integration_client_credential_revocations_append_only
before update or delete on foundation.integration_client_credential_revocations
for each row execute function foundation.reject_append_only_mutation();

create view foundation.effective_integration_client_credentials
with (security_invoker=true)
as
select
  c.credential_id,
  c.client_id,
  c.token_hash,
  c.label,
  c.issued_at,
  c.expires_at,
  cl.client_kind,
  case
    when cl.status <> 'active' then 'client-disabled'
    when r.credential_id is not null then 'revoked'
    when c.expires_at is not null and c.expires_at <= now() then 'expired'
    else 'active'
  end as effective_status
from foundation.integration_client_credentials c
join foundation.integration_clients cl on cl.client_id=c.client_id
left join foundation.integration_client_credential_revocations r
  on r.credential_id=c.credential_id;

revoke all on foundation.effective_integration_client_credentials
from public,anon,authenticated;

grant select on foundation.effective_integration_client_credentials
to foundation_runtime,service_role;

create or replace function foundation.list_discoverable_capabilities_v1(
  p_app_id text default null
)
returns jsonb
language sql
security definer
set search_path = pg_catalog, foundation
as $function$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'capabilityId',c.capability_id,
      'capabilityVersion',c.capability_version,
      'appId',c.app_id,
      'appName',r.manifest->>'name',
      'displayName',c.display_name,
      'description',c.description,
      'mode',c.capability_mode,
      'inputSchema',c.input_schema,
      'outputSchema',c.output_schema,
      'requiredPermissions',c.required_permissions,
      'invocationState',c.invocation_state,
      'invocable',(c.invocation_state='live')
    )
    order by c.app_id,c.capability_id
  ),'[]'::jsonb)
  from foundation.app_capabilities c
  join foundation.app_registry r on r.app_id=c.app_id
  where c.discoverable=true
    and c.invocation_state<>'disabled'
    and r.status='active'
    and (p_app_id is null or c.app_id=p_app_id);
$function$;

revoke all on function foundation.list_discoverable_capabilities_v1(text)
from public,anon,authenticated,service_role;

grant execute on function foundation.list_discoverable_capabilities_v1(text)
to foundation_runtime;

insert into foundation.app_capabilities(
  capability_id,app_id,display_name,description,capability_mode,
  input_schema,output_schema,required_permissions,invocation_state
) values
(
  'travel.plan_trip',
  'shine.travel',
  'Plan a trip',
  'Build or refine a trip plan for a destination using Shine Travel.',
  'advisory',
  '{"type":"object","properties":{"destination":{"type":"string"},"startDate":{"type":"string"},"endDate":{"type":"string"},"party":{"type":"object"},"preferences":{"type":"object"}},"required":["destination"]}'::jsonb,
  '{"type":"object","properties":{"summary":{"type":"string"},"itinerary":{"type":"array"},"estimatedBudget":{"type":"object"},"nextActions":{"type":"array"}}}'::jsonb,
  '[]'::jsonb,
  'declared'
),
(
  'dive.destination_brief',
  'shine.dive',
  'Destination dive brief',
  'Describe diving opportunities, conditions and suitability for a destination using Shine Dive.',
  'advisory',
  '{"type":"object","properties":{"destination":{"type":"string"},"travelDates":{"type":"object"},"certifications":{"type":"array"}},"required":["destination"]}'::jsonb,
  '{"type":"object","properties":{"summary":{"type":"string"},"sites":{"type":"array"},"conditions":{"type":"object"},"suitability":{"type":"object"},"nextActions":{"type":"array"}}}'::jsonb,
  '[]'::jsonb,
  'declared'
),
(
  'ski.destination_brief',
  'shine.ski',
  'Destination snow brief',
  'Describe skiing and snowboarding options, resorts and planning considerations for a destination using Shine Ski.',
  'advisory',
  '{"type":"object","properties":{"destination":{"type":"string"},"travelDates":{"type":"object"},"ability":{"type":"string"}},"required":["destination"]}'::jsonb,
  '{"type":"object","properties":{"summary":{"type":"string"},"resorts":{"type":"array"},"conditions":{"type":"object"},"nextActions":{"type":"array"}}}'::jsonb,
  '[]'::jsonb,
  'declared'
);
