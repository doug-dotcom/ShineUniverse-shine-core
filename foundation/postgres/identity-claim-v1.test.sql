\set ON_ERROR_STOP on
begin;

set role service_role;

insert into foundation.identity_providers(
  provider_id,kind,project_url,issuer,publishable_key,
  verification_resource,subject_field,token_header
) values
(
  'supabase:claim-source',
  'supabase-opaque-vault',
  'https://source.example.test',
  null,
  'public-source',
  'sessions',
  'session_hash',
  'x-source-token'
),
(
  'supabase:claim-target',
  'supabase-auth',
  'https://target.example.test',
  'https://target.example.test/auth/v1',
  'public-target',
  null,null,null
);

insert into foundation.app_registry(app_id,manifest_version,manifest)
values (
  'shine.claim-test',
  '1.0.0',
  '{"appId":"shine.claim-test","name":"Claim Test","foundation":{"standalonePrimaryPurposeAvailable":true,"requestedScopes":[]}}'::jsonb
);

insert into foundation.app_identity_providers(app_id,provider_id)
values ('shine.claim-test','supabase:claim-source');

insert into foundation.app_claim_identity_providers(app_id,provider_id)
values ('shine.claim-test','supabase:claim-target');

insert into foundation.shine_identities(shine_id)
values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into foundation.identity_bindings(
  provider,provider_subject,shine_id,verified_at
) values (
  'supabase:claim-target',
  'target-user',
  '11111111-1111-4111-8111-111111111111',
  now()
);

reset role;
set role foundation_gateway;

do $$
declare
  got_outcome text;
  got_reason text;
  linked uuid;
  grants integer;
begin
  select outcome,reason_code into got_outcome,got_reason
  from foundation.complete_identity_claim_v1(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'shine.claim-test',
    'supabase:claim-source',
    'source-session-hash',
    'supabase:claim-target',
    'target-user',
    '11111111-1111-4111-8111-111111111111',
    now()
  );

  if got_outcome<>'linked' or got_reason<>'identity-claim-linked' then
    raise exception 'expected linked, got % / %',got_outcome,got_reason;
  end if;

  select shine_id into linked
  from foundation.identity_bindings
  where provider='supabase:claim-source'
    and provider_subject='source-session-hash';

  if linked<>'11111111-1111-4111-8111-111111111111'::uuid then
    raise exception 'source session did not bind to target Shine ID';
  end if;

  select count(*) into grants
  from foundation.access_grants
  where app_id='shine.claim-test';

  if grants<>0 then
    raise exception 'identity claim must not create Vault grants';
  end if;
end
$$;

do $$
declare got_outcome text; got_reason text; n integer;
begin
  select outcome,reason_code into got_outcome,got_reason
  from foundation.complete_identity_claim_v1(
    'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    'shine.claim-test',
    'supabase:claim-source',
    'source-session-hash',
    'supabase:claim-target',
    'target-user',
    '11111111-1111-4111-8111-111111111111',
    now()
  );

  if got_outcome<>'already-linked' then
    raise exception 'expected already-linked, got %',got_outcome;
  end if;

  select count(*) into n
  from foundation.identity_bindings
  where provider='supabase:claim-source'
    and provider_subject='source-session-hash';

  if n<>1 then raise exception 'claim duplicated source binding'; end if;
end
$$;

set role service_role;
insert into foundation.identity_bindings(
  provider,provider_subject,shine_id,verified_at
) values (
  'supabase:claim-source',
  'other-source',
  '22222222-2222-4222-8222-222222222222',
  now()
);
reset role;
set role foundation_gateway;

do $$
declare got_outcome text; got_reason text;
begin
  select outcome,reason_code into got_outcome,got_reason
  from foundation.complete_identity_claim_v1(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'ffffffff-ffff-4fff-8fff-ffffffffffff',
    'shine.claim-test',
    'supabase:claim-source',
    'other-source',
    'supabase:claim-target',
    'target-user',
    '11111111-1111-4111-8111-111111111111',
    now()
  );

  if got_outcome<>'denied' or got_reason<>'source-already-bound' then
    raise exception 'expected source-already-bound denial, got % / %',got_outcome,got_reason;
  end if;
end
$$;

reset role;

do $$
begin
  begin
    update foundation.identity_claim_events
      set reason_code='tampered'
      where request_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    raise exception 'claim event unexpectedly mutable';
  exception
    when object_not_in_prerequisite_state then null;
  end;
end
$$;

-- Exact target provider subject must match the canonical binding proved by Auth.
set role foundation_gateway;
do $
declare got_outcome text; got_reason text;
begin
  select outcome,reason_code into got_outcome,got_reason
  from foundation.complete_identity_claim_v1(
    '12121212-1212-4212-8212-121212121212',
    '13131313-1313-4313-8313-131313131313',
    'shine.claim-test',
    'supabase:claim-source',
    'new-source-session',
    'supabase:claim-target',
    'wrong-target-user',
    '11111111-1111-4111-8111-111111111111',
    now()
  );

  if got_outcome<>'denied' or got_reason<>'target-identity-unverified' then
    raise exception 'expected exact target subject denial, got % / %',got_outcome,got_reason;
  end if;
end
$;

-- Reusing a request ID with a different canonical subject must fail as a replay conflict.
do $
begin
  begin
    perform *
    from foundation.complete_identity_claim_v1(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'shine.claim-test',
      'supabase:claim-source',
      'source-session-hash',
      'supabase:claim-target',
      'different-target-user',
      '11111111-1111-4111-8111-111111111111',
      now()
    );
    raise exception 'identity claim replay unexpectedly accepted a changed target subject';
  exception
    when unique_violation then null;
  end;
end
$;

reset role;
rollback;
select 'SHINE FOUNDATION IDENTITY CLAIM V1: PASS' as result;
