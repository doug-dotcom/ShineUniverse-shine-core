-- Shine Defence hardening for late-bound Concierge retirement objects v1.
-- Safe to apply whether or not Layer 194 objects are present yet.

do $$
begin
  if to_regclass('foundation.concierge_retirement_events') is not null then
    execute 'alter table foundation.concierge_retirement_events enable row level security';
    execute 'revoke all on foundation.concierge_retirement_events from public,anon,authenticated';
    execute 'grant select on foundation.concierge_retirement_events to foundation_runtime,service_role';
    execute 'grant insert on foundation.concierge_retirement_events to service_role';

    if not exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid=p.polrelid
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='foundation'
        and c.relname='concierge_retirement_events'
        and p.polname='foundation_runtime_concierge_retirement_select'
    ) then
      execute '
        create policy foundation_runtime_concierge_retirement_select
        on foundation.concierge_retirement_events
        for select
        to foundation_runtime
        using (true)
      ';
    end if;

    if to_regprocedure('foundation.reject_append_only_mutation()') is not null
       and not exists (
         select 1
         from pg_trigger t
         join pg_class c on c.oid=t.tgrelid
         join pg_namespace n on n.oid=c.relnamespace
         where n.nspname='foundation'
           and c.relname='concierge_retirement_events'
           and t.tgname='concierge_retirement_events_append_only'
           and not t.tgisinternal
       ) then
      execute '
        create trigger concierge_retirement_events_append_only
        before update or delete on foundation.concierge_retirement_events
        for each row execute function foundation.reject_append_only_mutation()
      ';
    end if;
  end if;

  if to_regprocedure('foundation.cancel_concierge_request_v2(uuid,uuid,uuid,text,text,timestamptz,uuid)') is not null then
    execute 'revoke all on function foundation.cancel_concierge_request_v2(uuid,uuid,uuid,text,text,timestamptz,uuid) from public,anon,authenticated';
    execute 'grant execute on function foundation.cancel_concierge_request_v2(uuid,uuid,uuid,text,text,timestamptz,uuid) to foundation_gateway,service_role';
  end if;

  if to_regprocedure('foundation.concierge_request_is_retired_v1(uuid)') is not null then
    execute 'revoke all on function foundation.concierge_request_is_retired_v1(uuid) from public,anon,authenticated';
    execute 'grant execute on function foundation.concierge_request_is_retired_v1(uuid) to foundation_runtime,foundation_gateway,service_role';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v4(uuid,integer,timestamptz)') is not null then
    execute 'revoke all on function foundation.list_user_concierge_jobs_v4(uuid,integer,timestamptz) from public,anon,authenticated';
    execute 'grant execute on function foundation.list_user_concierge_jobs_v4(uuid,integer,timestamptz) to foundation_gateway,service_role';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v5(uuid,integer,timestamptz)') is not null then
    execute 'revoke all on function foundation.list_user_concierge_jobs_v5(uuid,integer,timestamptz) from public,anon,authenticated';
    execute 'grant execute on function foundation.list_user_concierge_jobs_v5(uuid,integer,timestamptz) to foundation_gateway,service_role';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz)') is not null then
    execute 'revoke all on function foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz) from public,anon,authenticated';
    execute 'grant execute on function foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz) to foundation_gateway,service_role';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v7(uuid,integer,timestamptz,timestamptz)') is not null then
    execute 'revoke all on function foundation.list_user_concierge_jobs_v7(uuid,integer,timestamptz,timestamptz) from public,anon,authenticated';
    execute 'grant execute on function foundation.list_user_concierge_jobs_v7(uuid,integer,timestamptz,timestamptz) to foundation_gateway,service_role';
  end if;

  if to_regprocedure('foundation.retire_stale_concierge_requests_v1(timestamptz,interval,integer)') is not null then
    execute 'revoke all on function foundation.retire_stale_concierge_requests_v1(timestamptz,interval,integer) from public,anon,authenticated';
    execute 'grant execute on function foundation.retire_stale_concierge_requests_v1(timestamptz,interval,integer) to service_role';
  end if;
end;
$$;
