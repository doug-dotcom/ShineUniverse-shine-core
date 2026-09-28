create or replace function foundation.cancel_concierge_request_v1(
  p_event_id uuid,
  p_request_id uuid,
  p_owner_shine_id uuid,
  p_client_id text,
  p_reason_code text,
  p_cancelled_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','foundation'
as $function$
declare
  q foundation.concierge_requests%rowtype;
  existing foundation.concierge_cancellation_events%rowtype;
  effective_reason text:=coalesce(nullif(p_reason_code,''),'user-cancelled');
begin
  select * into q
  from foundation.concierge_requests x
  where x.request_id=p_request_id;
  if not found then
    raise exception 'concierge-request-not-found' using errcode='22023';
  end if;
  if q.owner_shine_id<>p_owner_shine_id then
    raise exception 'concierge-request-owner-mismatch' using errcode='22023';
  end if;
  if q.client_id<>p_client_id then
    raise exception 'concierge-request-client-mismatch' using errcode='22023';
  end if;

  select * into existing
  from foundation.concierge_cancellation_events c
  where c.request_id=p_request_id;
  if found then
    return jsonb_build_object(
      'status','already-cancelled',
      'requestId',p_request_id,
      'cancelledAt',existing.cancelled_at,
      'reasonCode',existing.reason_code
    );
  end if;

  insert into foundation.concierge_cancellation_events(
    event_id,request_id,owner_shine_id,client_id,reason_code,cancelled_at
  ) values (
    p_event_id,p_request_id,p_owner_shine_id,p_client_id,
    effective_reason,p_cancelled_at
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
    'reasonCode',effective_reason
  );
end;
$function$;
