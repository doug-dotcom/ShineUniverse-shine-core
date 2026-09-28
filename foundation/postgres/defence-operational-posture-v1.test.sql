begin;

do $$
declare
  v jsonb;
begin
  select foundation.evaluate_defence_posture_v1('production') into v;
  if v->>'overallState' <> 'pass' then
    raise exception 'initial Defence posture should pass: %',v;
  end if;
  if v#>>'{checks,rls,state}' <> 'pass'
     or v#>>'{checks,serviceToService,state}' <> 'pass'
     or v#>>'{checks,secrets,state}' <> 'pass'
     or v#>>'{checks,dataExposure,state}' <> 'pass'
     or v#>>'{checks,deploymentIntegrity,state}' <> 'pass' then
    raise exception 'local Defence controls should pass: %',v;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_roles
    where rolname='shine_defence_runtime'
      and not rolsuper
      and not rolcreaterole
      and not rolcreatedb
      and not rolcanlogin
      and not rolbypassrls
  ) then
    raise exception 'shine_defence_runtime must be NOLOGIN and non-privileged';
  end if;

  if has_function_privilege('anon','foundation.evaluate_defence_posture_v1(text)','EXECUTE')
     or has_function_privilege('authenticated','foundation.evaluate_defence_posture_v1(text)','EXECUTE') then
    raise exception 'public roles must not execute internal Defence posture';
  end if;

  if not has_function_privilege('shine_defence_runtime','foundation.evaluate_defence_posture_v1(text)','EXECUTE') then
    raise exception 'shine_defence_runtime must execute posture evaluation';
  end if;

  if has_table_privilege('anon','foundation.defence_external_evidence','SELECT')
     or has_table_privilege('authenticated','foundation.defence_posture_observations','SELECT') then
    raise exception 'public roles must not read Defence control-plane tables';
  end if;
end;
$$;

do $$
begin
  begin
    perform foundation.record_defence_external_evidence_v1(
      'auth','foundation.gateway','pass',null,now(),now()+interval '1 hour',
      'manual-verified','test:sensitive-key',
      jsonb_build_object('token','must-not-be-stored')
    );
    raise exception 'sensitive metadata key unexpectedly accepted';
  exception
    when sqlstate '22023' then
      null;
  end;
end;
$$;

insert into foundation.defence_external_evidence(
  domain,subject_ref,status,artifact_sha256,observed_at,valid_until,evidence_kind,evidence_ref,metadata
) values (
  'dependencies','test.subject','warning',null,now(),now()+interval '1 hour',
  'manual-verified','test:append-only','{}'::jsonb
);

do $$
begin
  begin
    update foundation.defence_external_evidence
       set status='pass'
     where subject_ref='test.subject';
    raise exception 'append-only Defence evidence update unexpectedly succeeded';
  exception
    when sqlstate '55000' then
      null;
  end;
end;
$$;

select foundation.evaluate_defence_posture_v1('production');
select * from foundation.current_defence_posture where environment='production';

do $$
begin
  if to_regclass('foundation.integration_delegation_refresh_requests') is not null then
    if not (
      select c.relrowsecurity
      from pg_class c
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='foundation'
        and c.relname='integration_delegation_refresh_requests'
    ) then
      raise exception 'delegation refresh request store must have RLS enabled';
    end if;
  end if;
end;
$$;

rollback;
