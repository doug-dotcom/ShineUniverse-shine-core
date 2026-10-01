begin;

do $authority_sync_full_estate$
declare
  r jsonb;
  v jsonb;
  t timestamptz := clock_timestamp();
begin
  select foundation.record_defence_attestation_authority_sync_receipt_v1(
    1,
    '7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    'doug-dotcom/ShineUniverse-shine-core/.github/workflows/shine-defence-release-attestation-v1.yml@7bfd7fe685b4b2da814ac53dafdbfac2350591c8',
    '71218df29b79919af76115b9180a6afbbd8dbf79',
    repeat('a',40),
    repeat('b',40),
    repeat('c',40),
    'asserted-current',
    '923456789',
    '1',
    'schedule',
    t,
    'test:authority-sync-full-estate',
    '{}'::jsonb
  ) into r;

  if r->>'status'<>'recorded' then
    raise exception 'full-estate authority sync fixture rejected: %',r;
  end if;

  select foundation.get_defence_full_estate_summary_v1() into v;
  if v->>'schemaVersion'<>'1.14.0'
     or v#>>'{attestationAuthoritySync,state}'<>'pass'
     or v#>>'{attestationAuthorityHeartbeatSentinel,state}'<>'pass'
     or v#>>'{attestationAuthorityHeartbeatSentinel,band}'<>'current'
     or v#>>'{correlatedTransportAttribution,defenceCorrelatedTransportAttribution}'<>
        'shine-defence/correlated-transport-attribution-v1'
     or v#>>'{correlatedTransportAttribution,rawEstateStateOverridden}' is distinct from 'false'
     or v#>>'{operationalAttention,defenceOperationalAttention}'<>
        'shine-defence/operational-attention-v1'
     or v#>>'{operationalAttention,schemaVersion}'<>'1.2.0'
     or v#>>'{operationalAttention,rawEstateStateOverridden}' is distinct from 'false'
     or v#>>'{operationalAttention,sleepAwareOverlay,rawEstateStateOverridden}' is distinct from 'false'
     or v#>>'{operationalAttention,revalidationControl,approvalRequired}'<>'true'
     or v#>>'{operationalAttention,revalidationControl,externalMutationAutomatic}'<>'false'
     or v#>>'{attestationAuthoritySync,currentAuthority,authoritySha}'<>
        '7bfd7fe685b4b2da814ac53dafdbfac2350591c8' then
    raise exception 'authority sync missing from full-estate summary: %',v;
  end if;
end;
$authority_sync_full_estate$;

rollback;
