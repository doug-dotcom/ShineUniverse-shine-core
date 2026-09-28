begin;

do $$
begin
  if to_regclass('foundation.concierge_retirement_events') is not null then
    if exists (
      select 1
      from pg_tables
      where schemaname='foundation'
        and tablename='concierge_retirement_events'
        and not rowsecurity
    ) then
      raise exception 'concierge_retirement_events must have RLS';
    end if;

    if has_table_privilege('anon','foundation.concierge_retirement_events','SELECT')
       or has_table_privilege('authenticated','foundation.concierge_retirement_events','SELECT') then
      raise exception 'public roles must not read concierge retirement events';
    end if;
  end if;

  if to_regprocedure('foundation.cancel_concierge_request_v2(uuid,uuid,uuid,text,text,timestamptz,uuid)') is not null
     and (
       has_function_privilege('anon','foundation.cancel_concierge_request_v2(uuid,uuid,uuid,text,text,timestamptz,uuid)','EXECUTE')
       or has_function_privilege('authenticated','foundation.cancel_concierge_request_v2(uuid,uuid,uuid,text,text,timestamptz,uuid)','EXECUTE')
     ) then
    raise exception 'cancel_concierge_request_v2 must not be public';
  end if;

  if to_regprocedure('foundation.concierge_request_is_retired_v1(uuid)') is not null
     and (
       has_function_privilege('anon','foundation.concierge_request_is_retired_v1(uuid)','EXECUTE')
       or has_function_privilege('authenticated','foundation.concierge_request_is_retired_v1(uuid)','EXECUTE')
     ) then
    raise exception 'concierge_request_is_retired_v1 must not be public';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v4(uuid,integer,timestamptz)') is not null
     and (
       has_function_privilege('anon','foundation.list_user_concierge_jobs_v4(uuid,integer,timestamptz)','EXECUTE')
       or has_function_privilege('authenticated','foundation.list_user_concierge_jobs_v4(uuid,integer,timestamptz)','EXECUTE')
     ) then
    raise exception 'list_user_concierge_jobs_v4 must not be public';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v5(uuid,integer,timestamptz)') is not null
     and (
       has_function_privilege('anon','foundation.list_user_concierge_jobs_v5(uuid,integer,timestamptz)','EXECUTE')
       or has_function_privilege('authenticated','foundation.list_user_concierge_jobs_v5(uuid,integer,timestamptz)','EXECUTE')
     ) then
    raise exception 'list_user_concierge_jobs_v5 must not be public';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz)') is not null
     and (
       has_function_privilege('anon','foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz)','EXECUTE')
       or has_function_privilege('authenticated','foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz)','EXECUTE')
     ) then
    raise exception 'list_user_concierge_jobs_v6 must not be public';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v7(uuid,integer,timestamptz,timestamptz)') is not null
     and (
       has_function_privilege('anon','foundation.list_user_concierge_jobs_v7(uuid,integer,timestamptz,timestamptz)','EXECUTE')
       or has_function_privilege('authenticated','foundation.list_user_concierge_jobs_v7(uuid,integer,timestamptz,timestamptz)','EXECUTE')
     ) then
    raise exception 'list_user_concierge_jobs_v7 must not be public';
  end if;

  if to_regprocedure('foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz)') is not null
     and (
       has_function_privilege('anon','foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz)','EXECUTE')
       or has_function_privilege('authenticated','foundation.list_user_concierge_jobs_v6(uuid,integer,timestamptz,timestamptz)','EXECUTE')
     ) then
    raise exception 'list_user_concierge_jobs_v6 must not be public';
  end if;

  if to_regprocedure('foundation.retire_stale_concierge_requests_v1(timestamptz,interval,integer)') is not null
     and (
       has_function_privilege('anon','foundation.retire_stale_concierge_requests_v1(timestamptz,interval,integer)','EXECUTE')
       or has_function_privilege('authenticated','foundation.retire_stale_concierge_requests_v1(timestamptz,interval,integer)','EXECUTE')
     ) then
    raise exception 'retire_stale_concierge_requests_v1 must not be public';
  end if;
end;
$$;

rollback;
