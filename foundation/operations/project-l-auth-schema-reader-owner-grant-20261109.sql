-- Project L: raxfwycrnviwxxzykhfq.
-- Requires an owner-authorised session with Auth-schema USAGE GRANT OPTION.
-- The current connector's postgres role does not have that authority.
-- This file has NOT been executed.
begin;
do $preflight$ begin
 if not exists(select 1 from pg_roles where rolname='vc_foundation_l_identity_reader') then
  raise exception 'expected-reader-role-missing';
 end if;
 if not has_schema_privilege(current_user,'auth','usage with grant option') then
  raise exception 'auth-schema-owner-authority-required';
 end if;
end $preflight$;
grant usage on schema auth to vc_foundation_l_identity_reader;
do $verify$ begin
 if not has_schema_privilege('vc_foundation_l_identity_reader','auth','usage') then
  raise exception 'reader-schema-usage-not-effective';
 end if;
end $verify$;
commit;
-- Follow with sentinel-scoped reader verification in a rolled-back transaction.
-- No login, membership, token, personal record or RLS bypass is created.
