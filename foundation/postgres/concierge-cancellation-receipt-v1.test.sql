do $$
declare
  fn text;
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema='foundation'
      and table_name='concierge_cancellation_events'
      and column_name='receipt_sha256'
  ) then
    raise exception 'cancellation receipt hash column missing';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='cancel_concierge_request_v2'
  limit 1;

  if fn is null
     or position('completedBeforeCancellation' in fn)=0
     or position('supersededByRequestId' in fn)=0
     or position('extensions.digest' in fn)=0 then
    raise exception 'cancellation receipt v2 contract incomplete';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='record_concierge_step_checkpoint_v1'
  limit 1;

  if fn is null
     or position('for share' in lower(fn))=0
     or position('concierge_request_is_cancelled_v1' in fn)=0 then
    raise exception 'checkpoint cancellation serialization missing';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='list_user_concierge_jobs_v4'
  limit 1;

  if fn is null
     or position('cancellationReceipt' in fn)=0
     or position('receiptSha256' in fn)=0 then
    raise exception 'task-centre cancellation receipt projection missing';
  end if;
end;
$$;
