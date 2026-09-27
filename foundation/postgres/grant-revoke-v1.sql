-- Shine Foundation explicit user grant revocation v1
-- Layer 16: the authenticated owner can withdraw one app grant immediately.
-- Revocation is monotonic, idempotent and deliberately independent of Defence approval.

create or replace function foundation.revoke_access_grant_v1(
  p_revocation_id uuid,
  p_grant_id uuid,
  p_owner_shine_id uuid,
  p_app_id text,
  p_revoked_at timestamptz
)
returns table(outcome text, reason_code text, grant_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $$
declare
  g foundation.access_grants%rowtype;
  r foundation.grant_revocations%rowtype;
begin
  select * into g
  from foundation.access_grants
  where access_grants.grant_id=p_grant_id
  for update;

  if not found
     or g.owner_shine_id<>p_owner_shine_id
     or g.app_id<>p_app_id then
    return query select 'denied'::text,'grant-not-found'::text,null::uuid;
    return;
  end if;

  select * into r
  from foundation.grant_revocations
  where grant_revocations.grant_id=p_grant_id;

  if found then
    return query select 'already-revoked'::text,'grant-already-revoked'::text,p_grant_id;
    return;
  end if;

  if p_revoked_at<g.issued_at then
    raise exception 'revocation cannot predate grant issuance' using errcode='23514';
  end if;

  insert into foundation.grant_revocations(
    revocation_id,grant_id,owner_shine_id,revoked_at,reason,detail
  ) values (
    p_revocation_id,p_grant_id,p_owner_shine_id,p_revoked_at,
    'user-revoked','explicit-user-foundation-v1'
  );

  return query select 'revoked'::text,'grant-revoked-by-user'::text,p_grant_id;
end;
$$;

revoke all on function foundation.revoke_access_grant_v1(
  uuid,uuid,uuid,text,timestamptz
) from public, anon, authenticated, service_role;

grant execute on function foundation.revoke_access_grant_v1(
  uuid,uuid,uuid,text,timestamptz
) to foundation_runtime;
