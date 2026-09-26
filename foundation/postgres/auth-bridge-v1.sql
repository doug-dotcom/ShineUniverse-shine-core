-- Shine Foundation trusted auth issuer bridge v1
-- Allows existing Shine app auth issuers to migrate into canonical Shine ID.

create table if not exists foundation.trusted_auth_issuers (
  issuer_id text primary key
    check (issuer_id ~ '^[a-z0-9][a-z0-9._:-]*$'),
  issuer_url text not null unique,
  api_url text not null,
  publishable_key text not null,
  status text not null default 'active'
    check (status in ('active','disabled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table foundation.trusted_auth_issuers enable row level security;

revoke all on foundation.trusted_auth_issuers from public, anon, authenticated;

grant select, insert, update on foundation.trusted_auth_issuers to service_role;
grant select on foundation.trusted_auth_issuers to foundation_runtime;

drop policy if exists foundation_runtime_trusted_auth_issuers_select
  on foundation.trusted_auth_issuers;
create policy foundation_runtime_trusted_auth_issuers_select
on foundation.trusted_auth_issuers for select
to foundation_runtime
using (status='active');
