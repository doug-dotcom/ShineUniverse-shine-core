-- Historical production backfill: revocation freshness policy v1.
-- Mirrors migration 20260926221929.

create table foundation.app_revocation_runtime_policies (
  app_id text primary key references foundation.app_registry(app_id),
  max_pending_age_seconds integer not null default 900
    check (max_pending_age_seconds between 60 and 86400),
  stale_action text not null default 'observe'
    check (stale_action in ('observe','degrade-connected','deny-connected')),
  updated_at timestamptz not null default now()
);

comment on table foundation.app_revocation_runtime_policies is
  'Optional per-app revocation freshness overrides. Missing rows use Foundation defaults: 900 seconds, observe-only.';

alter table foundation.app_revocation_runtime_policies enable row level security;

create policy foundation_runtime_revocation_runtime_policies_select
on foundation.app_revocation_runtime_policies
for select
to foundation_runtime
using (true);

revoke all on foundation.app_revocation_runtime_policies
from public,anon,authenticated;

grant select on foundation.app_revocation_runtime_policies
to foundation_runtime,service_role;

create or replace function foundation.get_app_revocation_health_v1(
  p_app_id text
)
returns table(
  app_id text,
  checkpoint_sequence bigint,
  latest_sequence bigint,
  pending_count bigint,
  oldest_pending_at timestamptz,
  pending_age_seconds bigint,
  max_pending_age_seconds integer,
  freshness_state text,
  stale_action text,
  recommended_action text
)
language plpgsql
security definer
set search_path = pg_catalog, foundation
as $function$
declare
  s record;
  max_age integer;
  action text;
  age_seconds bigint;
  freshness text;
  recommendation text;
begin
  if p_app_id is null
     or p_app_id !~ '^shine\.[a-z0-9][a-z0-9-]*$' then
    raise exception 'invalid-revocation-health-request' using errcode='22023';
  end if;

  if not exists (
    select 1
    from foundation.app_registry
    where app_registry.app_id=p_app_id
      and app_registry.status='active'
  ) then
    raise exception 'app-unregistered' using errcode='22023';
  end if;

  select * into s
  from foundation.get_app_revocation_status_v1(p_app_id);

  select
    coalesce(p.max_pending_age_seconds,900),
    coalesce(p.stale_action,'observe')
  into max_age,action
  from (select 1) seed
  left join foundation.app_revocation_runtime_policies p
    on p.app_id=p_app_id;

  if coalesce(s.pending_count,0)=0 then
    age_seconds := 0;
    freshness := 'current';
    recommendation := 'none';
  else
    age_seconds := greatest(
      0,
      floor(extract(epoch from (clock_timestamp()-s.oldest_pending_at)))::bigint
    );

    if age_seconds <= max_age then
      freshness := 'pending';
      recommendation := 'consume-revocations';
    else
      freshness := 'stale';
      recommendation := action;
    end if;
  end if;

  return query
  select
    p_app_id,
    coalesce(s.checkpoint_sequence,0)::bigint,
    coalesce(s.latest_sequence,0)::bigint,
    coalesce(s.pending_count,0)::bigint,
    s.oldest_pending_at,
    age_seconds,
    max_age,
    freshness,
    action,
    recommendation;
end;
$function$;

revoke all on function foundation.get_app_revocation_health_v1(text)
from public,anon,authenticated,service_role;

grant execute on function foundation.get_app_revocation_health_v1(text)
to foundation_runtime;
