begin;
do $$
declare owner_id uuid; normal_id uuid:=gen_random_uuid(); soon_id uuid:=gen_random_uuid(); due_id uuid:=gen_random_uuid(); started_id uuid:=gen_random_uuid(); payload jsonb; item jsonb;
begin
 select shine_id into owner_id from foundation.shine_identities order by created_at limit 1;
 insert into foundation.concierge_requests(request_id,owner_shine_id,client_id,purpose,requested_capabilities,step_count,requested_at) values
 (normal_id,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T07:11:01Z'),
 (soon_id,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T07:11:00Z'),
 (due_id,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T06:00:00Z'),
 (started_id,owner_id,'shine.companion','concierge.cross-project-read',array['travel.plan_trip'],1,'2026-09-28T06:00:00Z');
 insert into foundation.concierge_execution_events(event_id,request_id,owner_shine_id,client_id,event_type,reason_code,occurred_at)
 values(gen_random_uuid(),started_id,owner_id,'shine.companion','execution-started','concierge-execution-started','2026-09-28T06:30:00Z');
 payload:=foundation.list_user_concierge_jobs_v7(owner_id,100,null,'2026-09-28T08:01:00Z');
 select x into item from jsonb_array_elements(payload->'items')x where x->>'requestId'=normal_id::text;
 if item->'deadlinePosture'->>'state'<>'normal' or (item->'planTtl'->>'secondsRemaining')::int<>601 then raise exception '601-second posture wrong: %',item; end if;
 select x into item from jsonb_array_elements(payload->'items')x where x->>'requestId'=soon_id::text;
 if item->'deadlinePosture'->>'state'<>'start-soon' or (item->'planTtl'->>'secondsRemaining')::int<>600 then raise exception '600-second posture wrong: %',item; end if;
 select x into item from jsonb_array_elements(payload->'items')x where x->>'requestId'=due_id::text;
 if item->'deadlinePosture'->>'state'<>'expiry-due' then raise exception 'expiry posture wrong: %',item; end if;
 select x into item from jsonb_array_elements(payload->'items')x where x->>'requestId'=started_id::text;
 if item->'deadlinePosture'->>'state'<>'started-exempt' then raise exception 'started posture wrong: %',item; end if;
 if payload->'deadlinePostureContract'->>'source'<>'foundation-server'
 or (payload->'deadlinePostureContract'->>'automaticExecutionTriggered')::boolean<>false
 or (payload->'deadlinePostureContract'->>'automaticRetryTriggered')::boolean<>false
 or (payload->'deadlinePostureContract'->>'readMutatesState')::boolean<>false then raise exception 'deadline posture contract unsafe'; end if;
end; $$;
rollback;