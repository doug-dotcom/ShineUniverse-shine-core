\set ON_ERROR_STOP on

begin;

-- Security surface: clients cannot reach the private persistence schema.
do $$
begin
  if has_schema_privilege('anon','foundation','USAGE') then
    raise exception 'anon unexpectedly has foundation schema usage';
  end if;
  if has_schema_privilege('authenticated','foundation','USAGE') then
    raise exception 'authenticated unexpectedly has foundation schema usage';
  end if;
  if not has_schema_privilege('service_role','foundation','USAGE') then
    raise exception 'service_role missing foundation schema usage';
  end if;
end
$$;

-- Every Foundation persistence table has RLS enabled.
do $$
declare
  missing text;
begin
  select string_agg(c.relname, ', ')
  into missing
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='foundation'
    and c.relkind='r'
    and c.relname in (
      'app_registry','shine_identities','identity_bindings','vault_resources',
      'access_grants','grant_revocations','revocation_outbox','access_audit_events'
    )
    and not c.relrowsecurity;

  if missing is not null then
    raise exception 'RLS disabled on: %', missing;
  end if;
end
$$;

set role service_role;

insert into foundation.app_registry(app_id,manifest_version,manifest)
values (
  'shine.travel',
  '1.0.0',
  '{"appId":"shine.travel","foundation":{"requestedScopes":[{"scope":"vault.location.read","purpose":"travel.home-airport","resourceCategory":"profile.location"}]}}'::jsonb
);

insert into foundation.shine_identities(shine_id)
values ('11111111-1111-4111-8111-111111111111');

insert into foundation.vault_resources(
  resource_id, owner_shine_id, category, sensitivity, content_type, storage_ref, provenance
) values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'profile.location',
  'personal',
  'application/json',
  'vault://profile/location/home-airport',
  '{"source":"user"}'::jsonb
);

insert into foundation.access_grants(
  grant_id, owner_shine_id, app_id, scope, purpose, resource_id,
  issued_at, expires_at, consent_method, consent_recorded_at
) values (
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'shine.travel',
  'vault.location.read',
  'travel.home-airport',
  '22222222-2222-4222-8222-222222222222',
  '2026-09-01T00:00:00Z',
  '2026-12-01T00:00:00Z',
  'explicit-user',
  '2026-09-01T00:00:00Z'
);

do $$
declare
  state text;
begin
  select effective_status into state
  from foundation.effective_access_grants
  where grant_id='33333333-3333-4333-8333-333333333333';

  if state <> 'active' then
    raise exception 'expected active grant, got %', state;
  end if;
end
$$;

-- Audit both allow and deny decisions.
insert into foundation.access_audit_events(
  event_id, request_id, decision_id, app_id, shine_id, scope, purpose,
  resource_id, decision, reason_code, grant_id, occurred_at
) values (
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666',
  'shine.travel',
  '11111111-1111-4111-8111-111111111111',
  'vault.location.read',
  'travel.home-airport',
  '22222222-2222-4222-8222-222222222222',
  'allow',
  'grant-match',
  '33333333-3333-4333-8333-333333333333',
  '2026-09-26T06:00:00Z'
);

insert into foundation.access_audit_events(
  event_id, request_id, app_id, shine_id, scope, purpose,
  resource_id, decision, reason_code, occurred_at
) values (
  '77777777-7777-4777-8777-777777777777',
  '88888888-8888-4888-8888-888888888888',
  'shine.travel',
  '11111111-1111-4111-8111-111111111111',
  'vault.location.write',
  'travel.home-airport',
  '22222222-2222-4222-8222-222222222222',
  'deny',
  'scope-not-declared',
  '2026-09-26T06:01:00Z'
);

-- Revoke once: this must synchronously emit exactly one monotonic outbox event.
insert into foundation.grant_revocations(
  revocation_id, grant_id, owner_shine_id, revoked_at, reason
) values (
  '99999999-9999-4999-8999-999999999999',
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  '2026-09-26T06:02:00Z',
  'user-revoked'
);

do $$
declare
  state text;
  outbox_count integer;
  event_name text;
begin
  select effective_status into state
  from foundation.effective_access_grants
  where grant_id='33333333-3333-4333-8333-333333333333';

  if state <> 'revoked' then
    raise exception 'expected revoked grant, got %', state;
  end if;

  select count(*), min(payload->>'event')
  into outbox_count, event_name
  from foundation.revocation_outbox
  where grant_id='33333333-3333-4333-8333-333333333333';

  if outbox_count <> 1 then
    raise exception 'expected one revocation outbox event, got %', outbox_count;
  end if;

  if event_name <> 'shine-foundation/grant-revocation-v1' then
    raise exception 'unexpected revocation payload event %', event_name;
  end if;
end
$$;

-- Duplicate revocation must fail and cannot create another propagation event.
do $$
begin
  begin
    insert into foundation.grant_revocations(
      revocation_id, grant_id, owner_shine_id, revoked_at, reason
    ) values (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '33333333-3333-4333-8333-333333333333',
      '11111111-1111-4111-8111-111111111111',
      '2026-09-26T06:03:00Z',
      'administrative'
    );
    raise exception 'duplicate revocation unexpectedly succeeded';
  exception
    when unique_violation then null;
  end;
end
$$;

-- Grant and audit history are immutable from the trusted persistence role.
do $$
begin
  begin
    update foundation.access_grants
      set purpose='other-purpose'
      where grant_id='33333333-3333-4333-8333-333333333333';
    raise exception 'grant update unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
    when object_not_in_prerequisite_state then null;
  end;

  begin
    delete from foundation.access_audit_events
      where event_id='44444444-4444-4444-8444-444444444444';
    raise exception 'audit delete unexpectedly succeeded';
  exception
    when insufficient_privilege then null;
    when object_not_in_prerequisite_state then null;
  end;
end
$$;

reset role;

-- Even database-owner mutation is rejected by append-only triggers.
do $$
begin
  begin
    update foundation.access_audit_events
      set reason_code='tampered'
      where event_id='44444444-4444-4444-8444-444444444444';
    raise exception 'owner audit update unexpectedly succeeded';
  exception
    when object_not_in_prerequisite_state then null;
  end;
end
$$;

rollback;

select 'SHINE FOUNDATION PERSISTENCE: PASS' as result;
