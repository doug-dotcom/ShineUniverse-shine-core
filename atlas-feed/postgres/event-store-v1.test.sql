begin;

insert into foundation.app_registry(app_id,manifest_version,manifest)
values (
  'shine.atlas-test','1.0.0',
  '{"appId":"shine.atlas-test","name":"Atlas Test","primaryPurpose":"test","supportedModes":["connected"],"requestedScopes":[]}'::jsonb
);

insert into foundation.app_credentials(
  credential_id,app_id,token_hash,label
) values (
  '33333333-3333-4333-8333-333333333333','shine.atlas-test',
  repeat('a',64),'atlas-test'
);

insert into foundation.app_capabilities(
  capability_id,app_id,capability_version,display_name,description,
  capability_mode,input_schema,output_schema,required_permissions,invocation_state,discoverable
) values (
  'atlas.test.publish','shine.atlas-test','1.0.0','Atlas test publish',
  'CI publisher fixture','advisory','{}'::jsonb,'{}'::jsonb,'[]'::jsonb,'live',false
);

do $$
declare
  e jsonb;
  a jsonb;
  r jsonb;
  out1 jsonb;
  out2 jsonb;
  out3 jsonb;
begin
  e := jsonb_build_object(
    'atlasFeedEvent','shine-universe/atlas-feed-event',
    'schemaVersion','1.0.0',
    'eventId','22222222-2222-4222-8222-222222222222',
    'topic','atlas.test.signal',
    'source',jsonb_build_object(
      'appId','shine.atlas-test',
      'capabilityId','atlas.test.publish',
      'releaseRef','git:test'
    ),
    'subject',jsonb_build_object('kind','fixture','key','fixture:1'),
    'timing',jsonb_build_object(
      'occurredAt','2026-09-28T09:59:00Z',
      'publishedAt','2026-09-28T09:59:10Z',
      'freshForSeconds',3600
    ),
    'audience',jsonb_build_object('mode','internal','dataClass','general'),
    'provenance',jsonb_build_object(
      'mode','first_party',
      'sourceObservedAt','2026-09-28T09:58:50Z',
      'evidenceRefs','[]'::jsonb
    ),
    'payloadContract',jsonb_build_object(
      'schemaRef','atlas.test.signal',
      'schemaVersion','1.0.0'
    ),
    'payload',jsonb_build_object('state','green')
  );

  a := jsonb_build_object(
    'eventId','22222222-2222-4222-8222-222222222222',
    'appId','shine.atlas-test',
    'credentialId','33333333-3333-4333-8333-333333333333',
    'capabilityId','atlas.test.publish',
    'capabilityVersion','1.0.0',
    'capabilityState','live',
    'audienceMode','internal',
    'dataClass','general',
    'ownerShineId',null,
    'grantId',null
  );

  r := jsonb_build_object(
    'atlasFeedPersistenceReceipt','shine-universe/atlas-feed-persistence-receipt-v1',
    'schemaVersion','1.0.0',
    'receiptId','44444444-4444-4444-8444-444444444444',
    'requestId','11111111-1111-4111-8111-111111111111',
    'eventId','22222222-2222-4222-8222-222222222222',
    'publisherAppId','shine.atlas-test',
    'capabilityId','atlas.test.publish',
    'capabilityVersion','1.0.0',
    'persistedAt','2026-09-28T10:00:00Z',
    'eventSha256',repeat('b',64),
    'payloadSha256',repeat('c',64)
  );

  select foundation.persist_atlas_feed_event_v1(
    '11111111-1111-4111-8111-111111111111',
    e,a,repeat('b',64),repeat('c',64),17,r,repeat('d',64),
    '2026-09-28T10:00:00Z'
  ) into out1;

  if out1->>'outcome'<>'persisted' then
    raise exception 'first Atlas persistence should insert: %',out1;
  end if;

  select foundation.persist_atlas_feed_event_v1(
    '11111111-1111-4111-8111-111111111111',
    e,a,repeat('b',64),repeat('c',64),17,r,repeat('d',64),
    '2026-09-28T10:00:00Z'
  ) into out2;

  if out2->>'outcome'<>'already-persisted'
     or out2#>>'{receipt,receiptId}'<>'44444444-4444-4444-8444-444444444444' then
    raise exception 'same request replay should return stable receipt: %',out2;
  end if;

  e := jsonb_set(e,'{payload,state}','"red"'::jsonb);
  r := r || jsonb_build_object(
    'requestId','55555555-5555-4555-8555-555555555555',
    'receiptId','66666666-6666-4666-8666-666666666666',
    'persistedAt','2026-09-28T10:00:01Z',
    'eventSha256',repeat('e',64),
    'payloadSha256',repeat('f',64)
  );
  select foundation.persist_atlas_feed_event_v1(
    '55555555-5555-4555-8555-555555555555',
    e,a,repeat('e',64),repeat('f',64),15,
    r,repeat('1',64),'2026-09-28T10:00:01Z'
  ) into out3;

  if out3->>'outcome'<>'conflict'
     or out3->>'reasonCode'<>'atlas-feed-event-id-conflict' then
    raise exception 'changed content under same event id must conflict: %',out3;
  end if;

  if (select count(*) from foundation.atlas_feed_events
      where event_id='22222222-2222-4222-8222-222222222222')<>1 then
    raise exception 'Atlas event idempotency failed';
  end if;

  if (select count(*) from foundation.atlas_feed_persistence_receipts
      where event_id='22222222-2222-4222-8222-222222222222')<>1 then
    raise exception 'Atlas receipt idempotency failed';
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  select foundation.get_gateway_operation_registry_health_v1('production') into v;
  if v->>'state'<>'pass' or (v->>'routeCount')::integer<>42 then
    raise exception 'Layer 3 should extend healthy Gateway registry to 42 routes: %',v;
  end if;

  select foundation.get_gateway_operation_policy_coverage_v1('production') into v;
  if v->>'state'<>'pass'
     or (v->>'privilegedOperationCount')::integer<>26
     or (v->>'coveredOperationCount')::integer<>26
     or (v->>'dependencyAdmissionPolicyCount')::integer<>23
     or (v->>'workerOnlyPolicyCount')::integer<>2 then
    raise exception 'Layer 3 policy coverage mismatch: %',v;
  end if;

  select foundation.evaluate_gateway_operation_policy_v1(
    'atlas-feed.publish','production',now()
  ) into v;
  if v->>'impactScope'<>'context-operations'
     or v->>'executionGuardRef'<>'foundation.persist_atlas_feed_event_v1'
     or v->>'policyState' not in ('admit','admit-degraded','deny','unavailable') then
    raise exception 'Atlas persistence policy is not fail-closed context admission: %',v;
  end if;
