-- Shine Foundation identity federation v1
-- Layer 8: registered external identity providers for existing Shine app sessions.

create table if not exists foundation.identity_providers (
  provider_id text primary key
    check (provider_id ~ '^[a-z0-9][a-z0-9._:-]*$'),
  kind text not null
    check (kind in ('supabase-auth')),
  project_url text not null
    check (project_url ~ '^https://[a-z0-9.-]+$'),
  issuer text not null unique
    check (issuer ~ '^https://[a-z0-9.-]+/auth/v1$'),
  publishable_key text not null,
  status text not null default 'active'
    check (status in ('active','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table foundation.identity_providers enable row level security;

revoke all on foundation.identity_providers from public, anon, authenticated;
grant select, insert, update on foundation.identity_providers to service_role;
grant select on foundation.identity_providers to foundation_runtime;

drop policy if exists foundation_runtime_identity_providers_select
  on foundation.identity_providers;
create policy foundation_runtime_identity_providers_select
on foundation.identity_providers
for select
to foundation_runtime
using (status='active');

-- Pre-identity denials (for example an unverified app caller) are still
-- audit evidence even when no canonical Shine ID can yet be established.
alter table foundation.access_audit_events
  alter column shine_id drop not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='identity_bindings_provider_fkey'
      and conrelid='foundation.identity_bindings'::regclass
  ) then
    alter table foundation.identity_bindings
      add constraint identity_bindings_provider_fkey
      foreign key (provider)
      references foundation.identity_providers(provider_id);
  end if;
end
$$;
