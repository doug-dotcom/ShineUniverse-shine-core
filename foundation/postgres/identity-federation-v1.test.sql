\set ON_ERROR_STOP on
begin;

set role service_role;
insert into foundation.identity_providers(
  provider_id,kind,project_url,issuer,publishable_key
) values (
  'supabase:test',
  'supabase-auth',
  'https://identity.example.test',
  'https://identity.example.test/auth/v1',
  'publishable-test-key'
);
reset role;

set role foundation_gateway;

do $$
declare n integer;
begin
  select count(*) into n
  from foundation.identity_providers
  where provider_id='supabase:test' and status='active';
  if n <> 1 then raise exception 'runtime cannot read registered identity provider'; end if;
end
$$;

insert into foundation.access_audit_events(
  event_id,request_id,app_id,shine_id,scope,purpose,decision,reason_code,occurred_at
) values (
  'abababab-abab-4bab-8bab-abababababab',
  'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd',
  'shine.unknown',
  null,
  'vault.pilot.read',
  'pilot',
  'deny',
  'app-caller-unverified',
  '2026-09-26T08:30:00Z'
);

reset role;
rollback;

select 'SHINE FOUNDATION IDENTITY FEDERATION: PASS' as result;
