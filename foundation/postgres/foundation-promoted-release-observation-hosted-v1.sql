-- Foundation Layer 64 hosted wiring.
-- Layer 60 closure recording runs at :04/:09/.../:59. Observe consumer-visible
-- promotion state one minute later, every five minutes.

do $layer64_unschedule$
begin
  if exists (
    select 1 from cron.job
    where jobname='shine-foundation-promoted-release-observation-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-promoted-release-observation-5m'
    );
  end if;
end;
$layer64_unschedule$;

select cron.schedule(
  'shine-foundation-promoted-release-observation-5m',
  '0,5,10,15,20,25,30,35,40,45,50,55 * * * *',
  $$select foundation.record_foundation_promoted_release_observation_v1(
      'production',now()
    );$$
);
