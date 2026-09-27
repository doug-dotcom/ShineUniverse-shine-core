-- Historical production backfill: Foundation app revocation feed v1.
-- Mirrors migration 20260926143912.

create or replace function foundation.list_app_revocations_v1(
  p_app_id text,
  p_after_sequence bigint default 0,
  p_limit integer default 101
)
returns table(
  sequence_no bigint,
  event_payload jsonb,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $function$
begin
  if p_app_id is null
     or p_app_id !~ '^shine\.[a-z0-9][a-z0-9-]*$'
     or p_after_sequence is null
     or p_after_sequence < 0
     or p_limit is null
     or p_limit < 1
     or p_limit > 201 then
    raise exception 'invalid-revocation-feed-request' using errcode='22023';
  end if;

  return query
  select
    o.sequence_no,
    o.payload as event_payload,
    o.created_at
  from foundation.revocation_outbox o
  join foundation.access_grants g
    on g.grant_id = o.grant_id
   and g.owner_shine_id = o.owner_shine_id
  where g.app_id = p_app_id
    and o.sequence_no > p_after_sequence
  order by o.sequence_no
  limit p_limit;
end;
$function$;

revoke all on function foundation.list_app_revocations_v1(
  text, bigint, integer
) from public, anon, authenticated, service_role;

grant execute on function foundation.list_app_revocations_v1(
  text, bigint, integer
) to foundation_runtime;
