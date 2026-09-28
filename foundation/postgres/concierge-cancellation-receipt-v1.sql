alter table foundation.concierge_cancellation_events
  add column if not exists superseded_by_request_id uuid
    references foundation.concierge_requests(request_id),
  add column if not exists receipt jsonb,
  add column if not exists receipt_sha256 text;

alter table foundation.concierge_cancellation_events
  drop constraint if exists concierge_cancellation_superseded_not_self,
  add constraint concierge_cancellation_superseded_not_self
    check (superseded_by_request_id is null or superseded_by_request_id<>request_id),
  drop constraint if exists concierge_cancellation_receipt_object,
  add constraint concierge_cancellation_receipt_object
    check (receipt is null or jsonb_typeof(receipt)='object'),
  drop constraint if exists concierge_cancellation_receipt_sha256,
  add constraint concierge_cancellation_receipt_sha256
    check (receipt_sha256 is null or receipt_sha256 ~ '^[a-f0-9]{64}$');

alter table foundation.concierge_cancellation_events
  alter column receipt set not null,
  alter column receipt_sha256 set not null;

create index if not exists concierge_cancellation_superseded_by_idx
  on foundation.concierge_cancellation_events(superseded_by_request_id)
  where superseded_by_request_id is not null;

create or replace function foundation.cancel_concierge_request_v2(
  p_event_id uuid,
  p_request_id uuid,
  p_owner_shine_id uuid,
  p_client_id text,
  p_reason_code text,
  p_cancelled_at timestamptz,
  p_superseded_by_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','foundation'
as $function$
declare
  q foundation.concierge_requests%rowtype;
  replacement foundation.concierge_requests%rowtype;
  existing foundation.concierge_cancellation_events%rowtype;
  effective_reason text:=coalesce(nullif(p_reason_code,''),'user-cancelled');
  v_total integer:=0;
  v_completed integer:=0;
  v_completed_capabilities text[]:=array[]::text[];
  v_pending_capabilities text[]:=array[]::text[];
  v_steps jsonb:='[]'::jsonb;
  v_receipt jsonb;
  v_receipt_sha256 text;
begin
  select * into q
  from foundation.concierge_requests x
  where x.request_id=p_request_id
  for update;

  if not found then
    raise exception 'concierge-request-not-found' using errcode='22023';
  end if;
  if q.owner_shine_id<>p_owner_shine_id then
    raise exception 'concierge-request-owner-mismatch' using errcode='22023';
  end if;
  if q.client_id<>p_client_id then
    raise exception 'concierge-request-client-mismatch' using errcode='22023';
  end if;
  if p_superseded_by_request_id=p_request_id then
    raise exception 'concierge-supersession-self-reference' using errcode='22023';
  end if;

  if p_superseded_by_request_id is not null then
    select * into replacement
    from foundation.concierge_requests x
    where x.request_id=p_superseded_by_request_id;

    if not found then
      raise exception 'concierge-replacement-request-not-found' using errcode='22023';
    end if;
    if replacement.owner_shine_id<>p_owner_shine_id
       or replacement.client_id<>p_client_id then
      raise exception 'concierge-replacement-actor-mismatch' using errcode='22023';
    end if;
  end if;

  select * into existing
  from foundation.concierge_cancellation_events c
  where c.request_id=p_request_id;

  if found then
    if existing.reason_code<>effective_reason
       or existing.superseded_by_request_id is distinct from p_superseded_by_request_id then
      raise exception 'concierge-cancellation-replay-conflict' using errcode='22023';
    end if;
    return jsonb_build_object(
      'status','already-cancelled',
      'requestId',p_request_id,
      'cancelledAt',existing.cancelled_at,
      'reasonCode',existing.reason_code,
      'supersededByRequestId',existing.superseded_by_request_id,
      'receipt',existing.receipt,
      'receiptSha256',existing.receipt_sha256
    );
  end if;

  with step_state as (
    select
      s.step_order,
      s.step_id,
      s.capability_id,
      s.app_id,
      (cp.step_id is not null and cp.completed_at<=p_cancelled_at) as completed_before_cancel,
      case
        when cp.step_id is not null and cp.completed_at<=p_cancelled_at
        then cp.completed_at
        else null
      end as completed_at
    from foundation.concierge_plan_steps s
    left join foundation.concierge_step_checkpoints cp
      on cp.request_id=s.request_id
     and cp.step_id=s.step_id
    where s.request_id=p_request_id
  )
  select
    count(*)::integer,
    count(*) filter (where completed_before_cancel)::integer,
    coalesce(
      array_agg(capability_id order by step_order)
        filter (where completed_before_cancel),
      array[]::text[]
    ),
    coalesce(
      array_agg(capability_id order by step_order)
        filter (where not completed_before_cancel),
      array[]::text[]
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'stepId',step_id,
          'capabilityId',capability_id,
          'appId',app_id,
          'completedBeforeCancellation',completed_before_cancel,
          'completedAt',completed_at
        )
        order by step_order
      ),
      '[]'::jsonb
    )
  into
    v_total,
    v_completed,
    v_completed_capabilities,
    v_pending_capabilities,
    v_steps
  from step_state;

  v_receipt:=jsonb_build_object(
    'cancellationReceipt','shine-foundation/concierge-cancellation-receipt-v1',
    'schemaVersion','1.0.0',
    'requestId',p_request_id,
    'clientId',p_client_id,
    'reasonCode',effective_reason,
    'cancelledAt',p_cancelled_at,
    'supersededByRequestId',p_superseded_by_request_id,
    'progress',jsonb_build_object(
      'totalSteps',v_total,
      'completedBeforeCancellation',v_completed,
      'pendingAtCancellation',greatest(v_total-v_completed,0)
    ),
    'completedCapabilities',to_jsonb(v_completed_capabilities),
    'pendingCapabilities',to_jsonb(v_pending_capabilities),
    'steps',v_steps
  );

  v_receipt_sha256:=encode(
    extensions.digest(convert_to(v_receipt::text,'UTF8'),'sha256'),
    'hex'
  );

  insert into foundation.concierge_cancellation_events(
    event_id,request_id,owner_shine_id,client_id,reason_code,cancelled_at,
    superseded_by_request_id,receipt,receipt_sha256
  ) values (
    p_event_id,p_request_id,p_owner_shine_id,p_client_id,effective_reason,p_cancelled_at,
    p_superseded_by_request_id,v_receipt,v_receipt_sha256
  );

  update foundation.concierge_retry_jobs
  set status='abandoned',completed_at=p_cancelled_at
  where request_id=p_request_id and status in ('pending','claimed');

  insert into foundation.concierge_retry_job_events(
    event_id,retry_job_id,event_type,reason_code,occurred_at
  )
  select gen_random_uuid(),j.retry_job_id,'abandoned',effective_reason,p_cancelled_at
  from foundation.concierge_retry_jobs j
  where j.request_id=p_request_id and j.completed_at=p_cancelled_at
  on conflict do nothing;

  return jsonb_build_object(
    'status','cancelled',
    'requestId',p_request_id,
    'cancelledAt',p_cancelled_at,
    'reasonCode',effective_reason,
    'supersededByRequestId',p_superseded_by_request_id,
    'receipt',v_receipt,
    'receiptSha256',v_receipt_sha256
  );
