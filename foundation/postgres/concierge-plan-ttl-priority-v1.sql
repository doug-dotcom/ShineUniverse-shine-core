CREATE OR REPLACE FUNCTION foundation.list_user_concierge_jobs_v7(p_owner_shine_id uuid, p_limit integer DEFAULT 50, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_as_of timestamp with time zone DEFAULT clock_timestamp())
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
with source as (
  select foundation.list_user_concierge_jobs_v6(
    p_owner_shine_id,p_limit,p_before,p_as_of
  ) as payload
),
enriched as (
  select
    item ||
    jsonb_build_object(
      'planUrgency',
      case
        when item->'planTtl'->>'state'='expiry-due' then
          jsonb_build_object(
            'state','expiry-due',
            'priority','critical',
            'reasonCode','concierge-plan-expiry-due',
            'warningThresholdSeconds',900,
            'secondsRemaining',0,
            'requiresUserAttention',true,
            'autoStartsExecution',false
          )
        when item->'planTtl'->>'state'='counting-down'
          and (item->'planTtl'->>'secondsRemaining')::integer<=900 then
          jsonb_build_object(
            'state','expiring-soon',
            'priority','high',
            'reasonCode','concierge-plan-expires-soon',
            'warningThresholdSeconds',900,
            'secondsRemaining',(item->'planTtl'->>'secondsRemaining')::integer,
            'requiresUserAttention',true,
            'autoStartsExecution',false
          )
        when item->'planTtl'->>'state'='counting-down' then
          jsonb_build_object(
            'state','normal',
            'priority','normal',
            'reasonCode','concierge-plan-within-ttl',
            'warningThresholdSeconds',900,
            'secondsRemaining',(item->'planTtl'->>'secondsRemaining')::integer,
            'requiresUserAttention',false,
            'autoStartsExecution',false
          )
        else jsonb_build_object(
          'state','not-applicable',
          'priority','none',
          'reasonCode',coalesce(item->'planTtl'->>'reasonCode','concierge-plan-ttl-not-applicable'),
          'warningThresholdSeconds',900,
          'secondsRemaining',null,
          'requiresUserAttention',false,
          'autoStartsExecution',false
        )
      end,
      'attentionRequired',
      case
        when item->'planTtl'->>'state'='expiry-due' then true
        when item->'planTtl'->>'state'='counting-down'
          and (item->'planTtl'->>'secondsRemaining')::integer<=900 then true
        else coalesce((item->>'attentionRequired')::boolean,false)
      end,
      'attentionReason',
      case
        when (item ->> 'nextAction'::text) = ANY (ARRAY['review-updated-consent'::text, 'review-consent'::text]) THEN item ->> 'attentionReason'::text
        when (item -> 'planTtl'::text) ->> 'state'::text = 'expiry-due'::text THEN 'Plan expired — send a fresh request'::text
        when (item -> 'planTtl'::text) ->> 'state'::text = 'counting-down'::text AND (((item -> 'planTtl'::text) ->> 'secondsRemaining'::text))::integer <= 900 THEN 'Plan expires soon'::text
        when (item ->> 'nextAction'::text) = ANY (ARRAY['review-failure'::text, 'review-partial-result'::text]) THEN item ->> 'attentionReason'::text
        else item ->> 'attentionReason'::text
      end,
      'attentionOrder',
      case
        when item->>'nextAction' in ('review-updated-consent','review-consent')
          then (item->>'attentionOrder')::integer
        when item->'planTtl'->>'state'='expiry-due' then 25
        when item->>'nextAction' in ('review-failure','review-partial-result')
          then (item->>'attentionOrder')::integer
        when item->'planTtl'->>'state'='counting-down'
          and (item->'planTtl'->>'secondsRemaining')::integer<=900 then 45
        else coalesce((item->>'attentionOrder')::integer,999)
      end,
      'nextAction',
      case
        when item->>'nextAction' in ('review-updated-consent','review-consent')
          then item->>'nextAction'
        when item->'planTtl'->>'state'='expiry-due'
          then 'send-fresh-request'
        when item->'planTtl'->>'state'='counting-down'
          and (item->'planTtl'->>'secondsRemaining')::integer<=900
          then 'review-before-expiry'
        else item->>'nextAction'
      end
    ) as item
  from source
  cross join lateral jsonb_array_elements(source.payload->'items') item
),
assembled as (
  select coalesce(
    jsonb_agg(
      item order by
        coalesce((item->>'attentionOrder')::integer,999),
        (item->>'requestedAt')::timestamptz,
        item->>'requestId'
    ),
    '[]'::jsonb
  ) as items
  from enriched
)
select jsonb_build_object(
  'privacy',(select payload->'privacy' from source),
  'summary',jsonb_build_object(
    'total',jsonb_array_length(assembled.items),
    'attentionRequired',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where coalesce((x->>'attentionRequired')::boolean,false)
    ),
    'automatic',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where x->>'waitingOn' in ('companion','specialist')
        and not coalesce((x->>'attentionRequired')::boolean,false)
        and x->>'status' not in ('completed','failed','cancelled','retired')
    ),
    'completed',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where x->>'status'='completed'
    ),
    'cancelled',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where x->>'status'='cancelled'
    ),
    'superseded',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where x->>'status'='cancelled'
        and x->>'supersededByRequestId' is not null
    ),
    'retired',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where x->>'status'='retired'
    ),
    'expiringSoon',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where x->'planUrgency'->>'state'='expiring-soon'
    ),
    'expiryDue',(
      select count(*) from jsonb_array_elements(assembled.items) x
      where x->'planUrgency'->>'state'='expiry-due'
    )
  ),
  'ordering',
    (select payload->'ordering' from source) ||
    jsonb_build_object(
      'ttlUrgencyUsed',true,
      'ttlUrgencyWarningSeconds',900,
      'aiPriorityScoreUsed',false
    ),
  'receiptContract',(select payload->'receiptContract' from source),
  'planTtlContract',
    (select payload->'planTtlContract' from source) ||
    jsonb_build_object(
      'warningSeconds',900,
      'urgencyChangesExecution',false,
      'urgencyAutoStartsWork',false
    ),
  'serverTime',(select payload->'serverTime' from source),
  'items',assembled.items
)
from assembled;
$function$

