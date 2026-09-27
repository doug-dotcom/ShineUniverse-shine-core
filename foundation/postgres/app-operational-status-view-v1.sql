-- Historical production backfill: unified app operational status view.
-- Mirrors migration 20260926235144. A later production migration replaced this
-- view with the security-definer function checked in alongside it.

create view foundation.app_operational_status
with (security_invoker = true)
as
with checkpoint as (
  select app_id,last_sequence_no,last_ack_at
  from foundation.app_revocation_checkpoints
),
revocation_rollup as (
  select
    g.app_id,
    max(o.sequence_no)::bigint as latest_sequence,
    min(o.created_at) as oldest_outbox_at
  from foundation.revocation_outbox o
  join foundation.access_grants g
    on g.grant_id=o.grant_id
   and g.owner_shine_id=o.owner_shine_id
  group by g.app_id
),
pending as (
  select
    g.app_id,
    count(*) filter (
      where o.sequence_no > coalesce(c.last_sequence_no,0)
    )::bigint as pending_count,
    min(o.created_at) filter (
      where o.sequence_no > coalesce(c.last_sequence_no,0)
    ) as oldest_pending_at
  from foundation.revocation_outbox o
  join foundation.access_grants g
    on g.grant_id=o.grant_id
   and g.owner_shine_id=o.owner_shine_id
  left join checkpoint c on c.app_id=g.app_id
  group by g.app_id
),
combined as (
  select
    s.*,
    coalesce(c.last_sequence_no,0)::bigint as revocation_checkpoint_sequence,
    c.last_ack_at as revocation_last_ack_at,
    coalesce(r.latest_sequence,0)::bigint as revocation_latest_sequence,
    coalesce(p.pending_count,0)::bigint as revocation_pending_count,
    p.oldest_pending_at as revocation_oldest_pending_at,
    case
      when coalesce(p.pending_count,0)=0 then 0::bigint
      else greatest(
        0,
        floor(extract(epoch from (clock_timestamp()-p.oldest_pending_at)))::bigint
      )
    end as revocation_pending_age_seconds,
    coalesce(pol.max_pending_age_seconds,900)::integer as revocation_max_pending_age_seconds,
    coalesce(pol.stale_action,'observe')::text as revocation_stale_action
  from foundation.app_connection_status s
  left join checkpoint c on c.app_id=s.app_id
  left join revocation_rollup r on r.app_id=s.app_id
  left join pending p on p.app_id=s.app_id
  left join foundation.app_revocation_runtime_policies pol on pol.app_id=s.app_id
)
select
  combined.*,
  case
    when combined.revocation_pending_count=0 then 'current'
    when combined.revocation_pending_age_seconds <= combined.revocation_max_pending_age_seconds then 'pending'
    else 'stale'
  end as revocation_freshness_state,
  case
    when combined.registry_status <> 'active' then 'disabled'
    when combined.revocation_pending_count=0 then combined.connection_state
    when combined.revocation_pending_age_seconds <= combined.revocation_max_pending_age_seconds
      then 'revocation-pending'
    when combined.revocation_stale_action='observe'
      then 'revocation-stale-observed'
    when combined.revocation_stale_action='degrade-connected'
      then 'revocation-stale-degrade-connected'
    when combined.revocation_stale_action='deny-connected'
      then 'revocation-stale-deny-connected'
    else 'revocation-stale'
  end as operational_state,
  case
    when combined.registry_status <> 'active' then 'disabled'
    when combined.revocation_pending_count=0 then 'healthy'
    when combined.revocation_pending_age_seconds <= combined.revocation_max_pending_age_seconds
      then 'attention'
    when combined.revocation_stale_action='observe'
      then 'attention'
    else 'degraded'
  end as operational_health
from combined;

comment on view foundation.app_operational_status is
  'Unified Foundation app readiness plus revocation-delivery freshness. Observe-only policies affect status, not access, unless a later explicit enforcement layer opts in.';

revoke all on foundation.app_operational_status
from public,anon,authenticated;

grant select on foundation.app_operational_status
to foundation_runtime,service_role;
