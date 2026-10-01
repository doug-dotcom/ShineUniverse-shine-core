-- Explicit client-deny RLS hardening for live grant/R&D evidence tables.
-- These tables are internal service-role stores. This layer makes the existing
-- default-deny posture explicit and future-proof against accidental permissive
-- client policies.

do $grant_rnd_client_deny$
declare
  v record;
  v_rls boolean;
begin
  for v in
    select *
    from (
      values
        ('public','grant_protocol','grant_protocol_client_deny'),
        ('public','grant_build_evidence','grant_build_evidence_client_deny')
    ) as x(schema_name,table_name,policy_name)
  loop
    if to_regclass(format('%I.%I',v.schema_name,v.table_name)) is null then
      continue;
    end if;

    select c.relrowsecurity
      into v_rls
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname=v.schema_name
      and c.relname=v.table_name
      and c.relkind='r';

    if coalesce(v_rls,false) is not true then
      raise exception 'grant-rnd-client-deny-rls-disabled:%.%',
        v.schema_name,v.table_name;
    end if;

    execute format(
      'revoke all on table %I.%I from anon, authenticated',
      v.schema_name,v.table_name
    );

    execute format(
      'drop policy if exists %I on %I.%I',
      v.policy_name,v.schema_name,v.table_name
    );

    execute format(
      'create policy %I on %I.%I as restrictive for all to anon, authenticated using (false) with check (false)',
      v.policy_name,v.schema_name,v.table_name
    );
  end loop;
end;
$grant_rnd_client_deny$;
