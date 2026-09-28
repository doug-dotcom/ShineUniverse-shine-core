-- Atlas Feed Layer 3: append-only event persistence and stable receipts.
-- This is a private Foundation-schema store. No consumer read surface or
-- Realtime publication is created here.

create table foundation.atlas_feed_events (
  event_id uuid primary key,
  first_request_id uuid not null unique,
  source_app_id text not null references foundation.app_registry(app_id),
  source_capability_id text not null references foundation.app_capabilities(capability_id),
  publisher_capability_version text not null,
  publisher_credential_id uuid not null references foundation.app_credentials(credential_id),
  source_release_ref text not null,
  topic text not null check (topic ~ '^[a-z0-9]+([._-][a-z0-9]+){1,7}$'),
  subject_kind text not null,
  subject_key text not null,
  occurred_at timestamptz not null,
  published_at timestamptz not null,
  fresh_for_seconds integer not null check (fresh_for_seconds between 0 and 604800),
  expires_at timestamptz,
  audience_mode text not null check (audience_mode in ('owner','grant','internal')),
  data_class text not null check (data_class in ('general','personal','sensitive')),
  owner_shine_id uuid references foundation.shine_identities(shine_id),
  grant_id uuid references foundation.access_grants(grant_id),
  provenance_mode text not null check (provenance_mode in ('first_party','external','derived','mixed')),
  source_observed_at timestamptz not null,
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs)='array'),
  payload_schema_ref text not null,
  payload_schema_version text not null,
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  payload_size_bytes integer not null check (payload_size_bytes between 2 and 65536),
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  event_sha256 text not null check (event_sha256 ~ '^[a-f0-9]{64}$'),
  admission_snapshot jsonb not null check (jsonb_typeof(admission_snapshot)='object'),
  persisted_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (published_at >= occurred_at),
  check (expires_at is null or expires_at > published_at),
  check ((audience_mode='grant') = (grant_id is not null)),
  check (data_class='general' or audience_mode<>'internal'),
  check (data_class='general' or owner_shine_id is not null),
  check (grant_id is null or owner_shine_id is not null)
);

create unique index atlas_feed_events_event_hash_idx
  on foundation.atlas_feed_events(event_id,event_sha256);
create index atlas_feed_events_topic_time_idx
  on foundation.atlas_feed_events(topic,published_at desc,event_id);
create index atlas_feed_events_source_time_idx
  on foundation.atlas_feed_events(source_app_id,published_at desc,event_id);
create index atlas_feed_events_owner_time_idx
  on foundation.atlas_feed_events(owner_shine_id,published_at desc,event_id)
  where owner_shine_id is not null;
create index atlas_feed_events_grant_idx
  on foundation.atlas_feed_events(grant_id)
  where grant_id is not null;

