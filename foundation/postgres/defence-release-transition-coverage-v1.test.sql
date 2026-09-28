begin;

do $$
declare
  v jsonb;
begin
  select foundation.get_defence_release_transition_coverage_v1() into v;

  if (v->>'requiredTargets')::integer<>14 then
    raise exception 'expected 14 Railway release-transition targets: %',v;
  end if;

  if v->>'state' not in ('pass','warning') then
    raise exception 'coverage state must be pass or warning: %',v;
  end if;

  if jsonb_array_length(v->'targets')<>14 then
    raise exception 'coverage target detail must include all Railway targets: %',v;
  end if;
end;
$$;

do $$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_release_transition_coverage_v1()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_release_transition_coverage_v1()',
       'EXECUTE'
     ) then
    raise exception 'public roles must not execute release-transition coverage summary';
  end if;

  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_defence_release_transition_coverage_v1()',
       'EXECUTE'
     ) then
    raise exception 'foundation_runtime must read bounded release-transition coverage';
  end if;
end;
$$;

rollback;
