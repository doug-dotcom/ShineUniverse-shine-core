CREATE OR REPLACE FUNCTION foundation.retire_concierge_request_if_expired_v1(p_request_id uuid, p_owner_shine_id uuid, p_client_id text, p_as_of timestamp with time zone DEFAULT clock_timestamp(), p_min_age interval DEFAULT '01:00:00'::interval)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  q foundation.concierge_requests%rowtype;
  existing foundation.concierge_retirement_events%rowtype;
  v_receipt jsonb;
  v_hash text;
begin
  if p_request_id is null or p_owner_shine_id is null
     or p_client_id is null or p_as_of is null
     or p_min_age < interval '30 minutes'
     or p_min_age > interval '24 hours' then
    raise exception 'invalid-concierge-retirement-admission' using errcode='22023';
  end if;

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

  select * into existing
  from foundation.concierge_retirement_events r
  where r.request_id=p_request_id;

  if found then
    return jsonb_build_object(
      'status','already-retired',
      'reasonCode',existing.reason_code,
      'requestId',p_request_id,
      'retiredAt',existing.retired_at,
      'receipt',existing.receipt,
      'receiptSha256',existing.receipt_sha256
    );
  end if;

  if foundation.concierge_request_is_cancelled_v1(p_request_id) then
    return jsonb_build_object(
      'status','not-retired',
      'reasonCode','concierge-request-cancelled',
      'requestId',p_request_id
    );
  end if;

  if q.requested_at > p_as_of-p_min_age then
    return jsonb_build_object(
      'status','not-retired',
      'reasonCode','concierge-plan-within-ttl',
      'requestId',p_request_id,
      'expiresAt',q.requested_at+p_min_age
    );
  end if;

  if exists (
       select 1 from foundation.concierge_execution_events e
       where e.request_id=p_request_id
         and e.event_type in ('execution-started','execution-completed','execution-failed')
     )
     or exists (
       select 1 from foundation.concierge_step_checkpoints cp
       where cp.request_id=p_request_id
     )
     or exists (
       select 1 from foundation.concierge_retry_jobs j
       where j.request_id=p_request_id
     ) then
    return jsonb_build_object(
      'status','not-retired',
      'reasonCode','concierge-execution-already-started',
      'requestId',p_request_id
    );
  end if;

  v_receipt:=jsonb_build_object(
    'retirementReceipt','shine-foundation/concierge-retirement-receipt-v1',
    'schemaVersion','1.0.0',
    'requestId',q.request_id,
    'clientId',q.client_id,
    'reasonCode','unused-plan-expired',
    'requestedAt',q.requested_at,
    'retiredAt',p_as_of,
    'minimumAgeSeconds',extract(epoch from p_min_age)::integer,
    'requestedCapabilities',to_jsonb(q.requested_capabilities),
    'stepCount',q.step_count,
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
    gen_random_uuid(),q.request_id,q.owner_shine_id,q.client_id,
    'unused-plan-expired',p_as_of,v_receipt,v_hash
  );

  return jsonb_build_object(
    'status','retired',
    'reasonCode','unused-plan-expired',
    'requestId',q.request_id,
    'retiredAt',p_as_of,
    'receipt',v_receipt,
    'receiptSha256',v_hash
  );
end;
$function$;

