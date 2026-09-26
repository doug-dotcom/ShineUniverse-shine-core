\set ON_ERROR_STOP on
begin;
set role service_role;

insert into foundation.app_registry(app_id,manifest_version,manifest)
values ('shine.consent-test','1.0.0',
'{"appId":"shine.consent-test","name":"Consent Test","foundation":{"standalonePrimaryPurposeAvailable":true,"requestedScopes":[{"scope":"vault.foundation.pilot.read","purpose":"consent.foundation-pilot","resourceCategory":"foundation.pilot"}]}}'::jsonb);

insert into foundation.shine_identities(shine_id)
values ('11111111-1111-4111-8111-111111111111');

insert into foundation.vault_resources(
  resource_id,owner_shine_id,category,sensitivity,content_type,storage_ref
) values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'foundation.pilot','personal','application/json','foundation://consent-test'
);

reset role;
set role foundation_gateway;

do $$
declare got_outcome text; got_reason text; got_grant uuid; n integer; method text;
begin
  select outcome,reason_code,grant_id into got_outcome,got_reason,got_grant
  from foundation.issue_access_grant_v1(
    '33333333-3333-4333-8333-333333333333',
    '44444444-4444-4444-8444-444444444444',
    '55555555-5555-4555-8555-555555555555',
    '11111111-1111-4111-8111-111111111111',
    'shine.consent-test','vault.foundation.pilot.read','consent.foundation-pilot',
    null,'foundation.pilot',now()
  );
  if got_outcome<>'granted' or got_reason<>'grant-consent-recorded'
     or got_grant<>'44444444-4444-4444-8444-444444444444'::uuid then
    raise exception 'expected granted result, got % / % / %',got_outcome,got_reason,got_grant;
  end if;
  select count(*),max(consent_method) into n,method
  from foundation.access_grants where grant_id=got_grant;
  if n<>1 or method<>'explicit-user' then raise exception 'grant was not explicit-user consent'; end if;
end
$$;

do $$
declare got_outcome text; got_reason text; got_grant uuid; n integer;
begin
  select outcome,reason_code,grant_id into got_outcome,got_reason,got_grant
  from foundation.issue_access_grant_v1(
    '66666666-6666-4666-8666-666666666666',
    '77777777-7777-4777-8777-777777777777',
    '88888888-8888-4888-8888-888888888888',
    '11111111-1111-4111-8111-111111111111',
    'shine.consent-test','vault.foundation.pilot.read','consent.foundation-pilot',
    null,'foundation.pilot',now()
  );
  if got_outcome<>'already-granted' or got_reason<>'grant-already-active'
     or got_grant<>'44444444-4444-4444-8444-444444444444'::uuid then
    raise exception 'expected already-granted';
  end if;
  select count(*) into n from foundation.access_grants where app_id='shine.consent-test';
  if n<>1 then raise exception 'duplicate active grant was created'; end if;
end
$$;

do $$
declare got_outcome text; got_reason text; got_grant uuid;
begin
  select outcome,reason_code,grant_id into got_outcome,got_reason,got_grant
  from foundation.issue_access_grant_v1(
    '99999999-9999-4999-8999-999999999999',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '11111111-1111-4111-8111-111111111111',
    'shine.consent-test','vault.not-declared.read','consent.foundation-pilot',
    null,'foundation.pilot',now()
  );
  if got_outcome<>'denied' or got_reason<>'scope-not-declared' or got_grant is not null then
    raise exception 'undeclared scope was not denied';
  end if;
end
$$;

do $$
declare got_outcome text; got_reason text; got_grant uuid;
begin
  select outcome,reason_code,grant_id into got_outcome,got_reason,got_grant
  from foundation.issue_access_grant_v1(
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    '55555555-5555-4555-8555-555555555555',
    '11111111-1111-4111-8111-111111111111',
    'shine.consent-test','vault.foundation.pilot.read','consent.foundation-pilot',
    null,'foundation.pilot',now()
  );
  if got_outcome<>'granted' or got_grant<>'44444444-4444-4444-8444-444444444444'::uuid then
    raise exception 'idempotent replay did not return original result';
  end if;
end
$$;

reset role;
do $$
begin
  begin
    update foundation.grant_consent_events set reason_code='tampered'
    where request_id='55555555-5555-4555-8555-555555555555';
    raise exception 'grant consent evidence unexpectedly mutable';
  exception when object_not_in_prerequisite_state then null;
  end;
end
$$;

rollback;
select 'SHINE FOUNDATION GRANT CONSENT V1: PASS' as result;
