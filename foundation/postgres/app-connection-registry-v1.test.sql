\set ON_ERROR_STOP on
begin;

set role service_role;

insert into foundation.identity_providers(
  provider_id,kind,project_url,issuer,publishable_key
) values (
  'supabase:connection-test',
  'supabase-auth',
  'https://connection-test.example',
  'https://connection-test.example/auth/v1',
  'publishable-test-key'
);

insert into foundation.app_registry(app_id,manifest_version,manifest)
values (
  'shine.connection-test',
  '1.0.0',
  '{"appId":"shine.connection-test","name":"Connection Test","foundation":{"standalonePrimaryPurposeAvailable":true,"requestedScopes":[{"scope":"vault.test.read","purpose":"connection.test","resourceCategory":"connection.test"}]}}'::jsonb
);

do $$
declare state text;
begin
  select connection_state into state
  from foundation.app_connection_status
  where app_id='shine.connection-test';
  if state<>'registered' then raise exception 'expected registered, got %',state; end if;
end
$$;

insert into foundation.app_credentials(
  credential_id,app_id,token_hash,label
) values (
  '10101010-aaaa-4010-8010-101010101010',
  'shine.connection-test',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'connection-test'
);

do $$
declare state text;
begin
  select connection_state into state
  from foundation.app_connection_status
  where app_id='shine.connection-test';
  if state<>'credentialed' then raise exception 'expected credentialed, got %',state; end if;
end
$$;

insert into foundation.app_identity_providers(app_id,provider_id)
values ('shine.connection-test','supabase:connection-test');

do $$
declare state text;
begin
  select connection_state into state
  from foundation.app_connection_status
  where app_id='shine.connection-test';
  if state<>'identity-ready' then raise exception 'expected identity-ready, got %',state; end if;
end
$$;

insert into foundation.shine_identities(shine_id)
values ('20202020-aaaa-4020-8020-202020202020');

insert into foundation.vault_resources(
  resource_id,owner_shine_id,category,sensitivity,provenance
) values (
  '30303030-aaaa-4030-8030-303030303030',
  '20202020-aaaa-4020-8020-202020202020',
  'connection.test',
  'personal',
  '{"source":"system"}'::jsonb
);

insert into foundation.access_grants(
  grant_id,owner_shine_id,app_id,scope,purpose,resource_id,
  consent_method,consent_recorded_at
) values (
  '40404040-aaaa-4040-8040-404040404040',
  '20202020-aaaa-4020-8020-202020202020',
  'shine.connection-test',
  'vault.test.read',
  'connection.test',
  '30303030-aaaa-4030-8030-303030303030',
  'system-migration',
  now()
);

do $$
declare state text;
begin
  select connection_state into state
  from foundation.app_connection_status
  where app_id='shine.connection-test';
  if state<>'grant-ready' then raise exception 'expected grant-ready, got %',state; end if;
end
$$;

insert into foundation.access_audit_events(
  event_id,request_id,app_id,shine_id,scope,purpose,
  resource_id,decision,reason_code,grant_id,occurred_at
) values (
  '50505050-aaaa-4050-8050-505050505050',
  '60606060-aaaa-4060-8060-606060606060',
  'shine.connection-test',
  '20202020-aaaa-4020-8020-202020202020',
  'vault.test.read',
  'connection.test',
  '30303030-aaaa-4030-8030-303030303030',
  'allow',
  'grant-match',
  '40404040-aaaa-4040-8040-404040404040',
  now()
);

do $$
declare state text; allows integer;
begin
  select connection_state,observed_allows into state,allows
  from foundation.app_connection_status
  where app_id='shine.connection-test';
  if state<>'live-observed' then raise exception 'expected live-observed, got %',state; end if;
  if allows<>1 then raise exception 'expected one observed allow, got %',allows; end if;
end
$$;

reset role;
set role foundation_gateway;

do $$
declare n integer;
begin
  select count(*) into n
  from foundation.app_identity_providers
  where app_id='shine.connection-test'
    and provider_id='supabase:connection-test';
  if n<>1 then raise exception 'runtime cannot read app/provider link'; end if;
end
$$;

reset role;
rollback;

select 'SHINE FOUNDATION CONNECTION REGISTRY: PASS' as result;
