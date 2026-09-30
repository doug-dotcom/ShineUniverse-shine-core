-- Shine Wellness Foundation registration v1
-- Registers the application identity only. It grants no Vault access,
-- creates no credential, links no identity provider and declares no capability.

do $registration$
declare
  v_manifest constant jsonb := '{"manifest":"shine-foundation/app-manifest-v1","schemaVersion":"1.0.0","appId":"shine.wellness","name":"Shine Wellness","version":"0.1.0","primaryPurpose":"Person-centred health organiser, translator, historian and bridge that turns records, measurements, medications, care and wellbeing into one understandable longitudinal story.","supportedModes":["standalone","connected","universe-enhanced"],"foundation":{"contract":"shine-foundation/foundation-v1","standalonePrimaryPurposeAvailable":true,"requestedScopes":[],"onFoundationUnavailable":"continue-standalone"}}'::jsonb;
  v_existing foundation.app_registry%rowtype;
begin
  select *
  into v_existing
  from foundation.app_registry
  where app_id='shine.wellness'
  for update;

  if not found then
    insert into foundation.app_registry(
      app_id,
      manifest_version,
      manifest,
      status
    ) values (
      'shine.wellness',
      '1.0.0',
      v_manifest,
      'active'
    );
  else
    if v_existing.manifest_version <> '1.0.0'
       or v_existing.manifest <> v_manifest
       or v_existing.status <> 'active' then
      raise exception 'shine.wellness registration exists with a different identity or state'
        using errcode='23514';
    end if;
  end if;
end
$registration$;
