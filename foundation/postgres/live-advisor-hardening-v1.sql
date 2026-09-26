-- Shine Foundation live advisor hardening v1
-- Mirrors remediations discovered by Supabase hosted advisors.

alter function foundation.reject_append_only_mutation()
  set search_path = pg_catalog, foundation;

alter function foundation.enqueue_grant_revocation()
  set search_path = pg_catalog, foundation;

drop policy if exists foundation_runtime_revocation_outbox_deny on foundation.revocation_outbox;
create policy foundation_runtime_revocation_outbox_deny
on foundation.revocation_outbox
for select
to foundation_runtime
using (false);

create index if not exists access_audit_grant_id_idx
  on foundation.access_audit_events (grant_id)
  where grant_id is not null;

create index if not exists access_grants_app_id_idx
  on foundation.access_grants (app_id);

create index if not exists access_grants_resource_owner_idx
  on foundation.access_grants (resource_id, owner_shine_id)
  where resource_id is not null;

create index if not exists grant_revocations_grant_owner_idx
  on foundation.grant_revocations (grant_id, owner_shine_id);

create index if not exists revocation_outbox_grant_owner_idx
  on foundation.revocation_outbox (grant_id, owner_shine_id);
