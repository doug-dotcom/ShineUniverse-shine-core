create or replace function foundation.list_user_concierge_jobs_v6(
  p_owner_shine_id uuid,
  p_limit integer default 50,
  p_before timestamptz default null,
  p_as_of timestamptz default clock_timestamp()
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','foundation'
as $function$
with source as (
  select foundation.list_user_concierge_jobs_v5(p_owner_shine_id,p_limit,p_before) as payload
),
enriched as (
  select item || jsonb_build_object(
    'planTtl',
    case
      when item->>'status' in ('completed','failed','cancelled','retired') then
        jsonb_build_object('applies',false,'state','terminal','reasonCode','concierge-plan-terminal','expiresAt',null,'secondsRemaining',null,'serverTime',p_as_of)
      when exists (
        select 1 from foundation.concierge_execution_events e
        where e.request_id=(item->>'requestId')::uuid
          and e.event_type in ('execution-started','execution-completed','execution-failed')
      )
      or exists (select 1 from foundation.concierge_step_checkpoints cp where cp.request_id=(item->>'requestId')::uuid)
      or exists (select 1 from foundation.concierge_retry_jobs r where r.request_id=(item->>'requestId')::uuid)
      then jsonb_build_object('applies',false,'state','started-exempt','reasonCode','concierge-execution-already-started','expiresAt',null,'secondsRemaining',null,'serverTime',p_as_of)
      when (item->>'requestedAt')::timestamptz+interval '1 hour'<=p_as_of then
        jsonb_build_object('applies',true,'state','expiry-due','reasonCode','concierge-plan-expiry-due','expiresAt',(item->>'requestedAt')::timestamptz+interval '1 hour','secondsRemaining',0,'serverTime',p_as_of)
      else jsonb_build_object('applies',true,'state','counting-down','reasonCode','concierge-plan-within-ttl','expiresAt',(item->>'requestedAt')::timestamptz+interval '1 hour','secondsRemaining',ceil(extract(epoch from ((item->>'requestedAt')::timestamptz+interval '1 hour'-p_as_of)))::integer,'serverTime',p_as_of)
    end
  ) as item
  from source
  cross join lateral jsonb_array_elements(source.payload->'items') item
),
assembled as (
  select coalesce(jsonb_agg(item order by coalesce((item->>'attentionOrder')::integer,999),(item->>'requestedAt')::timestamptz,item->>'requestId'),'[]'::jsonb) as items
  from enriched
)
select jsonb_build_object(
  'privacy',(select payload->'privacy' from source),
  'summary',(select payload->'summary' from source),
  'ordering',(select payload->'ordering' from source),
  'receiptContract',(select payload->'receiptContract' from source),
  'planTtlContract',jsonb_build_object(
    'version','shine-foundation/concierge-plan-ttl-v1',
    'ttlSeconds',3600,
    'computedBy','foundation-server',
    'clientClockAuthoritative',false,
    'startedExecutionExempt',true,
    'expiryDueMutatesState',false
  ),
  'serverTime',p_as_of,
  'items',assembled.items
)
from assembled;
$function$;
