do $$
declare
  fn text;
begin
  select pg_get_functiondef(p.oid) into fn
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='cancel_concierge_request_v1'
  limit 1;

  if fn is null
     or position('effective_reason' in fn)=0
     or position('reasonCode'',effective_reason' in fn)=0 then
    raise exception 'Concierge cancellation reason fidelity is not installed';
  end if;
end;
$$;
