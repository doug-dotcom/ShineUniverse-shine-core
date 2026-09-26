-- Shine Foundation app connection registry v1
-- Layer 10: app-specific identity issuers + derived onboarding state.

create table if not exists foundation.app_identity_providers (
  app_id text not null references foundation.app_registry(app_id),
  provider_id text not null references foundation.identity_providers(provider_id),
  status text not null default 'active'
    check (status in ('active','disabled')),
  linked_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (app_id, provider_id)
);

alter table foundation.app_identity_providers enable row level security;

revoke all on foundation.app_identity_providers from public, anon, authenticated;
grant select, insert, update on foundation.app_identity_providers to service_role;
grant select on foundation.app_identity_providers to foundation_runtime;

drop policy if exists foundation_runtime_app_identity_providers_select
  on foundation.app_identity_providers;
create policy foundation_runtime_app_identity_providers_select
on foundation.app_identity_providers
for select
to foundation_runtime
using (status='active');

create or replace view foundation.app_connection_status
with (security_invoker = true)
as
with credential_counts as (
  select
    app_id,
    count(*) filter (where effective_status='active')::int as active_credentials
  from foundation.effective_app_credentials
  group by app_id
),
provider_counts as (
  select
    app_id,
    count(*) filter (where status='active')::int as active_identity_providers
  from foundation.app_identity_providers
  group by app_id
),
grant_counts as (
  select
    app_id,
    count(*) filter (where effective_status='active')::int as active_grants
  from foundation.effective_access_grants
  group by app_id
),
audit_counts as (
  select
    app_id,
    count(*) filter (where decision='allow')::int as observed_allows,
    count(*) filter (where decision='deny')::int as observed_denies,
    max(occurred_at) as last_observed_at
  from foundation.access_audit_events
  group by app_id
),
last_audit as (
  select distinct on (app_id)
    app_id,
    decision as last_decision,
    reason_code as last_reason_code
  from foundation.access_audit_events
  order by app_id, occurred_at desc, created_at desc
)
select
  r.app_id,
  r.manifest->>'name' as app_name,
  r.status as registry_status,
  coalesce((r.manifest #>> '{foundation,standalonePrimaryPurposeAvailable}')::boolean,false)
    as standalone_primary_purpose_available,
  coalesce(c.active_credentials,0) as active_credentials,
  coalesce(p.active_identity_providers,0) as active_identity_providers,
  coalesce(g.active_grants,0) as active_grants,
  coalesce(a.observed_allows,0) as observed_allows,
  coalesce(a.observed_denies,0) as observed_denies,
  a.last_observed_at,
  l.last_decision,
  l.last_reason_code,
  case
    when r.status<>'active' then 'disabled'
    when coalesce(c.active_credentials,0)=0 then 'registered'
    when coalesce(p.active_identity_providers,0)=0 then 'credentialed'
    when coalesce(g.active_grants,0)=0 then 'identity-ready'
    when coalesce(a.observed_allows,0)=0 then 'grant-ready'
    else 'live-observed'
  end as connection_state
from foundation.app_registry r
left join credential_counts c on c.app_id=r.app_id
left join provider_counts p on p.app_id=r.app_id
left join grant_counts g on g.app_id=r.app_id
left join audit_counts a on a.app_id=r.app_id
left join last_audit l on l.app_id=r.app_id;

revoke all on foundation.app_connection_status from public, anon, authenticated;
grant select on foundation.app_connection_status to service_role;
