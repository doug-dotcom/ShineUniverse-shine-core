-- Hosted-only pg_net extension schema hardening.
-- One-time migration for existing projects where pg_net was installed with
-- extension metadata in public. Fresh installs use automatic-health-collector-hosted-v1.sql.
--
-- Preconditions:
--   * pg_net exists in public
--   * all pg_net cron producers/harvesters are paused externally
--   * all Foundation/Defence pg_net responses are harvested
--   * net.http_request_queue is empty
--
-- The transaction preserves net._http_response history and request-id continuity.

begin;

create schema if not exists extensions;

do $pg_net_preflight$
declare
  v_schema text;
  v_version text;
  v_queue_count bigint;
  v_pending_defence_health bigint;
  v_pending_service_health bigint;
  v_pending_runtime_receipts bigint;
begin
  select n.nspname,e.extversion
    into v_schema,v_version
  from pg_extension e
  join pg_namespace n on n.oid=e.extnamespace
  where e.extname='pg_net';

  if v_schema is null then
    raise exception 'pg-net-hardening-extension-missing';
  end if;

  if v_schema<>'public' then
    raise exception 'pg-net-hardening-unexpected-extension-schema:%',v_schema;
  end if;

  select count(*) into v_queue_count
  from net.http_request_queue;

  select count(*) into v_pending_defence_health
  from foundation.defence_health_probe_requests q
  left join foundation.defence_health_probe_results r using(probe_request_id)
  where r.probe_request_id is null;

  select count(*) into v_pending_service_health
  from foundation.service_health_probe_requests q
  left join foundation.service_health_probe_results r using(probe_request_id)
  where r.probe_request_id is null;

  select count(*) into v_pending_runtime_receipts
  from foundation.defence_supabase_runtime_receipt_requests q
  where not exists (
    select 1
    from foundation.defence_supabase_runtime_receipt_observations o
    where o.target_id=q.target_id
      and o.observed_at>=q.queued_at
  );

  if v_queue_count<>0
     or v_pending_defence_health<>0
     or v_pending_service_health<>0
     or v_pending_runtime_receipts<>0 then
    raise exception
      'pg-net-hardening-not-drained:queue=%,defence=%,service=%,runtime=%',
      v_queue_count,v_pending_defence_health,
      v_pending_service_health,v_pending_runtime_receipts;
  end if;

  raise notice 'pg_net % preflight passed',v_version;
end;
$pg_net_preflight$;

lock table net.http_request_queue in access exclusive mode;
lock table net._http_response in access exclusive mode;

create temporary table pg_net_response_backup on commit drop as
select
  id,status_code,content_type,headers,content,timed_out,error_msg,created
from net._http_response;

create temporary table pg_net_state_backup on commit drop as
select
  (select last_value from net.http_request_queue_id_seq) as last_value,
  (select is_called from net.http_request_queue_id_seq) as is_called,
  (select count(*) from net._http_response) as response_count;

drop extension pg_net;
create extension pg_net with schema extensions;

insert into net._http_response(
  id,status_code,content_type,headers,content,timed_out,error_msg,created
)
select
  id,status_code,content_type,headers,content,timed_out,error_msg,created
from pg_net_response_backup;

select setval(
  'net.http_request_queue_id_seq',
  (select last_value from pg_net_state_backup),
  (select is_called from pg_net_state_backup)
);

do $pg_net_verify$
declare
  v_schema text;
  v_restored_count bigint;
  v_expected_count bigint;
  v_sequence bigint;
  v_expected_sequence bigint;
begin
  select n.nspname
    into v_schema
  from pg_extension e
  join pg_namespace n on n.oid=e.extnamespace
  where e.extname='pg_net';

  select count(*) into v_restored_count from net._http_response;
  select response_count,last_value
    into v_expected_count,v_expected_sequence
  from pg_net_state_backup;
  select last_value into v_sequence from net.http_request_queue_id_seq;

  if v_schema<>'extensions' then
    raise exception 'pg-net-hardening-schema-verification-failed:%',v_schema;
  end if;

  if v_restored_count<>v_expected_count then
    raise exception 'pg-net-hardening-response-restore-mismatch:%/%',
      v_restored_count,v_expected_count;
  end if;

  if v_sequence<>v_expected_sequence then
    raise exception 'pg-net-hardening-sequence-restore-mismatch:%/%',
      v_sequence,v_expected_sequence;
  end if;

  if not has_schema_privilege('service_role','net','USAGE')
     or not has_function_privilege(
       'service_role',
       'net.http_get(text,jsonb,jsonb,integer)',
       'EXECUTE'
     )
     or not has_table_privilege(
       'service_role',
       'net._http_response',
       'SELECT'
     ) then
    raise exception 'pg-net-hardening-service-role-privilege-mismatch';
  end if;
end;
$pg_net_verify$;

commit;
