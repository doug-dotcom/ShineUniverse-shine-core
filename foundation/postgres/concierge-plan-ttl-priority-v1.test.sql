begin;
do $$
declare
  owner_id uuid:=gen_random_uuid();
  permission_request uuid:=gen_random_uuid();
  due_request uuid:=gen_random_uuid();
  soon_request uuid:=gen_random_uuid();
  normal_request uuid:=gen_random_uuid();
  app_id text;
  payload jsonb;
  item jsonb;
begin
  insert into foundation.shine_identities(shine_id) values(owner_id);

  select c.app_id into app_id
  from foundation.app_capabilities c
  where c.capability_id='travel.plan_trip'
  limit 1;

  if app_id is null then
    raise exception 'TTL priority fixture app missing';
  end if;

  insert into foundation.concierge_requests(
    request_id,owner_shine_id,client_id,purpose,
    requested_capabilities,step_count,requested_at
  ) values
  (permission_request,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T07:06:00Z'),
  (due_request,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T06:59:00Z'),
  (soon_request,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T07:11:00Z'),
  (normal_request,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T07:21:00Z');

  insert into foundation.concierge_plan_steps(
    step_id,request_id,step_order,capability_id,app_id,
    authorization_decision,authorization_reason,invocation_state,
    executable,capability_mode
  ) values (
    gen_random_uuid(),permission_request,1,'travel.plan_trip',app_id,
    'deny','capability-consent-required','live',false,'advisory'
  );

  insert into foundation.concierge_execution_events(
    event_id,request_id,owner_shine_id,client_id,
    event_type,reason_code,occurred_at
  ) values (
    gen_random_uuid(),permission_request,owner_id,'shine.companion',
    'execution-blocked','concierge-plan-not-authorised','2026-09-28T07:07:00Z'
  );

  payload:=foundation.list_user_concierge_jobs_v7(
    owner_id,100,null,'2026-09-28T08:01:00Z'
  );

  select x into item from jsonb_array_elements(payload->'items') x
  where x->>'requestId'=permission_request::text;
  if item->>'nextAction'<>'review-consent'
     or (item->>'attentionOrder')::integer<>20
     or item->>'attentionReason'<>'Permission required'
     or item->'planUrgency'->>'state'<>'expiring-soon' then
    raise exception 'Permission precedence over TTL urgency failed: %',item;
  end if;

  select x into item from jsonb_array_elements(payload->'items') x
  where x->>'requestId'=due_request::text;
  if (item->>'attentionOrder')::integer<>25
     or item->>'nextAction'<>'send-fresh-request'
     or item->'planUrgency'->>'state'<>'expiry-due'
     or item->'planUrgency'->>'priority'<>'critical' then
    raise exception 'Expiry-due priority failed: %',item;
  end if;

  select x into item from jsonb_array_elements(payload->'items') x
  where x->>'requestId'=soon_request::text;
  if (item->>'attentionOrder')::integer<>45
     or item->>'nextAction'<>'review-before-expiry'
     or item->'planUrgency'->>'state'<>'expiring-soon'
     or (item->'planUrgency'->>'secondsRemaining')::integer<>600 then
    raise exception 'Expires-soon priority failed: %',item;
  end if;

  select x into item from jsonb_array_elements(payload->'items') x
  where x->>'requestId'=normal_request::text;
  if (item->>'attentionOrder')::integer<>60
     or item->'planUrgency'->>'state'<>'normal'
     or (item->'planUrgency'->>'requiresUserAttention')::boolean<>false then
    raise exception 'Ordinary task priority changed unexpectedly: %',item;
  end if;

  if (payload->'summary'->>'attentionRequired')::integer<>3
     or (payload->'summary'->>'automatic')::integer<>1
     or (payload->'summary'->>'expiringSoon')::integer<>2
     or (payload->'summary'->>'expiryDue')::integer<>1 then
    raise exception 'TTL urgency summary incorrect: %',payload->'summary';
  end if;

  if (payload->'ordering'->>'ttlUrgencyUsed')::boolean<>true
     or (payload->'ordering'->>'ttlUrgencyWarningSeconds')::integer<>900
     or (payload->'ordering'->>'aiPriorityScoreUsed')::boolean<>false then
    raise exception 'TTL urgency ordering contract incorrect: %',payload->'ordering';
  end if;

  if (payload->'planTtlContract'->>'warningSeconds')::integer<>900
     or (payload->'planTtlContract'->>'urgencyChangesExecution')::boolean<>false
     or (payload->'planTtlContract'->>'urgencyAutoStartsWork')::boolean<>false then
    raise exception 'TTL urgency execution boundary incorrect: %',payload->'planTtlContract';
  end if;
end;
$$;
rollback;
