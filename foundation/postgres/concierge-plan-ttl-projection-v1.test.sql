begin;
do $$
declare
  owner_id uuid;
  counting_request uuid:=gen_random_uuid();
  due_request uuid:=gen_random_uuid();
  started_request uuid:=gen_random_uuid();
  payload jsonb;
  item jsonb;
begin
  select shine_id into owner_id from foundation.shine_identities order by created_at limit 1;
  if owner_id is null then raise exception 'TTL projection fixture owner missing'; end if;

  insert into foundation.concierge_requests(request_id,owner_shine_id,client_id,purpose,requested_capabilities,step_count,requested_at)
  values
  (counting_request,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T07:31:00Z'),
  (due_request,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T06:30:00Z'),
  (started_request,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T06:00:00Z');

  insert into foundation.concierge_execution_events(event_id,request_id,owner_shine_id,client_id,event_type,reason_code,occurred_at)
  values(gen_random_uuid(),started_request,owner_id,'shine.companion','execution-started','concierge-execution-started','2026-09-28T06:20:00Z');

  payload:=foundation.list_user_concierge_jobs_v6(owner_id,100,null,'2026-09-28T08:01:00Z');

  select x into item from jsonb_array_elements(payload->'items') x where x->>'requestId'=counting_request::text;
  if item->'planTtl'->>'state'<>'counting-down'
     or (item->'planTtl'->>'secondsRemaining')::integer<>1800
     or item->'planTtl'->>'expiresAt'<>'2026-09-28T08:31:00+00:00' then
    raise exception 'counting-down TTL projection incorrect: %',item;
  end if;

  select x into item from jsonb_array_elements(payload->'items') x where x->>'requestId'=due_request::text;
  if item->'planTtl'->>'state'<>'expiry-due'
     or (item->'planTtl'->>'secondsRemaining')::integer<>0 then
    raise exception 'expiry-due TTL projection incorrect: %',item;
  end if;

  select x into item from jsonb_array_elements(payload->'items') x where x->>'requestId'=started_request::text;
  if item->'planTtl'->>'state'<>'started-exempt'
     or item->'planTtl'->>'secondsRemaining' is not null then
    raise exception 'started-exempt TTL projection incorrect: %',item;
  end if;

  if payload->'planTtlContract'->>'computedBy'<>'foundation-server'
     or (payload->'planTtlContract'->>'ttlSeconds')::integer<>3600
     or (payload->'planTtlContract'->>'clientClockAuthoritative')::boolean<>false then
    raise exception 'TTL projection contract incorrect: %',payload->'planTtlContract';
  end if;
end;
$$;
rollback;
