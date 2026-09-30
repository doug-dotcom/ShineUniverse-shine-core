-- Hosted-only explicit client deny policies.
-- These tables are intentionally internal. RLS with no policies already denies
-- client access; this migration makes that deny posture explicit and future-proof.
-- Policies are RESTRICTIVE so any future permissive policy still cannot open these
-- tables to anon/authenticated unless this deny is deliberately removed.

do $explicit_client_deny$
declare
  v_target text;
  v_rel regclass;
  v_policy_count integer;
begin
  foreach v_target in array array[
    'foundation.project_l_policy_transition_authorization_events',
    'foundation.project_l_roster_head_witness_events',
    'foundation.project_l_roster_head_witness_state',
    'foundation.project_l_trace_witness_events',
    'foundation.project_l_trace_witness_state',
    'universe.app_registry',
    'universe.app_repo_links',
    'universe.daily_build_closes',
    'universe.data_dataset_aliases',
    'universe.data_dataset_relationships',
    'universe.data_datasets',
    'universe.data_sources',
    'universe.dataset_capability_map',
    'universe.foundation_app_links',
    'universe.layer_events',
    'universe.layer_ledger_anchors',
    'universe.readiness_events',
    'universe.readiness_releases',
    'universe.readiness_stage_definitions',
    'universe.repo_registry'
  ]
  loop
    v_rel:=to_regclass(v_target);
    if v_rel is null then
      raise exception 'explicit-client-deny-target-missing:%',v_target;
    end if;

    if not exists(
      select 1 from pg_class c
      where c.oid=v_rel and c.relrowsecurity
    ) then
      raise exception 'explicit-client-deny-rls-disabled:%',v_target;
    end if;

    if has_table_privilege('anon',v_rel,'SELECT')
       or has_table_privilege('anon',v_rel,'INSERT')
       or has_table_privilege('anon',v_rel,'UPDATE')
       or has_table_privilege('anon',v_rel,'DELETE')
       or has_table_privilege('authenticated',v_rel,'SELECT')
       or has_table_privilege('authenticated',v_rel,'INSERT')
       or has_table_privilege('authenticated',v_rel,'UPDATE')
       or has_table_privilege('authenticated',v_rel,'DELETE') then
      raise exception 'explicit-client-deny-unexpected-client-grant:%',v_target;
    end if;

    select count(*) into v_policy_count
    from pg_policy p
    where p.polrelid=v_rel
      and p.polname='client_access_explicit_deny';

    if v_policy_count=0 then
      execute format(
        'create policy client_access_explicit_deny on %s as restrictive for all to anon, authenticated using (false) with check (false)',
        v_rel
      );
    elsif v_policy_count<>1 then
      raise exception 'explicit-client-deny-policy-count-invalid:%:%',v_target,v_policy_count;
    end if;

    if not exists(
      select 1
      from pg_policy p
      where p.polrelid=v_rel
        and p.polname='client_access_explicit_deny'
        and p.polpermissive=false
        and p.polcmd='*'
        and pg_get_expr(p.polqual,p.polrelid)='false'
        and pg_get_expr(p.polwithcheck,p.polrelid)='false'
        and cardinality(p.polroles)=2
        and p.polroles @> array[
          (select oid from pg_roles where rolname='anon'),
          (select oid from pg_roles where rolname='authenticated')
        ]::oid[]
    ) then
      raise exception 'explicit-client-deny-policy-shape-invalid:%',v_target;
    end if;
  end loop;
end;
$explicit_client_deny$;
