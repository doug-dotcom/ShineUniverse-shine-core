-- Shine Foundation identity federation v2
-- Layer 11: opaque Supabase vault sessions alongside JWT issuers.

alter table foundation.identity_providers
  alter column issuer drop not null;

alter table foundation.identity_providers
  add column if not exists verification_resource text,
  add column if not exists subject_field text,
  add column if not exists token_header text;

alter table foundation.identity_providers
  drop constraint if exists identity_providers_kind_check;

alter table foundation.identity_providers
  add constraint identity_providers_kind_check
  check (kind in ('supabase-auth','supabase-opaque-vault'));

alter table foundation.identity_providers
  drop constraint if exists identity_providers_shape_check;

alter table foundation.identity_providers
  add constraint identity_providers_shape_check
  check (
    (
      kind='supabase-auth'
      and issuer is not null
      and verification_resource is null
      and subject_field is null
      and token_header is null
    )
    or
    (
      kind='supabase-opaque-vault'
      and issuer is null
      and verification_resource ~ '^[a-z][a-z0-9_]{0,62}$'
      and subject_field ~ '^[a-z][a-z0-9_]{0,62}$'
      and token_header ~ '^x-[a-z0-9-]{1,62}$'
    )
  );