CREATE OR REPLACE FUNCTION foundation.gate_concierge_execution_v1(p_event_id uuid, p_request_id uuid, p_owner_shine_id uuid, p_client_id text, p_occurred_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  r foundation.concierge_requests%rowtype;
  retirement jsonb;
  denied_count integer;
  nonlive_count integer;
  event_type text;
  reason text;
begin
  select * into r
  from foundation.concierge_requests q
  where q.request_id=p_request_id;

  if not found then
    raise exception 'concierge-request-not-found' using errcode='22023';
  end if;
  if r.owner_shine_id<>p_owner_shine_id then
    raise exception 'concierge-request-owner-mismatch' using errcode='22023';
  end if;
  if r.client_id<>p_client_id then
    raise exception 'concierge-request-client-mismatch' using errcode='22023';
  end if;

  if foundation.concierge_request_is_cancelled_v1(p_request_id) then
    event_type:='execution-blocked';
    reason:='concierge-request-cancelled';
  elsif foundation.concierge_request_is_retired_v1(p_request_id) then
    event_type:='execution-blocked';
    reason:='concierge-request-retired';
    retirement:=foundation.retire_concierge_request_if_expired_v1(
      p_request_id,p_owner_shine_id,p_client_id,p_occurred_at,interval '1 hour'
    );
  else
    retirement:=foundation.retire_concierge_request_if_expired_v1(
      p_request_id,p_owner_shine_id,p_client_id,p_occurred_at,interval '1 hour'
    );

    if retirement->>'status' in ('retired','already-retired') then
      event_type:='execution-blocked';
      reason:='concierge-plan-expired';
    else
      select
        count(*) filter (where authorization_decision='deny'),
        count(*) filter (where executable=false)
      into denied_count,nonlive_count
      from foundation.concierge_plan_steps
      where request_id=p_request_id;

      if denied_count>0 then
        event_type:='execution-blocked';
        reason:='concierge-plan-not-authorised';
      elsif nonlive_count>0 then
        event_type:='execution-blocked';
        reason:='capability-adapter-not-live';
      else
        event_type:='execution-ready';
        reason:='concierge-execution-ready';
      end if;
    end if;
  end if;

  insert into foundation.concierge_execution_events(
    event_id,request_id,owner_shine_id,client_id,event_type,reason_code,occurred_at
  ) values (
    p_event_id,p_request_id,p_owner_shine_id,p_client_id,event_type,reason,p_occurred_at
  );

  return jsonb_build_object(
    'requestId',p_request_id,
    'status',case when event_type='execution-ready' then 'ready' else 'blocked' end,
    'reasonCode',reason,
    'retirement',case
      when retirement is not null
       and retirement->>'status' in ('retired','already-retired')
      then retirement
      else null
    end,
    'plan',foundation.get_concierge_plan_v1(p_request_id)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION foundation.issue_capability_invocation_ticket_v2(p_ticket_id uuid, p_concierge_request_id uuid, p_step_id uuid, p_owner_shine_id uuid, p_client_id text, p_expires_at timestamp with time zone, p_occurred_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  r foundation.concierge_requests%rowtype;
  s foundation.concierge_plan_steps%rowtype;
  retirement jsonb;
begin
  select * into r
  from foundation.concierge_requests q
  where q.request_id=p_concierge_request_id;

  if not found then
    raise exception 'concierge-request-not-found' using errcode='22023';
  end if;
  if r.owner_shine_id<>p_owner_shine_id or r.client_id<>p_client_id then
    raise exception 'concierge-request-actor-mismatch' using errcode='22023';
  end if;

  if foundation.concierge_request_is_cancelled_v1(p_concierge_request_id) then
    raise exception 'concierge-request-cancelled' using errcode='22023';
  end if;

  retirement:=foundation.retire_concierge_request_if_expired_v1(
    p_concierge_request_id,p_owner_shine_id,p_client_id,p_occurred_at,interval '1 hour'
  );
  if retirement->>'status' in ('retired','already-retired') then
    raise exception 'concierge-request-retired' using errcode='22023';
  end if;

  select * into s
  from foundation.concierge_plan_steps x
  where x.step_id=p_step_id and x.request_id=p_concierge_request_id;
  if not found then
    raise exception 'concierge-step-not-found' using errcode='22023';
  end if;

  if s.authorization_decision<>'allow' or s.integration_grant_id is null
     or s.executable<>true or s.capability_mode not in ('read','advisory')
     or s.invocation_state<>'live' then
    raise exception 'concierge-step-not-executable' using errcode='22023';
  end if;

  if not exists (
    select 1 from foundation.effective_integration_client_grants g
    where g.grant_id=s.integration_grant_id
      and g.owner_shine_id=p_owner_shine_id
      and g.client_id=p_client_id
      and g.capability_id=s.capability_id
      and g.purpose=r.purpose
      and g.effective_status='active'
  ) then
    raise exception 'integration-grant-no-longer-active' using errcode='22023';
  end if;

  if p_ticket_id is null
     or p_expires_at<=p_occurred_at
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
    'ticketId',p_ticket_id,
    'stepId',p_step_id,
    'capabilityId',s.capability_id,
    'expiresAt',p_expires_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION foundation.record_concierge_step_checkpoint_v1(p_checkpoint_id uuid, p_request_id uuid, p_step_id uuid, p_capability_id text, p_result jsonb, p_completed_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'foundation'
AS $function$
declare
  q foundation.concierge_requests%rowtype;
  retirement jsonb;
begin
  if p_result is null or jsonb_typeof(p_result)<>'object' then
    raise exception 'invalid-step-checkpoint-result' using errcode='22023';
  end if;
  if pg_column_size(p_result)>65536 then
    raise exception 'step-checkpoint-result-too-large' using errcode='22023';
  end if;

  select * into q
  from foundation.concierge_requests x
  where x.request_id=p_request_id;

  if not found then
    raise exception 'concierge-request-not-found' using errcode='22023';
  end if;
  if foundation.concierge_request_is_cancelled_v1(p_request_id) then
    raise exception 'concierge-request-cancelled' using errcode='22023';
  end if;

  retirement:=foundation.retire_concierge_request_if_expired_v1(
    p_request_id,q.owner_shine_id,q.client_id,p_completed_at,interval '1 hour'
  );
  if retirement->>'status' in ('retired','already-retired') then
    raise exception 'concierge-request-retired' using errcode='22023';
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
