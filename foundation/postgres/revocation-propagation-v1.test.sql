\set ON_ERROR_STOP on
begin;
set role service_role;

insert into foundation.app_registry(app_id,manifest_version,manifest)
values
('shine.rev-a','1.0.0','{"appId":"shine.rev-a","name":"Rev A","foundation":{"requestedScopes":[{"scope":"vault.test.read","purpose":"test","resourceCategory":"test"}]}}'::jsonb),
('shine.rev-b','1.0.0','{"appId":"shine.rev-b","name":"Rev B","foundation":{"requestedScopes":[{"scope":"vault.test.read","purpose":"test","resourceCategory":"test"}]}}'::jsonb);

insert into foundation.shine_identities(shine_id)
values ('11111111-1111-4111-8111-111111111111');

insert into foundation.vault_resources(resource_id,owner_shine_id,category,sensitivity)
values
('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','test','personal'),
('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','test','personal');

insert into foundation.access_grants(
  grant_id,owner_shine_id,app_id,scope,purpose,resource_id,status,issued_at,
  consent_method,consent_recorded_at
) values
('44444444-4444-4444-8444-444444444444','11111111-1111-4111-8111-111111111111','shine.rev-a','vault.test.read','test','22222222-2222-4222-8222-222222222222','active',now(),'explicit-user',now()),
('55555555-5555-4555-8555-555555555555','11111111-1111-4111-8111-111111111111','shine.rev-b','vault.test.read','test','33333333-3333-4333-8333-333333333333','active',now(),'explicit-user',now());

reset role;
set role foundation_gateway;

select * from foundation.revoke_access_grant_v1(
  '66666666-6666-4666-8666-666666666666',
  '77777777-7777-4777-8777-777777777777',
  '88888888-8888-4888-8888-888888888888',
  '44444444-4444-4444-8444-444444444444',
  '11111111-1111-4111-8111-111111111111',
  'shine.rev-a',now()
);

select * from foundation.revoke_access_grant_v1(
  '99999999-9999-4999-8999-999999999999',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '55555555-5555-4555-8555-555555555555',
  '11111111-1111-4111-8111-111111111111',
  'shine.rev-b',now()
);

do $$
declare seq_a bigint; seq_b bigint; n integer; pending bigint; health_state text; recommended text;
begin
  select sequence_no into seq_a
  from foundation.list_app_revocations_v1('shine.rev-a',0,101)
  order by sequence_no limit 1;
  select sequence_no into seq_b
  from foundation.list_app_revocations_v1('shine.rev-b',0,101)
  order by sequence_no limit 1;

  if seq_a is null or seq_b is null or seq_a=seq_b then
    raise exception 'expected distinct app-scoped revocation sequences';
  end if;

  select count(*) into n
  from foundation.list_app_revocations_v1('shine.rev-a',0,101);
  if n<>1 then raise exception 'app feed leaked another app event'; end if;

  select pending_count into pending
  from foundation.get_app_revocation_status_v1('shine.rev-a');
  if pending<>1 then raise exception 'expected one pending revocation'; end if;

  select freshness_state,recommended_action into health_state,recommended
  from foundation.get_app_revocation_health_v1('shine.rev-a');
  if health_state<>'pending' or recommended<>'consume-revocations' then
    raise exception 'unexpected pre-ack health % / %',health_state,recommended;
  end if;

  perform *
  from foundation.record_app_revocation_delivery_v1(
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'shine.rev-a',0,array[seq_a],now()
  );

  perform *
  from foundation.ack_app_revocations_v2(
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'shine.rev-a',seq_a,now()
  );

  select pending_count into pending
  from foundation.get_app_revocation_status_v1('shine.rev-a');
  if pending<>0 then raise exception 'checkpoint did not clear pending event'; end if;

  select freshness_state,recommended_action into health_state,recommended
  from foundation.get_app_revocation_health_v1('shine.rev-a');
  if health_state<>'current' or recommended<>'none' then
    raise exception 'unexpected post-ack health % / %',health_state,recommended;
  end if;

  begin
    perform *
    from foundation.record_app_revocation_delivery_v1(
      'ffffffff-ffff-4fff-8fff-ffffffffffff',
      'shine.rev-a',0,array[seq_b],now()
    );
    raise exception 'cross-app delivery sequence unexpectedly accepted';
  exception when sqlstate '22023' then null;
  end;
end
$$;

reset role;
set role service_role;
do $$
declare deliveries integer; acks integer;
begin
  select count(*) into deliveries from foundation.app_revocation_deliveries
  where app_id='shine.rev-a';
  if deliveries<>1 then raise exception 'expected one delivery receipt'; end if;

  select count(*) into acks from foundation.app_revocation_ack_events
  where app_id='shine.rev-a' and outcome='advanced';
  if acks<>1 then raise exception 'expected one advanced ack'; end if;
end
$$;

rollback;
select 'SHINE FOUNDATION REVOCATION PROPAGATION V1: PASS' as result;