end;
$$;

do $$
begin
  begin
    update foundation.atlas_feed_events
    set topic='atlas.test.mutated'
    where event_id='22222222-2222-4222-8222-222222222222';
    raise exception 'Atlas event update unexpectedly succeeded';
  exception when sqlstate '55000' then null;
  end;

  begin
    delete from foundation.atlas_feed_persistence_receipts
    where event_id='22222222-2222-4222-8222-222222222222';
    raise exception 'Atlas receipt delete unexpectedly succeeded';
  exception when sqlstate '55000' then null;
  end;

  if has_table_privilege('anon','foundation.atlas_feed_events','SELECT')
     or has_table_privilege('authenticated','foundation.atlas_feed_events','SELECT')
     or has_table_privilege('anon','foundation.atlas_feed_persistence_receipts','SELECT')
     or has_table_privilege('authenticated','foundation.atlas_feed_persistence_receipts','SELECT') then
    raise exception 'client roles must not read Atlas event storage';
  end if;

  if has_table_privilege('foundation_gateway','foundation.atlas_feed_events','SELECT')
     or has_table_privilege('foundation_gateway','foundation.atlas_feed_events','INSERT')
     or has_table_privilege('foundation_gateway','foundation.atlas_feed_events','UPDATE')
     or has_table_privilege('foundation_gateway','foundation.atlas_feed_events','DELETE')
     or has_table_privilege('foundation_gateway','foundation.atlas_feed_persistence_receipts','SELECT')
     or has_table_privilege('foundation_gateway','foundation.atlas_feed_persistence_receipts','INSERT') then
    raise exception 'Foundation Gateway must not receive direct Atlas table privileges';
  end if;

  if not has_function_privilege(
    'foundation_gateway',
    'foundation.persist_atlas_feed_event_v1(uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'Foundation Gateway must execute only the narrow Atlas persistence function';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.persist_atlas_feed_event_v1(uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'foundation.persist_atlas_feed_event_v1(uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'client roles must not execute Atlas persistence';
  end if;
end;
$$;

rollback;
