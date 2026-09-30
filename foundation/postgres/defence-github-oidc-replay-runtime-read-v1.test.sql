begin;

do $$
begin
  if not has_table_privilege(
       'shine_defence_runtime',
       'foundation.github_oidc_operation_bindings',
       'SELECT'
     )
     or not has_table_privilege(
       'shine_defence_runtime',
       'foundation.github_oidc_operation_events',
       'SELECT'
     )
     or not has_table_privilege(
       'shine_defence_runtime',
       'foundation.github_oidc_replay_alert_events',
       'SELECT'
     ) then
    raise exception 'shine_defence_runtime is missing replay-control SELECT privilege';
  end if;

  if not exists (
       select 1 from pg_policies
       where schemaname='foundation'
         and tablename='github_oidc_operation_bindings'
         and policyname='shine_defence_runtime_github_oidc_operation_bindings_select'
         and 'shine_defence_runtime'=any(roles)
     )
     or not exists (
       select 1 from pg_policies
       where schemaname='foundation'
         and tablename='github_oidc_operation_events'
         and policyname='shine_defence_runtime_github_oidc_operation_events_select'
         and 'shine_defence_runtime'=any(roles)
     )
     or not exists (
       select 1 from pg_policies
       where schemaname='foundation'
         and tablename='github_oidc_replay_alert_events'
         and policyname='shine_defence_runtime_github_oidc_replay_alert_events_select'
         and 'shine_defence_runtime'=any(roles)
     ) then
    raise exception 'replay-control RLS policy missing';
  end if;

  if has_table_privilege('anon','foundation.github_oidc_operation_bindings','SELECT')
     or has_table_privilege('authenticated','foundation.github_oidc_operation_events','SELECT')
     or has_table_privilege('anon','foundation.github_oidc_replay_alert_events','SELECT')
     or has_table_privilege('foundation_gateway','foundation.github_oidc_replay_alert_events','SELECT') then
    raise exception 'public/application role unexpectedly gained replay-control read access';
  end if;

end;
$$;

rollback;
