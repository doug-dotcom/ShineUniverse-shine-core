begin;

do $$
declare
  v jsonb;
begin
  select foundation.get_defence_oidc_principal_binding_summary_v1() into v;

  if v->>'state'<>'pass'
     or (v->>'requiredTargets')::integer<>14
     or (v->>'boundTargets')::integer<>14
     or (v->>'duplicateRepositoryIds')::integer<>0
     or (v->>'wrongOwnerTargets')::integer<>0
     or (v->>'repositoryIdMismatches')::integer<>0 then
    raise exception 'OIDC principal binding summary not fully bound: %',v;
  end if;

  if exists (
    select 1
    from foundation.defence_estate_targets t
    join (
      values
        ('railway:daash','1373763946'),
        ('railway:dive','1361439227'),
        ('railway:dnd','1384280308'),
        ('railway:fiona','1357712835'),
        ('railway:fish','1384278684'),
        ('railway:my-money','1378329747'),
        ('railway:project-l','1240491225'),
        ('railway:punt49','1359524189'),
        ('railway:recovery-companion','1354993812'),
        ('railway:rivers','1377780406'),
        ('railway:shine-ai','1386493862'),
        ('railway:ski','1359646182'),
        ('railway:translate','1368992845'),
        ('railway:travel','1361434212')
    ) expected(target_id,repository_id) using(target_id)
    where t.metadata->>'sourceRepositoryId' is distinct from expected.repository_id
       or t.metadata->>'sourceRepositoryOwner' is distinct from 'doug-dotcom'
       or t.metadata->>'sourceRepositoryOwnerId' is distinct from '225530237'
  ) then
    raise exception 'immutable repository principal mismatch';
  end if;
end;
$$;

do $$
declare
  v jsonb;
begin
  update foundation.defence_estate_targets
     set metadata=jsonb_set(metadata,'{sourceRepositoryId}','"9999999999"'::jsonb)
   where target_id='railway:project-l';

  select foundation.get_defence_oidc_principal_binding_summary_v1() into v;
  if v->>'state'<>'fail' then
    raise exception 'principal binding summary failed to detect repository id corruption: %',v;
  end if;
end;
$$;

do $$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_oidc_principal_binding_summary_v1()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_oidc_principal_binding_summary_v1()',
       'EXECUTE'
     ) then
    raise exception 'public roles unexpectedly inspect OIDC principal bindings';
  end if;

  if not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_oidc_principal_binding_summary_v1()',
       'EXECUTE'
     ) then
    raise exception 'Defence runtime cannot inspect OIDC principal bindings';
  end if;
end;
$$;

rollback;
