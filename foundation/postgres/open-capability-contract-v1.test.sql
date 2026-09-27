\set ON_ERROR_STOP on

begin;

do $test$
declare
  all_caps jsonb;
  travel_caps jsonb;
begin
  select foundation.list_discoverable_capabilities_v1(null) into all_caps;
  if jsonb_array_length(all_caps) <> 3 then
    raise exception 'expected exactly three initial discoverable capabilities, got %', jsonb_array_length(all_caps);
  end if;

  if not exists (
    select 1
    from jsonb_array_elements(all_caps) cap
    where cap->>'capabilityId'='travel.plan_trip'
      and cap->>'appId'='shine.travel'
      and cap->>'invocationState'='declared'
      and (cap->>'invocable')::boolean=false
  ) then
    raise exception 'travel.plan_trip must be declared and non-invocable';
  end if;

  select foundation.list_discoverable_capabilities_v1('shine.travel') into travel_caps;
  if jsonb_array_length(travel_caps) <> 1
     or travel_caps->0->>'capabilityId' <> 'travel.plan_trip' then
    raise exception 'app-scoped capability discovery did not isolate shine.travel';
  end if;
end
$test$;

do $test$
begin
  if has_table_privilege('anon','foundation.app_capabilities','SELECT')
     or has_table_privilege('authenticated','foundation.app_capabilities','SELECT') then
    raise exception 'public client roles must not read the capability catalogue table directly';
  end if;

  if has_table_privilege('anon','foundation.integration_clients','SELECT')
     or has_table_privilege('authenticated','foundation.integration_clients','SELECT') then
    raise exception 'public client roles must not read integration client registry directly';
  end if;

  if has_function_privilege('anon','foundation.list_discoverable_capabilities_v1(text)','EXECUTE')
     or has_function_privilege('authenticated','foundation.list_discoverable_capabilities_v1(text)','EXECUTE') then
    raise exception 'public client roles must not execute discovery database function directly';
  end if;

  if not has_function_privilege('foundation_runtime','foundation.list_discoverable_capabilities_v1(text)','EXECUTE') then
    raise exception 'foundation_runtime must be able to execute discovery database function';
  end if;
end
$test$;

insert into foundation.integration_clients(client_id,display_name,client_kind)
values ('test.layer19.client','Layer 19 Test Client','developer-agent');

insert into foundation.integration_client_credentials(
  credential_id,client_id,token_hash,label,issued_at
) values (
  '19191919-1919-4919-8919-191919191919',
  'test.layer19.client',
  repeat('a',64),
  'test',
  '2026-09-27T01:00:00Z'
);

do $test$
declare
  credential_status text;
begin
  select effective_status into credential_status
  from foundation.effective_integration_client_credentials
  where credential_id='19191919-1919-4919-8919-191919191919';

  if credential_status <> 'active' then
    raise exception 'new integration client credential should be active, got %', credential_status;
  end if;
end
$test$;

insert into foundation.integration_client_credential_revocations(
  revocation_id,credential_id,revoked_at,reason,detail
) values (
  '29292929-2929-4929-8929-292929292929',
  '19191919-1919-4919-8919-191919191919',
  '2026-09-27T01:05:00Z',
  'rotated',
  'layer-19-acceptance'
);

do $test$
declare
  credential_status text;
begin
  select effective_status into credential_status
  from foundation.effective_integration_client_credentials
  where credential_id='19191919-1919-4919-8919-191919191919';

  if credential_status <> 'revoked' then
    raise exception 'revoked integration client credential should be revoked, got %', credential_status;
  end if;
end
$test$;

rollback;
