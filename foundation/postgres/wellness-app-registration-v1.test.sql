-- Shine Wellness registration acceptance tests.
-- Registration must remain identity-only: no credential, provider, grant or capability.

do $test$
declare
  v_manifest jsonb;
  v_state text;
begin
  select manifest
  into v_manifest
  from foundation.app_registry
  where app_id='shine.wellness'
    and manifest_version='1.0.0'
    and status='active';

  if v_manifest is null then
    raise exception 'shine.wellness is not actively registered';
  end if;

  if v_manifest->>'manifest' <> 'shine-foundation/app-manifest-v1'
     or v_manifest->>'schemaVersion' <> '1.0.0'
     or v_manifest->>'name' <> 'Shine Wellness'
     or v_manifest->>'version' <> '0.1.0'
     or v_manifest#>>'{foundation,contract}' <> 'shine-foundation/foundation-v1'
     or coalesce((v_manifest#>>'{foundation,standalonePrimaryPurposeAvailable}')::boolean,false) is not true then
    raise exception 'shine.wellness manifest identity is invalid';
  end if;

  if jsonb_array_length(v_manifest#>'{foundation,requestedScopes}') <> 0 then
    raise exception 'shine.wellness registration must request zero scopes';
  end if;

  if exists (
    select 1 from foundation.app_credentials
    where app_id='shine.wellness'
  ) then
    raise exception 'registration unexpectedly provisioned an app credential';
  end if;

  if exists (
    select 1 from foundation.app_identity_providers
    where app_id='shine.wellness'
  ) then
    raise exception 'registration unexpectedly linked an identity provider';
  end if;

  if exists (
    select 1 from foundation.access_grants
    where app_id='shine.wellness'
  ) then
    raise exception 'registration unexpectedly granted Vault access';
  end if;

  select connection_state
  into v_state
  from foundation.app_connection_status
  where app_id='shine.wellness';

  if v_state is distinct from 'registered' then
    raise exception 'shine.wellness connection state must be registered, got %', v_state;
  end if;
end
$test$;
