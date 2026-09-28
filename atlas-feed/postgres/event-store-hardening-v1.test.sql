begin;

do $$
declare
  event_policies integer;
  receipt_policies integer;
begin
  select count(*) into event_policies
  from pg_catalog.pg_policies
  where schemaname='foundation'
    and tablename='atlas_feed_events'
    and policyname='atlas_feed_events_client_deny'
    and permissive='RESTRICTIVE'
    and roles @> array['anon','authenticated']::name[];

  select count(*) into receipt_policies
  from pg_catalog.pg_policies
  where schemaname='foundation'
    and tablename='atlas_feed_persistence_receipts'
    and policyname='atlas_feed_receipts_client_deny'
    and permissive='RESTRICTIVE'
    and roles @> array['anon','authenticated']::name[];

  if event_policies<>1 or receipt_policies<>1 then
    raise exception 'Atlas deny-all client policies are missing';
  end if;

  if has_table_privilege('anon','foundation.atlas_feed_events','SELECT')
     or has_table_privilege('authenticated','foundation.atlas_feed_events','SELECT')
     or has_table_privilege('anon','foundation.atlas_feed_persistence_receipts','SELECT')
     or has_table_privilege('authenticated','foundation.atlas_feed_persistence_receipts','SELECT') then
    raise exception 'Atlas client roles gained direct table access';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname='foundation'
      and tablename='atlas_feed_events'
      and indexname='atlas_feed_events_source_capability_fk_idx'
  ) or not exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname='foundation'
      and tablename='atlas_feed_events'
      and indexname='atlas_feed_events_publisher_credential_app_fk_idx'
  ) or not exists (
    select 1 from pg_catalog.pg_indexes
    where schemaname='foundation'
      and tablename='atlas_feed_persistence_receipts'
      and indexname='atlas_feed_receipts_publisher_capability_fk_idx'
  ) then
    raise exception 'Atlas composite foreign keys are not fully indexed';
  end if;
end;
$$;

rollback;
