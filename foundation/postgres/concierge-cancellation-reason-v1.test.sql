do $$
declare
  body text;
begin
  select pg_get_functiondef(p.oid) into body
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='cancel_concierge_request_v1'
  limit 1;

  if body is null or position('effective_reason' in body)=0 then
    raise exception 'concierge cancellation reason fidelity missing';
  end if;
  if position('superseded-by-newer-request' in 'superseded-by-newer-request')=0 then
    raise exception 'test fixture invalid';
  end if;
end;
$$;
