-- Test-only historical data fixture.
-- Production already had these three canonical apps registered before
-- foundation_open_capability_contract_v1 ran. Migration history did not
-- create those registry rows, so a clean CI database seeds equivalent state.

insert into foundation.app_registry(app_id,manifest_version,manifest,status)
values
(
  'shine.travel',
  '1.0.0',
  '{
    "name":"Shine Travel",
    "appId":"shine.travel",
    "version":"1.0.0",
    "manifest":"shine-foundation/app-manifest-v1",
    "foundation":{
      "contract":"shine-foundation/foundation-v1",
      "requestedScopes":[{
        "scope":"vault.foundation.pilot.read",
        "purpose":"travel.foundation-pilot",
        "optional":true,
        "resourceCategory":"foundation.pilot"
      }],
      "onFoundationUnavailable":"continue-standalone",
      "standalonePrimaryPurposeAvailable":true
    },
    "schemaVersion":"1.0.0",
    "primaryPurpose":"Private holiday planning and on-trip guidance.",
    "supportedModes":["standalone","connected","universe-enhanced"]
  }'::jsonb,
  'active'
),
(
  'shine.dive',
  '1.0.0',
  '{
    "name":"Shine Dive",
    "appId":"shine.dive",
    "version":"1.0.0",
    "manifest":"shine-foundation/app-manifest-v1",
    "foundation":{
      "contract":"shine-foundation/foundation-v1",
      "requestedScopes":[{
        "scope":"vault.foundation.pilot.read",
        "purpose":"dive.foundation-pilot",
        "optional":true,
        "resourceCategory":"foundation.pilot"
      }],
      "onFoundationUnavailable":"continue-standalone",
      "standalonePrimaryPurposeAvailable":true
    },
    "schemaVersion":"1.0.0",
    "primaryPurpose":"Personal dive logbook, planning, equipment and diving companion.",
    "supportedModes":["standalone","connected","universe-enhanced"]
  }'::jsonb,
  'active'
),
(
  'shine.ski',
  '1.0.0',
  '{
    "name":"Shine Ski",
    "appId":"shine.ski",
    "version":"1.0.0",
    "manifest":"shine-foundation/app-manifest-v1",
    "foundation":{
      "contract":"shine-foundation/foundation-v1",
      "requestedScopes":[{
        "scope":"vault.foundation.pilot.read",
        "purpose":"ski.foundation-pilot",
        "optional":true,
        "resourceCategory":"foundation.pilot"
      }],
      "onFoundationUnavailable":"continue-standalone",
      "standalonePrimaryPurposeAvailable":true
    },
    "schemaVersion":"1.0.0",
    "primaryPurpose":"Local-first skiing and snowboarding companion for resort discovery, learning, packing and mountain-day tracking.",
    "supportedModes":["standalone","connected","universe-enhanced"]
  }'::jsonb,
  'active'
)
on conflict (app_id) do nothing;
