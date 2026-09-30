-- Foundation Layer 67 hosted wiring.
-- Layer 65 evaluates promotion-trust incidents at :01/:06/.../:56.
-- Materialise owner work two minutes later, after Layer-37 projection incident
-- reconciliation at :02/:07/.../:57.

do $layer67_unschedule$
begin
  if exists (
    select 1 from cron.job
    where jobname='shine-foundation-promoted-release-owner-handoff-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-promoted-release-owner-handoff-5m'
    );
  end if;
end;
$layer67_unschedule$;

select cron.schedule(
  'shine-foundation-promoted-release-owner-handoff-5m',
  '3,8,13,18,23,28,33,38,43,48,53,58 * * * *',
  $$select foundation.generate_foundation_promoted_release_owner_handoff_v1(
      'production',now()
    );$$
);
