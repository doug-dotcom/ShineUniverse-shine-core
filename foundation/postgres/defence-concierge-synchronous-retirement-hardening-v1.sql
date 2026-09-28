-- Shine Defence hardening for synchronous Concierge retirement helpers v1.

do $$
begin
  if to_regprocedure('foundation.retire_concierge_request_if_expired_v1(uuid,uuid,text,timestamptz,interval)') is not null then
    execute 'revoke all on function foundation.retire_concierge_request_if_expired_v1(uuid,uuid,text,timestamptz,interval) from public,anon,authenticated';
    execute 'grant execute on function foundation.retire_concierge_request_if_expired_v1(uuid,uuid,text,timestamptz,interval) to foundation_gateway,service_role';
  end if;

  if to_regprocedure('foundation.retire_concierge_request_if_expired_v1(uuid,timestamptz,interval)') is not null then
    execute 'revoke all on function foundation.retire_concierge_request_if_expired_v1(uuid,timestamptz,interval) from public,anon,authenticated';
    execute 'grant execute on function foundation.retire_concierge_request_if_expired_v1(uuid,timestamptz,interval) to foundation_gateway,service_role';
  end if;
end;
$$;
