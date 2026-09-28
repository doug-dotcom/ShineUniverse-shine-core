begin;

do $$
begin
  if to_regprocedure('foundation.retire_concierge_request_if_expired_v1(uuid,uuid,text,timestamptz,interval)') is not null
     and (
       has_function_privilege(
         'anon',
         'foundation.retire_concierge_request_if_expired_v1(uuid,uuid,text,timestamptz,interval)',
         'EXECUTE'
       )
       or has_function_privilege(
         'authenticated',
         'foundation.retire_concierge_request_if_expired_v1(uuid,uuid,text,timestamptz,interval)',
         'EXECUTE'
       )
     ) then
    raise exception 'five-argument retirement helper must not be public';
  end if;

  if to_regprocedure('foundation.retire_concierge_request_if_expired_v1(uuid,timestamptz,interval)') is not null
     and (
       has_function_privilege(
         'anon',
         'foundation.retire_concierge_request_if_expired_v1(uuid,timestamptz,interval)',
         'EXECUTE'
       )
       or has_function_privilege(
         'authenticated',
         'foundation.retire_concierge_request_if_expired_v1(uuid,timestamptz,interval)',
         'EXECUTE'
       )
     ) then
    raise exception 'three-argument retirement helper must not be public';
  end if;
end;
$$;

rollback;
