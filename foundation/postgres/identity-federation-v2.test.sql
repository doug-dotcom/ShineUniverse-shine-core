\set ON_ERROR_STOP on
begin;

set role service_role;

insert into foundation.identity_providers(
  provider_id,kind,project_url,issuer,publishable_key,
  verification_resource,subject_field,token_header
) values (
  'supabase:test-opaque',
  'supabase-opaque-vault',
  'https://opaque.example.test',
  null,
  'publishable-test-key',
  'private_records',
  'vault_hash',
  'x-shine-vault-token'
);

do $$
declare n integer;
begin
  select count(*) into n
  from foundation.identity_providers
  where provider_id='supabase:test-opaque'
    and kind='supabase-opaque-vault'
    and issuer is null
    and verification_resource='private_records'
    and subject_field='vault_hash'
    and token_header='x-shine-vault-token';
  if n<>1 then raise exception 'opaque provider was not stored correctly'; end if;
end
$$;

reset role;
rollback;

select 'SHINE FOUNDATION IDENTITY FEDERATION V2: PASS' as result;
