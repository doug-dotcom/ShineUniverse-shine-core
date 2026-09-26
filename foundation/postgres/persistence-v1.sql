-- Shine Foundation persistence v1
-- Layer 4: durable grants, audit ledger and monotonic revocation propagation.
--
-- Security model:
--   * private `foundation` schema
--   * no anon/authenticated access
--   * RLS enabled as defence in depth
--   * trusted server-side service_role performs Foundation persistence
--   * grant/revocation/audit/outbox records are append-only

create schema if not exists foundation;

revoke all on schema foundation from public;
revoke all on schema foundation from anon;
revoke all on schema foundation from authenticated;
grant usage on schema foundation to service_role;

create table if not exists foundation.app_registry (
  app_id text primary key
    check (app_id ~ '^shine\.[a-z0-9][a-z0-9-]*$'),
  manifest_version text not null,
  manifest jsonb not null,
  status text not null default 'active'
    check (status in ('active','disabled')),
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists foundation.shine_identities (
  shine_id uuid primary key,
  account_state text not null default 'active'
    check (account_state in ('active','suspended','deletion-pending','deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists foundation.identity_bindings (
  provider text not null,
  provider_subject text not null,
  shine_id uuid not null references foundation.shine_identities(shine_id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (provider, provider_subject)
);

create index if not exists identity_bindings_shine_id_idx
  on foundation.identity_bindings (shine_id);

create table if not exists foundation.vault_resources (
  resource_id uuid primary key,
  owner_shine_id uuid not null references foundation.shine_identities(shine_id),
  category text not null
    check (category ~ '^[a-z0-9][a-z0-9._-]*$'),
  sensitivity text not null
    check (sensitivity in ('personal','sensitive','restricted')),
  content_type text,
  storage_ref text,
  provenance jsonb not null default '{}'::jsonb,
  integrity_sha256 text
    check (integrity_sha256 is null or integrity_sha256 ~ '^[a-fA-F0-9]{64}$'),
  size_bytes bigint
    check (size_bytes is null or size_bytes >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (resource_id, owner_shine_id)
);

create index if not exists vault_resources_owner_category_idx
  on foundation.vault_resources (owner_shine_id, category);

create table if not exists foundation.access_grants (
  grant_id uuid primary key,
  owner_shine_id uuid not null references foundation.shine_identities(shine_id),
  app_id text not null references foundation.app_registry(app_id),
  scope text not null
    check (scope ~ '^[a-z0-9][a-z0-9._:-]*$'),
  purpose text not null
    check (purpose ~ '^[a-z0-9][a-z0-9._:-]*$'),
  resource_id uuid,
  resource_category text
    check (resource_category is null or resource_category ~ '^[a-z0-9][a-z0-9._-]*$'),
  status text not null default 'active'
    check (status = 'active'),
  issued_at timestamptz not null default now(),
  not_before timestamptz,
  expires_at timestamptz,
  consent_method text not null
    check (consent_method in ('explicit-user','admin-authorised','system-migration')),
  consent_recorded_at timestamptz not null,
  consent_evidence_ref text,
  created_at timestamptz not null default now(),
  check (resource_id is not null or resource_category is not null),
  check (not_before is null or expires_at is null or not_before < expires_at),
  unique (grant_id, owner_shine_id),
  foreign key (resource_id, owner_shine_id)
    references foundation.vault_resources(resource_id, owner_shine_id)
);

create index if not exists access_grants_lookup_idx
  on foundation.access_grants (owner_shine_id, app_id, scope, purpose);

create index if not exists access_grants_resource_idx
  on foundation.access_grants (resource_id)
  where resource_id is not null;

create table if not exists foundation.grant_revocations (
  revocation_id uuid primary key,
  grant_id uuid not null,
  owner_shine_id uuid not null,
  revoked_at timestamptz not null default now(),
  reason text not null
    check (reason in ('user-revoked','account-state','security-event','app-removed','expired','administrative')),
  detail text,
  created_at timestamptz not null default now(),
  unique (grant_id),
  foreign key (grant_id, owner_shine_id)
    references foundation.access_grants(grant_id, owner_shine_id)
);

create index if not exists grant_revocations_owner_idx
  on foundation.grant_revocations (owner_shine_id, revoked_at desc);

create table if not exists foundation.revocation_outbox (
  sequence_no bigint generated always as identity primary key,
  revocation_id uuid not null unique
    references foundation.grant_revocations(revocation_id),
  grant_id uuid not null,
  owner_shine_id uuid not null,
  topic text not null default 'foundation.grant.revoked',
  payload jsonb not null,
  created_at timestamptz not null default now(),
  foreign key (grant_id, owner_shine_id)
    references foundation.access_grants(grant_id, owner_shine_id)
);

create index if not exists revocation_outbox_cursor_idx
  on foundation.revocation_outbox (sequence_no);

create table if not exists foundation.access_audit_events (
  event_id uuid primary key,
  request_id uuid not null unique,
  decision_id uuid,
  app_id text not null,
  shine_id uuid not null,
  scope text not null,
  purpose text not null,
  resource_id uuid,
  resource_category text,
  decision text not null
    check (decision in ('allow','deny')),
  reason_code text not null,
  grant_id uuid,
  occurred_at timestamptz not null,
  defence_evidence_ref text,
  request_context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (app_id) references foundation.app_registry(app_id),
  foreign key (shine_id) references foundation.shine_identities(shine_id),
  foreign key (grant_id) references foundation.access_grants(grant_id)
);

create index if not exists access_audit_identity_time_idx
  on foundation.access_audit_events (shine_id, occurred_at desc);

create index if not exists access_audit_app_time_idx
  on foundation.access_audit_events (app_id, occurred_at desc);

create or replace function foundation.reject_append_only_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is append-only', tg_table_schema || '.' || tg_table_name
    using errcode = '55000';
end;
$$;

revoke all on function foundation.reject_append_only_mutation() from public;
grant execute on function foundation.reject_append_only_mutation() to service_role;

drop trigger if exists access_grants_append_only on foundation.access_grants;
create trigger access_grants_append_only
before update or delete on foundation.access_grants
for each row execute function foundation.reject_append_only_mutation();

drop trigger if exists grant_revocations_append_only on foundation.grant_revocations;
create trigger grant_revocations_append_only
before update or delete on foundation.grant_revocations
for each row execute function foundation.reject_append_only_mutation();

drop trigger if exists revocation_outbox_append_only on foundation.revocation_outbox;
create trigger revocation_outbox_append_only
before update or delete on foundation.revocation_outbox
for each row execute function foundation.reject_append_only_mutation();

drop trigger if exists access_audit_events_append_only on foundation.access_audit_events;
create trigger access_audit_events_append_only
before update or delete on foundation.access_audit_events
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.enqueue_grant_revocation()
returns trigger
language plpgsql
as $$
begin
  if new.revoked_at < (
    select issued_at from foundation.access_grants where grant_id = new.grant_id
  ) then
    raise exception 'revocation cannot predate grant issuance'
      using errcode = '23514';
  end if;

  insert into foundation.revocation_outbox (
    revocation_id,
    grant_id,
    owner_shine_id,
    payload
  ) values (
    new.revocation_id,
    new.grant_id,
    new.owner_shine_id,
    jsonb_build_object(
      'event', 'shine-foundation/grant-revocation-v1',
      'schemaVersion', '1.0.0',
      'revocationId', new.revocation_id,
      'grantId', new.grant_id,
      'ownerShineId', new.owner_shine_id,
      'revokedAt', new.revoked_at,
      'reason', new.reason,
      'detail', new.detail
    )
  );

  return new;
end;
$$;

revoke all on function foundation.enqueue_grant_revocation() from public;
grant execute on function foundation.enqueue_grant_revocation() to service_role;

drop trigger if exists grant_revocation_outbox on foundation.grant_revocations;
create trigger grant_revocation_outbox
after insert on foundation.grant_revocations
for each row execute function foundation.enqueue_grant_revocation();

create or replace view foundation.effective_access_grants
with (security_invoker = true)
as
select
  g.grant_id,
  g.owner_shine_id,
  g.app_id,
  g.scope,
  g.purpose,
  g.resource_id,
  g.resource_category,
  case
    when r.revocation_id is not null then 'revoked'
    when g.expires_at is not null and g.expires_at <= now() then 'expired'
    when g.not_before is not null and g.not_before > now() then 'not-yet-active'
    else 'active'
  end as effective_status,
  g.issued_at,
  g.not_before,
  g.expires_at,
  r.revocation_id,
  r.revoked_at,
  r.reason as revocation_reason
from foundation.access_grants g
left join foundation.grant_revocations r
  on r.grant_id = g.grant_id;

-- Defence in depth: RLS is enabled even though the schema is not client-exposed.
alter table foundation.app_registry enable row level security;
alter table foundation.shine_identities enable row level security;
alter table foundation.identity_bindings enable row level security;
alter table foundation.vault_resources enable row level security;
alter table foundation.access_grants enable row level security;
alter table foundation.grant_revocations enable row level security;
alter table foundation.revocation_outbox enable row level security;
alter table foundation.access_audit_events enable row level security;

-- No browser/client roles receive Foundation persistence privileges.
revoke all on all tables in schema foundation from public;
revoke all on all tables in schema foundation from anon;
revoke all on all tables in schema foundation from authenticated;
revoke all on all sequences in schema foundation from public;
revoke all on all sequences in schema foundation from anon;
revoke all on all sequences in schema foundation from authenticated;

-- Trusted Foundation server-side persistence.
grant select, insert, update on foundation.app_registry to service_role;
grant select, insert, update on foundation.shine_identities to service_role;
grant select, insert, update on foundation.identity_bindings to service_role;
grant select, insert, update on foundation.vault_resources to service_role;

grant select, insert on foundation.access_grants to service_role;
grant select, insert on foundation.grant_revocations to service_role;
grant select, insert on foundation.revocation_outbox to service_role;
grant select, insert on foundation.access_audit_events to service_role;
grant select on foundation.effective_access_grants to service_role;
grant usage, select on all sequences in schema foundation to service_role;
