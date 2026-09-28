do $$
declare
  fn text;
begin
  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='retire_concierge_request_if_expired_v1'
  limit 1;

  if fn is null
     or position('interval ''1 hour''' in fn)=0
     or position('concierge_execution_events' in fn)=0
     or position('concierge_step_checkpoints' in fn)=0
     or position('concierge_retry_jobs' in fn)=0 then
    raise exception 'Synchronous Concierge plan TTL helper incomplete';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='gate_concierge_execution_v1'
  limit 1;

  if fn is null
     or position('retire_concierge_request_if_expired_v1' in fn)=0
     or position('concierge-plan-expired' in fn)=0
     or position('retirement' in fn)=0 then
    raise exception 'Execution gate does not enforce synchronous plan TTL';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='issue_capability_invocation_ticket_v2'
  limit 1;

  if fn is null
     or position('retire_concierge_request_if_expired_v1' in fn)=0 then
    raise exception 'Ticket issuance does not enforce synchronous plan TTL';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='record_concierge_step_checkpoint_v1'
  limit 1;

  if fn is null
     or position('retire_concierge_request_if_expired_v1' in fn)=0 then
    raise exception 'Checkpoint write does not enforce synchronous plan TTL';
  end if;
end;
$$;
