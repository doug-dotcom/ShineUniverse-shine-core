CREATE OR REPLACE FUNCTION foundation.cancel_concierge_request_v2(p_event_id uuid, p_request_id uuid, p_owner_shine_id uuid, p_client_id text, p_reason_code text, p_cancelled_at timestamp with time zone, p_superseded_by_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  q foundation.concierge_requests%rowtype;
  replacement foundation.concierge_requests%rowtype;
  existing foundation.concierge_cancellation_events%rowtype;
  retired foundation.concierge_retirement_events%rowtype;
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
  if foundation.concierge_request_is_retired_v1(p_request_id) then
    select * into retired
    from foundation.concierge_retirement_events r
    where r.request_id=p_request_id;

    return jsonb_build_object(
      'status','retired',
      'requestId',p_request_id,
      'reasonCode',retired.reason_code,
      'retiredAt',retired.retired_at,
      'receipt',retired.receipt,
      'receiptSha256',retired.receipt_sha256
    );
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
$function$

