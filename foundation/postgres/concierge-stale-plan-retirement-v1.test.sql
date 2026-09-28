do $$
declare
  fn text;
begin
  if not exists (
    select 1 from information_schema.tables
    where table_schema='foundation'
      and table_name='concierge_retirement_events'
  ) then
    raise exception 'Concierge retirement table missing';
  end if;

  if not exists (
    select 1 from cron.job
    where jobname='shine-foundation-concierge-retire-stale-15m'
      and active=true
  ) then
    raise exception 'Concierge stale-plan retirement cron missing';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='retire_stale_concierge_requests_v1'
  limit 1;
  if fn is null
     or position('concierge_execution_events' in fn)=0
     or position('concierge_step_checkpoints' in fn)=0
     or position('concierge_retry_jobs' in fn)=0
     or position('concierge_cancellation_events' in fn)=0 then
    raise exception 'Stale-plan retirement safety predicates incomplete';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='issue_capability_invocation_ticket_v2'
  limit 1;
  if fn is null or position('concierge_request_is_retired_v1' in fn)=0 then
    raise exception 'Retired request ticket guard missing';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.relnamespace
  where false;
exception when undefined_column then
  null;
end;
$$;

do $$
declare
  fn text;
begin
  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='record_concierge_step_checkpoint_v1'
  limit 1;
  if fn is null or position('concierge_request_is_retired_v1' in fn)=0 then
    raise exception 'Retired request checkpoint guard missing';
  end if;

  select pg_get_functiondef(p.oid) into fn
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='foundation'
    and p.proname='list_user_concierge_jobs_v5'
  limit 1;
  if fn is null
     or position('retirementReceipt' in fn)=0
     or position('retirementReceiptIntegrity' in fn)=0 then
    raise exception 'Retired task-centre projection missing';
  end if;
end;
$$;
