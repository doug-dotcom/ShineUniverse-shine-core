-- Shine Foundation Supabase runtime v1
-- Layer 6: least-privilege runtime role, app attestation and auditable untrusted claims.

alter table foundation.access_audit_events
  drop constraint if exists access_audit_events_app_id_fkey;
alter table foundation.access_audit_events
  drop constraint if exists access_audit_events_shine_id_fkey;

create table if not exists foundation.app_credentials (
  credential_id uuid primary key,
  app_id text not null references foundation.app_registry(app_id),
  token_hash text not null unique
    check (token_hash ~ '^[a-fA-F0-9]{64}$'),
  label text,
  issued_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  unique (credential_id, app_id)
);

create index if not exists app_credentials_app_idx
  on foundation.app_credentials (app_id);

create table if not exists foundation.app_credential_revocations (
  revocation_id uuid primary key,
  credential_id uuid not null unique
    references foundation.app_credentials(credential_id),
  revoked_at timestamptz not null default now(),
  reason text not null
    check (reason in ('rotated','compromised','app-disabled','administrative')),
  detail text,
  created_at timestamptz not null default now()
);

create or replace view foundation.effective_app_credentials
with (security_invoker = true)
as
select
  c.credential_id,
  c.app_id,
  c.token_hash,
  c.issued_at,
  c.expires_at,
  case
    when r.revocation_id is not null then 'revoked'
    when c.expires_at is not null and c.expires_at <= now() then 'expired'
    else 'active'
  end as effective_status,
  r.revocation_id,
  r.revoked_at,
  r.reason as revocation_reason
from foundation.app_credentials c
left join foundation.app_credential_revocations r
  on r.credential_id = c.credential_id;

alter table foundation.app_credentials enable row level security;
alter table foundation.app_credential_revocations enable row level security;

revoke all on foundation.app_credentials from public, anon, authenticated;
revoke all on foundation.app_credential_revocations from public, anon, authenticated;
revoke all on foundation.effective_app_credentials from public, anon, authenticated;

grant select, insert on foundation.app_credentials to service_role;
grant select, insert on foundation.app_credential_revocations to service_role;
grant select on foundation.effective_app_credentials to service_role;

drop trigger if exists app_credentials_append_only on foundation.app_credentials;
create trigger app_credentials_append_only
before update or delete on foundation.app_credentials
for each row execute function foundation.reject_append_only_mutation();

drop trigger if exists app_credential_revocations_append_only on foundation.app_credential_revocations;
create trigger app_credential_revocations_append_only
before update or delete on foundation.app_credential_revocations
for each row execute function foundation.reject_append_only_mutation();

do $$
begin
  if not exists (select 1 from pg_roles where rolname='foundation_runtime') then
    create role foundation_runtime nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname='foundation_gateway') then
    create role foundation_gateway login;
  end if;
end
$$;

grant foundation_runtime to foundation_gateway;
grant usage on schema foundation to foundation_runtime;

grant select on foundation.app_registry to foundation_runtime;
grant select on foundation.shine_identities to foundation_runtime;
grant select on foundation.identity_bindings to foundation_runtime;
grant select on foundation.vault_resources to foundation_runtime;
grant select on foundation.access_grants to foundation_runtime;
grant select on foundation.grant_revocations to foundation_runtime;
grant select on foundation.effective_access_grants to foundation_runtime;
grant select on foundation.app_credentials to foundation_runtime;
grant select on foundation.app_credential_revocations to foundation_runtime;
grant select on foundation.effective_app_credentials to foundation_runtime;
grant select, insert on foundation.access_audit_events to foundation_runtime;

drop policy if exists foundation_runtime_app_registry_select on foundation.app_registry;
create policy foundation_runtime_app_registry_select
on foundation.app_registry for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_identities_select on foundation.shine_identities;
create policy foundation_runtime_identities_select
on foundation.shine_identities for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_bindings_select on foundation.identity_bindings;
create policy foundation_runtime_bindings_select
on foundation.identity_bindings for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_resources_select on foundation.vault_resources;
create policy foundation_runtime_resources_select
on foundation.vault_resources for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_grants_select on foundation.access_grants;
create policy foundation_runtime_grants_select
on foundation.access_grants for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_revocations_select on foundation.grant_revocations;
create policy foundation_runtime_revocations_select
on foundation.grant_revocations for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_app_credentials_select on foundation.app_credentials;
create policy foundation_runtime_app_credentials_select
on foundation.app_credentials for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_app_credential_revocations_select on foundation.app_credential_revocations;
create policy foundation_runtime_app_credential_revocations_select
on foundation.app_credential_revocations for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_audit_select on foundation.access_audit_events;
create policy foundation_runtime_audit_select
on foundation.access_audit_events for select to foundation_runtime using (true);

drop policy if exists foundation_runtime_audit_insert on foundation.access_audit_events;
create policy foundation_runtime_audit_insert
on foundation.access_audit_events for insert to foundation_runtime with check (true);
