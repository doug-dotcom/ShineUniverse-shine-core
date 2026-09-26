\set ON_ERROR_STOP on
begin;

set role service_role;

insert into foundation.app_registry(app_id,manifest_version,manifest)
values ('shine.travel','1.0.0','{"appId":"shine.travel","foundation":{"requestedScopes":[]}}'::jsonb);

insert into foundation.app_credentials(
  credential_id, app_id, token_hash, label, issued_at, expires_at
) values (
  '10101010-1010-4010-8010-101010101010',
  'shine.travel',
  '4c0ffa9a073e5e47ee51e8352cee4b05d0c21f75b501e314e2ffae28fd635909',
  'runtime-test',
  '2026-09-01T00:00:00Z',
  '2026-12-01T00:00:00Z'
);

reset role;

do $$
begin
  if (select rolcanlogin from pg_roles where rolname='foundation_gateway') then
    raise exception 'foundation_gateway must remain NOLOGIN';
  end if;
end
$$;

set role foundation_gateway;

do $$
declare state text;
begin
  select effective_status into state
  from foundation.effective_app_credentials
  where token_hash='4c0ffa9a073e5e47ee51e8352cee4b05d0c21f75b501e314e2ffae28fd635909';
  if state <> 'active' then raise exception 'expected active app credential, got %', state; end if;
end
$$;

insert into foundation.access_audit_events(
  event_id, request_id, app_id, shine_id, scope, purpose,
  decision, reason_code, occurred_at
) values (
  '20202020-2020-4020-8020-202020202020',
  '30303030-3030-4030-8030-303030303030',
  'shine.unknown',
  '40404040-4040-4040-8040-404040404040',
  'vault.test.read',
  'runtime.attestation',
  'deny',
  'app-caller-unverified',
  '2026-09-26T07:00:00Z'
);

do $$
declare n integer;
begin
  select count(*) into n from foundation.access_audit_events
  where request_id='30303030-3030-4030-8030-303030303030';
  if n <> 1 then raise exception 'unknown caller denial was not auditable'; end if;
end
$$;

do $$
begin
  begin
    insert into foundation.app_credentials(
      credential_id, app_id, token_hash
    ) values (
      '50505050-5050-4050-8050-505050505050',
      'shine.travel',
      '539e915a40033497f3a93ce662c8c1940c84503361223312e6fab7c5f3a3fdda'
    );
    raise exception 'runtime unexpectedly provisioned an app credential';
  exception when insufficient_privilege then null;
  end;
end
$$;

reset role;
set role service_role;

insert into foundation.app_credential_revocations(
  revocation_id, credential_id, revoked_at, reason
) values (
  '60606060-6060-4060-8060-606060606060',
  '10101010-1010-4010-8010-101010101010',
  '2026-09-26T07:01:00Z',
  'rotated'
);

reset role;
set role foundation_gateway;

do $$
declare state text;
begin
  select effective_status into state
  from foundation.effective_app_credentials
  where credential_id='10101010-1010-4010-8010-101010101010';
  if state <> 'revoked' then raise exception 'expected revoked app credential, got %', state; end if;
end
$$;

rollback;
select 'SHINE FOUNDATION RUNTIME SQL: PASS' as result;
