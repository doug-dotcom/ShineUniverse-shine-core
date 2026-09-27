\set ON_ERROR_STOP on
begin;
set role service_role;

insert into foundation.app_registry(app_id,manifest_version,manifest)
values ('shine.status-test','1.0.0',
'{"appId":"shine.status-test","name":"Status Test","foundation":{"standalonePrimaryPurposeAvailable":true,"requestedScopes":[{"scope":"vault.status.read","purpose":"status","resourceCategory":"status"}]}}'::jsonb);

insert into foundation.shine_identities(shine_id)
values ('11111111-1111-4111-8111-111111111111');

insert into foundation.vault_resources(resource_id,owner_shine_id,category,sensitivity)
values ('22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111','status','personal');

reset role;
set role foundation_gateway;

do $$
declare s jsonb;
begin
  select foundation.get_app_operational_status_v1('shine.status-test') into s;
  if s->>'operationalState'<>'registered' or s->>'operationalHealth'<>'healthy' then
    raise exception 'unexpected clean status %',s;
  end if;
  if s #>> '{revocations,freshnessState}' <> 'current' then
    raise exception 'clean app revocation freshness was not current';
  end if;
end
$$;

reset role;
set role service_role;

insert into foundation.access_grants(
  grant_id,owner_shine_id,app_id,scope,purpose,resource_id,status,issued_at,
  consent_method,consent_recorded_at
) values (
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'shine.status-test','vault.status.read','status',
  '22222222-2222-4222-8222-222222222222',
  'active',now(),'explicit-user',now()
);

reset role;
set role foundation_gateway;

select * from foundation.revoke_access_grant_v1(
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666',
  '33333333-3333-4333-8333-333333333333',
  '11111111-1111-4111-8111-111111111111',
  'shine.status-test',now()
);

do $$
declare s jsonb;
begin
  select foundation.get_app_operational_status_v1('shine.status-test') into s;
  if s->>'operationalState'<>'revocation-pending'
     or s->>'operationalHealth'<>'attention' then
    raise exception 'pending revocation not reflected in operational status %',s;
  end if;
  if (s #>> '{revocations,pendingCount}')::integer<>1 then
    raise exception 'pending revocation count missing';
  end if;
end
$$;

rollback;
select 'SHINE FOUNDATION APP OPERATIONAL STATUS V1: PASS' as result;
