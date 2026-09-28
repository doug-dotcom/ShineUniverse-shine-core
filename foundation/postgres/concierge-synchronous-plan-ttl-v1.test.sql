begin;

do $$
declare
  owner_id uuid;
  app_id text;
  expired_request uuid:=gen_random_uuid();
  started_request uuid:=gen_random_uuid();
  expired_step uuid:=gen_random_uuid();
  started_step uuid:=gen_random_uuid();
  expired_gate jsonb;
  started_gate jsonb;
begin
  select shine_id into owner_id
  from foundation.shine_identities
  order by created_at
  limit 1;

  select c.app_id into app_id
  from foundation.app_capabilities c
  where c.capability_id='travel.plan_trip'
  limit 1;

  if owner_id is null or app_id is null then
    raise exception 'TTL regression fixture dependencies unavailable';
  end if;

  insert into foundation.concierge_requests(
    request_id,owner_shine_id,client_id,purpose,
    requested_capabilities,step_count,requested_at
  ) values
  (
    expired_request,owner_id,'shine.companion','concierge.cross-project-read',
    array['travel.plan_trip']::text[],1,clock_timestamp()-interval '2 hours'
  ),
  (
    started_request,owner_id,'shine.companion','concierge.cross-project-read',
    array['travel.plan_trip']::text[],1,clock_timestamp()-interval '2 hours'
  );

  insert into foundation.concierge_plan_steps(
    step_id,request_id,step_order,capability_id,app_id,
    authorization_decision,authorization_reason,invocation_state,
    executable,capability_mode
  ) values
  (
    expired_step,expired_request,1,'travel.plan_trip',app_id,
    'allow','fixture','live',true,'advisory'
  ),
  (
    started_step,started_request,1,'travel.plan_trip',app_id,
    'allow','fixture','live',true,'advisory'
  );

  insert into foundation.concierge_execution_events(
    event_id,request_id,owner_shine_id,client_id,
    event_type,reason_code,occurred_at
  ) values
  (
    gen_random_uuid(),expired_request,owner_id,'shine.companion',
    'execution-ready','concierge-execution-ready',
    clock_timestamp()-interval '90 minutes'
  ),
  (
    gen_random_uuid(),started_request,owner_id,'shine.companion',
    'execution-started','concierge-execution-started',
    clock_timestamp()-interval '90 minutes'
  );

  expired_gate:=foundation.gate_concierge_execution_v1(
    gen_random_uuid(),expired_request,owner_id,'shine.companion',clock_timestamp()
  );

  if expired_gate->>'status'<>'blocked'
     or expired_gate->>'reasonCode'<>'concierge-plan-expired'
     or expired_gate->'retirement'->>'status' not in ('retired','already-retired')
     or expired_gate->'retirement'->'receipt'->>'executionStarted'<>'false'
     or not foundation.concierge_request_is_retired_v1(expired_request) then
    raise exception 'gate-ready-only request did not expire synchronously: %',expired_gate;
  end if;

  started_gate:=foundation.gate_concierge_execution_v1(
    gen_random_uuid(),started_request,owner_id,'shine.companion',clock_timestamp()
  );

  if started_gate->>'status'<>'ready'
     or started_gate->>'reasonCode'<>'concierge-execution-ready'
     or foundation.concierge_request_is_retired_v1(started_request) then
    raise exception 'execution-started request did not remain resumable: %',started_gate;
  end if;
end;
$$;

rollback;