end;
$function$;

create or replace function foundation.cancel_concierge_request_v1(
  p_event_id uuid,
  p_request_id uuid,
  p_owner_shine_id uuid,
  p_client_id text,
  p_reason_code text,
  p_cancelled_at timestamptz
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','foundation'
as $function$
  select foundation.cancel_concierge_request_v2(
    p_event_id,p_request_id,p_owner_shine_id,p_client_id,
    p_reason_code,p_cancelled_at,null
  );
$function$;

create or replace function foundation.record_concierge_step_checkpoint_v1(
  p_checkpoint_id uuid,
  p_request_id uuid,
  p_step_id uuid,
  p_capability_id text,
  p_result jsonb,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','foundation'
as $function$
declare
  q foundation.concierge_requests%rowtype;
begin
  if p_result is null or jsonb_typeof(p_result)<>'object' then
    raise exception 'invalid-step-checkpoint-result' using errcode='22023';
  end if;
  if pg_column_size(p_result)>65536 then
    raise exception 'step-checkpoint-result-too-large' using errcode='22023';
  end if;

  select * into q
  from foundation.concierge_requests x
  where x.request_id=p_request_id
  for share;

  if not found then
    raise exception 'concierge-request-not-found' using errcode='22023';
  end if;
  if foundation.concierge_request_is_cancelled_v1(p_request_id) then
    raise exception 'concierge-request-cancelled' using errcode='22023';
  end if;

  if not exists (
    select 1 from foundation.concierge_plan_steps s
    where s.request_id=p_request_id
      and s.step_id=p_step_id
      and s.capability_id=p_capability_id
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

  return jsonb_build_object(
    'recorded',true,
    'expiresAt',p_completed_at+interval '24 hours'
  );
end;
$function$;

create or replace function foundation.list_user_concierge_jobs_v4(
  p_owner_shine_id uuid,
  p_limit integer default 50,
  p_before timestamptz default null
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog','foundation'
as $function$
with source as (
  select foundation.list_user_concierge_jobs_v3(
    p_owner_shine_id,p_limit,p_before
  ) as payload
),
enriched as (
  select
    item ||
    jsonb_build_object(
      'cancellationReceipt',
      case
        when c.request_id is null then null
        when encode(
          extensions.digest(convert_to(c.receipt::text,'UTF8'),'sha256'),
          'hex'
        )=c.receipt_sha256
        then c.receipt || jsonb_build_object(
          'receiptSha256',c.receipt_sha256,
          'integrity','verified'
        )
        else null
      end,
      'cancellationReceiptIntegrity',
      case
        when c.request_id is null then null
        when encode(
          extensions.digest(convert_to(c.receipt::text,'UTF8'),'sha256'),
          'hex'
        )=c.receipt_sha256 then 'verified'
        else 'mismatch'
      end,
      'supersededByRequestId',c.superseded_by_request_id
    ) as item
  from source
  cross join lateral jsonb_array_elements(source.payload->'items') item
  left join foundation.concierge_cancellation_events c
    on c.request_id=(item->>'requestId')::uuid
   and c.owner_shine_id=p_owner_shine_id
),
assembled as (
  select coalesce(
    jsonb_agg(
      item
      order by
        coalesce((item->>'attentionOrder')::integer,999) asc,
        (item->>'requestedAt')::timestamptz asc,
        item->>'requestId' asc
    ),
    '[]'::jsonb
  ) as items
  from enriched
)
select jsonb_build_object(
  'privacy',(select payload->'privacy' from source),
  'summary',
    (select payload->'summary' from source) ||
    jsonb_build_object(
      'superseded',
      (select count(*) from jsonb_array_elements(assembled.items) x
       where x->>'status'='cancelled'
         and x->>'supersededByRequestId' is not null)
    ),
  'ordering',(select payload->'ordering' from source),
  'receiptContract',jsonb_build_object(
    'version','shine-foundation/concierge-cancellation-receipt-v1',
    'specialistOutputIncluded',false,
    'conversationTextIncluded',false,
    'tamperEvidentSha256',true,
    'readTimeVerification',true
  ),
  'items',assembled.items
)
from assembled;
$function$;