create table foundation.atlas_feed_persistence_receipts (
  receipt_id uuid primary key,
  request_id uuid not null unique,
  event_id uuid not null unique references foundation.atlas_feed_events(event_id),
  event_sha256 text not null check (event_sha256 ~ '^[a-f0-9]{64}$'),
  payload_sha256 text not null check (payload_sha256 ~ '^[a-f0-9]{64}$'),
  publisher_app_id text not null references foundation.app_registry(app_id),
  publisher_capability_id text not null references foundation.app_capabilities(capability_id),
  persisted_at timestamptz not null,
  receipt jsonb not null check (jsonb_typeof(receipt)='object'),
  receipt_sha256 text not null check (receipt_sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now()
);

create index atlas_feed_receipts_app_time_idx
  on foundation.atlas_feed_persistence_receipts(publisher_app_id,persisted_at desc);

alter table foundation.atlas_feed_events enable row level security;
alter table foundation.atlas_feed_persistence_receipts enable row level security;

revoke all on foundation.atlas_feed_events from public,anon,authenticated;
revoke all on foundation.atlas_feed_persistence_receipts from public,anon,authenticated;

grant select,insert on foundation.atlas_feed_events to foundation_gateway,service_role;
grant select,insert on foundation.atlas_feed_persistence_receipts to foundation_gateway,service_role;

create policy foundation_gateway_atlas_feed_events_select
on foundation.atlas_feed_events
for select
to foundation_gateway
using (true);

create policy foundation_gateway_atlas_feed_events_insert
on foundation.atlas_feed_events
for insert
to foundation_gateway
with check (true);

create policy foundation_gateway_atlas_feed_receipts_select
on foundation.atlas_feed_persistence_receipts
for select
to foundation_gateway
using (true);

create policy foundation_gateway_atlas_feed_receipts_insert
on foundation.atlas_feed_persistence_receipts
for insert
to foundation_gateway
with check (true);

create trigger atlas_feed_events_append_only
before update or delete on foundation.atlas_feed_events
for each row execute function foundation.reject_append_only_mutation();

create trigger atlas_feed_persistence_receipts_append_only
before update or delete on foundation.atlas_feed_persistence_receipts
for each row execute function foundation.reject_append_only_mutation();

create or replace function foundation.persist_atlas_feed_event_v1(
  p_request_id uuid,
  p_event jsonb,
  p_admission jsonb,
  p_event_sha256 text,
  p_payload_sha256 text,
  p_payload_size_bytes integer,
  p_receipt jsonb,
  p_receipt_sha256 text,
  p_persisted_at timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation
as $function$
declare
  v_event_id uuid;
  v_receipt_id uuid;
  v_existing_event foundation.atlas_feed_events%rowtype;
  v_existing_receipt foundation.atlas_feed_persistence_receipts%rowtype;
  v_owner_shine_id uuid;
  v_grant_id uuid;
  v_inserted uuid;
begin
  if p_request_id is null
     or jsonb_typeof(p_event)<>'object'
     or jsonb_typeof(p_admission)<>'object'
     or jsonb_typeof(p_receipt)<>'object'
     or p_event_sha256 !~ '^[a-f0-9]{64}$'
     or p_payload_sha256 !~ '^[a-f0-9]{64}$'
     or p_payload_size_bytes is null
     or p_payload_size_bytes<2
     or p_payload_size_bytes>65536
     or p_receipt_sha256 !~ '^[a-f0-9]{64}$'
     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'capabilityVersion','') is null
     or p_admission->>'audienceMode'<>p_event#>>'{audience,mode}'
     or p_admission->>'dataClass'<>p_event#>>'{audience,dataClass}'
     or coalesce(p_admission->>'grantId','')<>coalesce(p_event#>>'{audience,grantId}','')
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'capabilityVersion'<>p_admission->>'capabilityVersion'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_capability_version,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    p_admission->>'capabilityVersion',(p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    p_payload_size_bytes,
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_payload_size_bytes is null or p_payload_size_bytes<2 or p_payload_size_bytes>65536
     or p_receipt_sha256 !~ '^[a-f0-9]{64}     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_payload_sha256 !~ '^[a-f0-9]{64}    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'capabilityVersion','') is null
     or p_admission->>'audienceMode'<>p_event#>>'{audience,mode}'
     or p_admission->>'dataClass'<>p_event#>>'{audience,dataClass}'
     or coalesce(p_admission->>'grantId','')<>coalesce(p_event#>>'{audience,grantId}','')
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'capabilityVersion'<>p_admission->>'capabilityVersion'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_capability_version,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    p_admission->>'capabilityVersion',(p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    p_payload_size_bytes,
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_payload_size_bytes is null or p_payload_size_bytes<2 or p_payload_size_bytes>65536
     or p_receipt_sha256 !~ '^[a-f0-9]{64}     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_payload_size_bytes is null
     or p_payload_size_bytes<2
     or p_payload_size_bytes>65536
     or p_receipt_sha256 !~ '^[a-f0-9]{64}    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'capabilityVersion','') is null
     or p_admission->>'audienceMode'<>p_event#>>'{audience,mode}'
     or p_admission->>'dataClass'<>p_event#>>'{audience,dataClass}'
     or coalesce(p_admission->>'grantId','')<>coalesce(p_event#>>'{audience,grantId}','')
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'capabilityVersion'<>p_admission->>'capabilityVersion'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_capability_version,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    p_admission->>'capabilityVersion',(p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    p_payload_size_bytes,
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_payload_size_bytes is null or p_payload_size_bytes<2 or p_payload_size_bytes>65536
     or p_receipt_sha256 !~ '^[a-f0-9]{64}     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'capabilityVersion','') is null
     or p_admission->>'audienceMode'<>p_event#>>'{audience,mode}'
     or p_admission->>'dataClass'<>p_event#>>'{audience,dataClass}'
     or coalesce(p_admission->>'grantId','')<>coalesce(p_event#>>'{audience,grantId}','')
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'capabilityVersion'<>p_admission->>'capabilityVersion'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_capability_version,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    p_admission->>'capabilityVersion',(p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    p_payload_size_bytes,
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,integer,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_payload_size_bytes is null or p_payload_size_bytes<2 or p_payload_size_bytes>65536
     or p_receipt_sha256 !~ '^[a-f0-9]{64}     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;

     or p_persisted_at is null then
    raise exception 'invalid-atlas-feed-persistence-request' using errcode='22023';
  end if;

  v_event_id := (p_event->>'eventId')::uuid;
  v_receipt_id := (p_receipt->>'receiptId')::uuid;
  v_owner_shine_id := nullif(p_admission->>'ownerShineId','')::uuid;
  v_grant_id := nullif(p_admission->>'grantId','')::uuid;

  if p_event->>'atlasFeedEvent'<>'shine-universe/atlas-feed-event'
     or p_event->>'schemaVersion'<>'1.0.0'
     or p_admission->>'eventId'<>p_event->>'eventId'
     or p_admission->>'appId'<>p_event#>>'{source,appId}'
     or p_admission->>'capabilityId'<>p_event#>>'{source,capabilityId}'
     or p_admission->>'capabilityState'<>'live'
     or nullif(p_admission->>'credentialId','') is null
     or (p_admission->>'credentialId')::uuid is null
     or p_receipt->>'atlasFeedPersistenceReceipt'<>'shine-universe/atlas-feed-persistence-receipt-v1'
     or p_receipt->>'schemaVersion'<>'1.0.0'
     or (p_receipt->>'requestId')::uuid<>p_request_id
     or (p_receipt->>'eventId')::uuid<>v_event_id
     or p_receipt->>'publisherAppId'<>p_admission->>'appId'
     or p_receipt->>'capabilityId'<>p_admission->>'capabilityId'
     or p_receipt->>'eventSha256'<>p_event_sha256
     or p_receipt->>'payloadSha256'<>p_payload_sha256
     or (p_receipt->>'persistedAt')::timestamptz<>p_persisted_at then
    raise exception 'atlas-feed-persistence-boundary-mismatch' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-request:'||p_request_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended('atlas-feed-event:'||v_event_id::text,0));

  select * into v_existing_receipt
  from foundation.atlas_feed_persistence_receipts r
  where r.request_id=p_request_id;

  if found then
    if v_existing_receipt.event_id<>v_event_id
       or v_existing_receipt.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-request-replay-conflict'
      );
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  select * into v_existing_event
  from foundation.atlas_feed_events e
  where e.event_id=v_event_id;

  if found then
    if v_existing_event.event_sha256<>p_event_sha256 then
      return jsonb_build_object(
        'outcome','conflict',
        'reasonCode','atlas-feed-event-id-conflict'
      );
    end if;
    select * into v_existing_receipt
    from foundation.atlas_feed_persistence_receipts r
    where r.event_id=v_event_id;
    if not found then
      raise exception 'atlas-feed-event-receipt-missing' using errcode='55000';
    end if;
    return jsonb_build_object(
      'outcome','already-persisted',
      'reasonCode','atlas-feed-event-already-persisted',
      'receipt',v_existing_receipt.receipt,
      'receiptSha256',v_existing_receipt.receipt_sha256
    );
  end if;

  insert into foundation.atlas_feed_events(
    event_id,first_request_id,source_app_id,source_capability_id,publisher_credential_id,
    source_release_ref,topic,subject_kind,subject_key,
    occurred_at,published_at,fresh_for_seconds,expires_at,
    audience_mode,data_class,owner_shine_id,grant_id,
    provenance_mode,source_observed_at,evidence_refs,
    payload_schema_ref,payload_schema_version,payload,payload_size_bytes,
    payload_sha256,event_sha256,admission_snapshot,persisted_at
  ) values (
    v_event_id,p_request_id,p_event#>>'{source,appId}',p_event#>>'{source,capabilityId}',
    (p_admission->>'credentialId')::uuid,
    p_event#>>'{source,releaseRef}',p_event->>'topic',
    p_event#>>'{subject,kind}',p_event#>>'{subject,key}',
    (p_event#>>'{timing,occurredAt}')::timestamptz,
    (p_event#>>'{timing,publishedAt}')::timestamptz,
    (p_event#>>'{timing,freshForSeconds}')::integer,
    nullif(p_event#>>'{timing,expiresAt}','')::timestamptz,
    p_event#>>'{audience,mode}',p_event#>>'{audience,dataClass}',
    v_owner_shine_id,v_grant_id,
    p_event#>>'{provenance,mode}',
    (p_event#>>'{provenance,sourceObservedAt}')::timestamptz,
    coalesce(p_event#>'{provenance,evidenceRefs}','[]'::jsonb),
    p_event#>>'{payloadContract,schemaRef}',p_event#>>'{payloadContract,schemaVersion}',
    p_event->'payload',
    octet_length(convert_to((p_event->'payload')::text,'UTF8')),
    p_payload_sha256,p_event_sha256,p_admission,p_persisted_at
  )
  returning event_id into v_inserted;

  insert into foundation.atlas_feed_persistence_receipts(
    receipt_id,request_id,event_id,event_sha256,payload_sha256,
    publisher_app_id,publisher_capability_id,persisted_at,receipt,receipt_sha256
  ) values (
    v_receipt_id,p_request_id,v_event_id,p_event_sha256,p_payload_sha256,
    p_admission->>'appId',p_admission->>'capabilityId',p_persisted_at,p_receipt,p_receipt_sha256
  );

  return jsonb_build_object(
    'outcome','persisted',
    'reasonCode','atlas-feed-event-persisted',
    'receipt',p_receipt,
    'receiptSha256',p_receipt_sha256
  );
end;
$function$;

revoke all on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) from public,anon,authenticated;

grant execute on function foundation.persist_atlas_feed_event_v1(
  uuid,jsonb,jsonb,text,text,jsonb,text,timestamptz
) to foundation_gateway,service_role;

-- Register the final write route behind the same Defence-backed context scope
-- as Layer 2. Layer-2 admission remains the mandatory in-process execution guard.
insert into foundation.gateway_operation_contracts(
  service_id,environment,contract_version,route_symbol,http_method,path_template,
  operation_key,risk_class,effect_class,auth_class,control_mode,control_ref,
  source_ref,effective_at
)
values (
  'foundation.gateway','production','1.0.0','atlasFeedPublishPath','POST',
  '/v1/atlas-feed/publish','atlas-feed.publish',
  'context-write','write','app-or-user+app','service-guard',
  'foundation.persist_atlas_feed_event_v1',
  'github:atlas-feed/contracts/event-store-v1.json',now()
)
on conflict (service_id,environment,route_symbol,contract_version) do nothing;

insert into foundation.service_admission_bindings(
  service_id,environment,operation,binding_version,impact_scope,
  enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'context-operations',true,now(),
  'atlas-feed:admission-binding:persistence:v1',
  'Atlas Feed persistence is Defence-guarded and still requires Layer-2 publisher admission before storage.'
)
on conflict do nothing;

insert into foundation.gateway_operation_policies(
  service_id,environment,operation_key,policy_version,policy_mode,impact_scope,
  failure_behavior,execution_guard_ref,enabled,effective_at,evidence_ref,evidence_note
)
values (
  'foundation.gateway','production','atlas-feed.publish','1.0.0',
  'dependency-admission','context-operations','fail-closed',
  'foundation.persist_atlas_feed_event_v1',true,now(),
  'atlas-feed:operation-policy:persistence:v1',
  'Front-door Defence admission precedes Layer-2 publisher admission and the append-only event-store write.'
)
on conflict do nothing;
