\set ON_ERROR_STOP on
begin;

set role service_role;
insert into foundation.trusted_auth_issuers(
  issuer_id, issuer_url, api_url, publishable_key
) values (
  'supabase:test-shine',
  'https://test-shine.supabase.co/auth/v1',
  'https://test-shine.supabase.co',
  'sb_publishable_test'
);
reset role;

set role foundation_gateway;
do $$
declare n integer;
begin
  select count(*) into n
  from foundation.trusted_auth_issuers
  where issuer_id='supabase:test-shine' and status='active';
  if n<>1 then raise exception 'runtime could not read active trusted issuer'; end if;
end
$$;
reset role;

rollback;
select 'SHINE FOUNDATION AUTH BRIDGE: PASS' as result;
