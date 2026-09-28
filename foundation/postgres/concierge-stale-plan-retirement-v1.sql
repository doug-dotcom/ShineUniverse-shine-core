create table if not exists foundation.concierge_retirement_events (
  event_id uuid primary key,
  request_id uuid not null unique references foundation.concierge_requests(request_id),
  owner_shine_id uuid not null references foundation.shine_identities(shine_id),
  client_id text not null references foundation.integration_clients(client_id),
  reason_code text not null,
  retired_at timestamptz not null,
  receipt jsonb not null check (jsonb_typeof(receipt)='object'),
  receipt_sha256 text not null check (receipt_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now()
);

create index if not exists concierge_retirement_owner_time_idx
  on foundation.concierge_retirement_events(owner_shine_id,retired_at desc);

create index if not exists concierge_retirement_client_idx
  on foundation.concierge_retirement_events(client_id);

CREATE OR REPLACE FUNCTION foundation.concierge_request_is_retired_v1(p_request_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
  select exists (
    select 1
    from foundation.concierge_retirement_events r
    where r.request_id=p_request_id
  );
$function$


CREATE OR REPLACE FUNCTION foundation.retire_stale_concierge_requests_v1(p_as_of timestamp with time zone DEFAULT clock_timestamp(), p_min_age interval DEFAULT '01:00:00'::interval, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  r record;
  v_receipt jsonb;
  v_hash text;
  v_retired integer:=0;
  v_ids uuid[]:=array[]::uuid[];
begin
  if p_as_of is null
     or p_min_age < interval '30 minutes'
     or p_min_age > interval '24 hours'
     or p_limit < 1 or p_limit > 500 then
    raise exception 'invalid-concierge-retirement-request' using errcode='22023';
  end if;

  for r in
    select q.*
    from foundation.concierge_requests q
    where q.requested_at <= p_as_of-p_min_age
      and not exists (
        select 1 from foundation.concierge_execution_events e
        where e.request_id=q.request_id
      )
      and not exists (
        select 1 from foundation.concierge_step_checkpoints cp
        where cp.request_id=q.request_id
      )
      and not exists (
        select 1 from foundation.concierge_retry_jobs j
        where j.request_id=q.request_id
      )
      and not exists (
        select 1 from foundation.concierge_cancellation_events c
        where c.request_id=q.request_id
      )
      and not exists (
        select 1 from foundation.concierge_retirement_events x
        where x.request_id=q.request_id
      )
    order by q.requested_at
    for update skip locked
    limit p_limit
  loop
    v_receipt:=jsonb_build_object(
      'retirementReceipt','shine-foundation/concierge-retirement-receipt-v1',
      'schemaVersion','1.0.0',
      'requestId',r.request_id,
      'clientId',r.client_id,
      'reasonCode','unused-plan-expired',
      'requestedAt',r.requested_at,
      'retiredAt',p_as_of,
      'minimumAgeSeconds',extract(epoch from p_min_age)::integer,
      'requestedCapabilities',to_jsonb(r.requested_capabilities),
      'stepCount',r.step_count,
      'executionStarted',false,
      'specialistCheckpointCount',0,
      'retryCount',0
    );
    v_hash:=encode(
      extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),
      'hex'
    );

    insert into foundation.concierge_retirement_events(
      event_id,request_id,owner_shine_id,client_id,reason_code,retired_at,
      receipt,receipt_sha256
    ) values (
      gen_random_uuid(),r.request_id,r.owner_shine_id,r.client_id,
      'unused-plan-expired',p_as_of,v_receipt,v_hash
    );

    v_retired:=v_retired+1;
    v_ids:=array_append(v_ids,r.request_id);
  end loop;

  return jsonb_build_object(
    'status','ok',
    'retiredCount',v_retired,
    'requestIds',to_jsonb(v_ids),
    'asOf',p_as_of,
    'minimumAgeSeconds',extract(epoch from p_min_age)::integer
  );
end;
$function$


CREATE OR REPLACE FUNCTION foundation.issue_capability_invocation_ticket_v2(p_ticket_id uuid, p_concierge_request_id uuid, p_step_id uuid, p_owner_shine_id uuid, p_client_id text, p_expires_at timestamp with time zone, p_occurred_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  r foundation.concierge_requests%rowtype;
  s foundation.concierge_plan_steps%rowtype;
begin
  select * into r from foundation.concierge_requests q
  where q.request_id=p_concierge_request_id;
  if not found then raise exception 'concierge-request-not-found' using errcode='22023'; end if;
  if r.owner_shine_id<>p_owner_shine_id or r.client_id<>p_client_id then
    raise exception 'concierge-request-actor-mismatch' using errcode='22023';
  end if;

  if foundation.concierge_request_is_cancelled_v1(p_concierge_request_id) then
    raise exception 'concierge-request-cancelled' using errcode='22023';
  end if;
  if foundation.concierge_request_is_retired_v1(p_concierge_request_id) then
    raise exception 'concierge-request-retired' using errcode='22023';
  end if;

  select * into s from foundation.concierge_plan_steps x
  where x.step_id=p_step_id and x.request_id=p_concierge_request_id;
  if not found then raise exception 'concierge-step-not-found' using errcode='22023'; end if;

  if s.authorization_decision<>'allow' or s.integration_grant_id is null
     or s.executable<>true or s.capability_mode not in ('read','advisory')
     or s.invocation_state<>'live' then
    raise exception 'concierge-step-not-executable' using errcode='22023';
  end if;

  if not exists (
    select 1 from foundation.effective_integration_client_grants g
    where g.grant_id=s.integration_grant_id
      and g.owner_shine_id=p_owner_shine_id and g.client_id=p_client_id
      and g.capability_id=s.capability_id and g.purpose=r.purpose
      and g.effective_status='active'
  ) then
    raise exception 'integration-grant-no-longer-active' using errcode='22023';
  end if;

  if p_ticket_id is null or p_expires_at<=p_occurred_at
     or p_expires_at>p_occurred_at+interval '60 seconds' then
    raise exception 'invalid-invocation-ticket' using errcode='22023';
  end if;

  insert into foundation.capability_invocation_tickets(
    ticket_id,ticket_hash,concierge_request_id,step_id,
    owner_shine_id,client_id,capability_id,purpose,issued_at,expires_at
  ) values (
    p_ticket_id,null,p_concierge_request_id,p_step_id,
    p_owner_shine_id,p_client_id,s.capability_id,r.purpose,p_occurred_at,p_expires_at
  );

  return jsonb_build_object(
    'ticketId',p_ticket_id,'stepId',p_step_id,
    'capabilityId',s.capability_id,'expiresAt',p_expires_at
  );
end;
$function$


CREATE OR REPLACE FUNCTION foundation.consume_capability_invocation_ticket_v2(p_event_id uuid, p_ticket_id uuid, p_step_id uuid, p_capability_id text, p_occurred_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  t foundation.capability_invocation_tickets%rowtype;
  already_consumed boolean;
  v_app_id text;
  v_binding jsonb;
begin
  select * into t from foundation.capability_invocation_tickets x
  where x.ticket_id=p_ticket_id for update;

  if not found then return jsonb_build_object('allowed',false,'reasonCode','invocation-ticket-not-found'); end if;

  if foundation.concierge_request_is_cancelled_v1(t.concierge_request_id) then
    insert into foundation.capability_invocation_ticket_events(
      event_id,ticket_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,t.ticket_id,'denied','concierge-request-cancelled',p_occurred_at
    );
    return jsonb_build_object('allowed',false,'reasonCode','concierge-request-cancelled');
  end if;

  if foundation.concierge_request_is_retired_v1(t.concierge_request_id) then
    insert into foundation.capability_invocation_ticket_events(
      event_id,ticket_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,t.ticket_id,'denied','concierge-request-retired',p_occurred_at
    );
    return jsonb_build_object('allowed',false,'reasonCode','concierge-request-retired');
  end if;

  select exists (
    select 1 from foundation.capability_invocation_ticket_events e
    where e.ticket_id=t.ticket_id and e.event_type='consumed'
  ) into already_consumed;

  if already_consumed then
    insert into foundation.capability_invocation_ticket_events(
      event_id,ticket_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,t.ticket_id,'denied','invocation-ticket-already-consumed',p_occurred_at
    );
    return jsonb_build_object('allowed',false,'reasonCode','invocation-ticket-already-consumed');
  end if;

  if t.expires_at<=p_occurred_at then
    insert into foundation.capability_invocation_ticket_events(
      event_id,ticket_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,t.ticket_id,'denied','invocation-ticket-expired',p_occurred_at
    );
    return jsonb_build_object('allowed',false,'reasonCode','invocation-ticket-expired');
  end if;

  if t.step_id<>p_step_id or t.capability_id<>p_capability_id then
    insert into foundation.capability_invocation_ticket_events(
      event_id,ticket_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,t.ticket_id,'denied','invocation-ticket-binding-mismatch',p_occurred_at
    );
    return jsonb_build_object('allowed',false,'reasonCode','invocation-ticket-binding-mismatch');
  end if;

  if not exists (
    select 1 from foundation.effective_integration_client_grants g
    join foundation.concierge_plan_steps s on s.integration_grant_id=g.grant_id
    where s.step_id=t.step_id and g.owner_shine_id=t.owner_shine_id
      and g.client_id=t.client_id and g.capability_id=t.capability_id
      and g.purpose=t.purpose and g.effective_status='active'
  ) then
    insert into foundation.capability_invocation_ticket_events(
      event_id,ticket_id,event_type,reason_code,occurred_at
    ) values (
      p_event_id,t.ticket_id,'denied','invocation-grant-no-longer-active',p_occurred_at
    );
    return jsonb_build_object('allowed',false,'reasonCode','invocation-grant-no-longer-active');
  end if;

  select c.app_id into v_app_id
  from foundation.app_capabilities c
  where c.capability_id=t.capability_id;

  v_binding:=foundation.get_integration_subject_binding_v1(t.owner_shine_id,v_app_id);

  insert into foundation.capability_invocation_ticket_events(
    event_id,ticket_id,event_type,reason_code,occurred_at
  ) values (
    p_event_id,t.ticket_id,'consumed','invocation-ticket-consumed',p_occurred_at
  );

  return jsonb_build_object(
    'allowed',true,'reasonCode','invocation-ticket-consumed',
    'ticketId',t.ticket_id,'conciergeRequestId',t.concierge_request_id,
    'stepId',t.step_id,'capabilityId',t.capability_id,'appId',v_app_id,
    'purpose',t.purpose,'ownerShineId',t.owner_shine_id,
    'clientId',t.client_id,'appSubjectId',v_binding->>'subjectId',
    'subjectBindingStatus',v_binding->>'status'
  );
end;
$function$


CREATE OR REPLACE FUNCTION foundation.record_concierge_step_checkpoint_v1(p_checkpoint_id uuid, p_request_id uuid, p_step_id uuid, p_capability_id text, p_result jsonb, p_completed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare q foundation.concierge_requests%rowtype;
begin
  if p_result is null or jsonb_typeof(p_result)<>'object' then
    raise exception 'invalid-step-checkpoint-result' using errcode='22023';
  end if;
  if pg_column_size(p_result)>65536 then
    raise exception 'step-checkpoint-result-too-large' using errcode='22023';
  end if;

  select * into q from foundation.concierge_requests x
  where x.request_id=p_request_id for share;

  if not found then raise exception 'concierge-request-not-found' using errcode='22023'; end if;
  if foundation.concierge_request_is_cancelled_v1(p_request_id) then
    raise exception 'concierge-request-cancelled' using errcode='22023';
  end if;
  if foundation.concierge_request_is_retired_v1(p_request_id) then
    raise exception 'concierge-request-retired' using errcode='22023';
  end if;

  if not exists (
    select 1 from foundation.concierge_plan_steps s
    where s.request_id=p_request_id and s.step_id=p_step_id and s.capability_id=p_capability_id
  ) then
    raise exception 'concierge-step-binding-mismatch' using errcode='22023';
  end if;

  insert into foundation.concierge_step_checkpoints(
    checkpoint_id,request_id,step_id,capability_id,result,completed_at,expires_at
  ) values (
    p_checkpoint_id,p_request_id,p_step_id,p_capability_id,p_result,
    p_completed_at,p_completed_at+interval '24 hours'
  )
  on conflict(request_id,step_id) do nothing;

  return jsonb_build_object('recorded',true,'expiresAt',p_completed_at+interval '24 hours');
end;
$function$


CREATE OR REPLACE FUNCTION foundation.list_user_concierge_jobs_v5(p_owner_shine_id uuid, p_limit integer DEFAULT 50, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
with source as (
  select foundation.list_user_concierge_jobs_v4(p_owner_shine_id,p_limit,p_before) as payload
),
enriched as (
  select
    case
      when x.request_id is null then item
      else item || jsonb_build_object(
        'status','retired',
        'waitingOn','none',
        'attentionRequired',false,
        'nextAction',null,
        'attentionOrder',95,
        'attentionReason','Expired unused',
        'canCancel',false,
        'retirementReceipt',
          case
            when encode(
              extensions.digest(convert_to(x.receipt::text,'UTF8'),'sha256'),'hex'
            )=x.receipt_sha256
            then x.receipt || jsonb_build_object(
              'receiptSha256',x.receipt_sha256,'integrity','verified'
            )
            else null
          end,
        'retirementReceiptIntegrity',
          case
            when encode(
              extensions.digest(convert_to(x.receipt::text,'UTF8'),'sha256'),'hex'
            )=x.receipt_sha256 then 'verified'
            else 'mismatch'
          end
      )
    end as item
  from source
  cross join lateral jsonb_array_elements(source.payload->'items') item
  left join foundation.concierge_retirement_events x
    on x.request_id=(item->>'requestId')::uuid
   and x.owner_shine_id=p_owner_shine_id
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
      where x->>'status'<>'retired'
        and x->>'waitingOn' in ('companion','specialist')
        and not coalesce((x->>'attentionRequired')::boolean,false)
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
    )
  ),
  'ordering',(select payload->'ordering' from source),
  'receiptContract',
    (select payload->'receiptContract' from source) ||
    jsonb_build_object(
      'retirementVersion','shine-foundation/concierge-retirement-receipt-v1',
      'retirementReadTimeVerification',true
    ),
  'items',assembled.items
)
from assembled;
$function$


select cron.unschedule(jobid)
from cron.job
where jobname='shine-foundation-concierge-retire-stale-15m';

select cron.schedule(
  'shine-foundation-concierge-retire-stale-15m',
  '*/15 * * * *',
  $$select foundation.retire_stale_concierge_requests_v1(
      clock_timestamp(),interval '1 hour',100
    );$$
);
