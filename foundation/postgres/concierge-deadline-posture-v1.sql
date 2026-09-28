create or replace function foundation.list_user_concierge_jobs_v7(
  p_owner_shine_id uuid,p_limit integer default 50,p_before timestamptz default null,p_as_of timestamptz default clock_timestamp()
) returns jsonb language sql security definer set search_path to 'pg_catalog','foundation' as $function$
with source as (select foundation.list_user_concierge_jobs_v6(p_owner_shine_id,p_limit,p_before,p_as_of) payload),
enriched as (
 select item || jsonb_build_object('deadlinePosture',
  case
   when item->'planTtl'->>'state'='terminal' then jsonb_build_object('state','terminal','attentionRequired',false,'reasonCode','concierge-plan-terminal','action','none','automaticExecutionTriggered',false)
   when item->'planTtl'->>'state'='started-exempt' then jsonb_build_object('state','started-exempt','attentionRequired',false,'reasonCode','concierge-execution-already-started','action','continue-running','automaticExecutionTriggered',false)
   when item->'planTtl'->>'state'='expiry-due' then jsonb_build_object('state','expiry-due','attentionRequired',true,'reasonCode','concierge-plan-expiry-due','action','retire-before-execution','automaticExecutionTriggered',false)
   when item->'planTtl'->>'state'='counting-down' and (item->'planTtl'->>'secondsRemaining')::integer<=600 then jsonb_build_object('state','start-soon','attentionRequired',true,'reasonCode','concierge-plan-near-expiry','action','start-or-retire','automaticExecutionTriggered',false)
   else jsonb_build_object('state','normal','attentionRequired',false,'reasonCode','concierge-plan-within-ttl','action','none','automaticExecutionTriggered',false)
  end) item
 from source cross join lateral jsonb_array_elements(source.payload->'items') item
), assembled as (
 select coalesce(jsonb_agg(item order by case item->'deadlinePosture'->>'state' when 'expiry-due' then 0 when 'start-soon' then 1 else 2 end,coalesce((item->>'attentionOrder')::integer,999),(item->>'requestedAt')::timestamptz,item->>'requestId'),'[]'::jsonb) items from enriched
)
select jsonb_build_object(
 'privacy',(select payload->'privacy' from source),
 'summary',(select payload->'summary' from source)||jsonb_build_object(
  'deadlineAttention',(select count(*) from jsonb_array_elements(assembled.items)x where x->'deadlinePosture'->>'state' in('start-soon','expiry-due')),
  'startSoon',(select count(*) from jsonb_array_elements(assembled.items)x where x->'deadlinePosture'->>'state'='start-soon'),
  'expiryDue',(select count(*) from jsonb_array_elements(assembled.items)x where x->'deadlinePosture'->>'state'='expiry-due')),
 'ordering',(select payload->'ordering' from source)||jsonb_build_object('deadlineAware',true,'deadlinePriority',jsonb_build_array('expiry-due','start-soon')),
 'receiptContract',(select payload->'receiptContract' from source),
 'planTtlContract',(select payload->'planTtlContract' from source),
 'deadlinePostureContract',jsonb_build_object('version','shine-foundation/concierge-deadline-posture-v1','startSoonThresholdSeconds',600,'automaticExecutionTriggered',false,'automaticRetryTriggered',false,'readMutatesState',false,'source','foundation-server'),
 'serverTime',(select payload->'serverTime' from source),'items',assembled.items) from assembled;
$function$;