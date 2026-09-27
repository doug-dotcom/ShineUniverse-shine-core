\set ON_ERROR_STOP on
begin;
set role service_role;

insert into foundation.app_registry(app_id,manifest_version,manifest)
values ('shine.revoke-test','1.0.0',
'{"appId":"shine.revoke-test","name":"Revoke Test","foundation":{"standalonePrimaryPurposeAvailable":true,"requestedScopes":[{"scope":"vault.foundation.pilot.read","purpose":"revoke.foundation-pilot","resourceCategory":"foundation.pilot"}]}}'::jsonb);

insert into foundation.shine_identities(shine_id)
values ('11111111-1111-4111-8111-111111111111');

insert into foundation.vault_resources(
  resource_id,owner_shine_id,category,sensitivity,content_type,storage_ref
) values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'foundation.pilot','personal','application/json','foundation://revoke-test'
);

reset role;
set role foundation_gateway;

select * from foundation.issue_access_grant_v1(
  '33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '11111111-1111-4111-8111-111111111111',
  'shine.revoke-test','vault.foundation.pilot.read','revoke.foundation-pilot',
  null,'foundation.pilot',now()
);

do $$
declare got_outcome text; got_reason text; got_grant uuid; n integer; state text; outbox_n integer;
begin
  select outcome,reason_code,grant_id into got_outcome,got_reason,got_grant
  from foundation.revoke_access_grant_v1(
    '66666666-6666-4666-8666-666666666666',
    '44444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111',
    'shine.revoke-test',now()
  );

  if got_outcome<>'revoked' or got_reason<>'grant-revoked-by-user'
     or got_grant<>'44444444-4444-4444-8444-444444444444'::uuid then
    raise exception 'expected explicit revoke, got % / % / %',got_outcome,got_reason,got_grant;
  end if;

  select count(*) into n from foundation.grant_revocations
  where grant_id='44444444-4444-4444-8444-444444444444';
  if n<>1 then raise exception 'expected one revocation'; end if;

  select effective_status into state from foundation.effective_access_grants
  where grant_id='44444444-4444-4444-8444-444444444444';
  if state<>'revoked' then raise exception 'grant remained effective: %',state; end if;

  select count(*) into outbox_n from foundation.revocation_outbox
  where grant_id='44444444-4444-4444-8444-444444444444';
  if outbox_n<>1 then raise exception 'revocation outbox not populated'; end if;
end
$$;

do $$
declare got_outcome text; got_reason text; n integer;
begin
  select outcome,reason_code into got_outcome,got_reason
  from foundation.revoke_access_grant_v1(
    '77777777-7777-4777-8777-777777777777',
    '44444444-4444-4444-8444-444444444444',
    '11111111-1111-4111-8111-111111111111',
    'shine.revoke-test',now()
  );
  if got_outcome<>'already-revoked' or got_reason<>'grant-already-revoked' then
    raise exception 'repeated revoke was not idempotent';
  end if;
  select count(*) into n from foundation.grant_revocations
  where grant_id='44444444-4444-4444-8444-444444444444';
  if n<>1 then raise exception 'duplicate revocation created'; end if;
end
$$;

do $$
declare got_outcome text; got_reason text;
begin
  select outcome,reason_code into got_outcome,got_reason
  from foundation.revoke_access_grant_v1(
    '88888888-8888-4888-8888-888888888888',
    '44444444-4444-4444-8444-444444444444',
    '99999999-9999-4999-8999-999999999999',
    'shine.revoke-test',now()
  );
  if got_outcome<>'denied' or got_reason<>'grant-not-found' then
    raise exception 'wrong owner was not denied';
  end if;
end
$$;

rollback;
select 'SHINE FOUNDATION GRANT REVOKE V1: PASS' as result;
