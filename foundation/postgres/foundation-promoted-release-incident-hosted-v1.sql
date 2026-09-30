-- Foundation Layer 65 hosted wiring.
-- Layer 64 records promoted-release trust on minutes :00/:05/.../:55.
-- Evaluate incident lifecycle one minute later.

do $layer65_unschedule$
begin
  if exists (
    select 1 from cron.job
    where jobname='shine-foundation-promoted-release-incident-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-promoted-release-incident-5m'
    );
  end if;
end;
$layer65_unschedule$;

select cron.schedule(
  'shine-foundation-promoted-release-incident-5m',
  '1,6,11,16,21,26,31,36,41,46,51,56 * * * *',
  $$select foundation.run_foundation_promoted_release_incident_sentinel_v1(
      'production',now(),300,600
    );$$
);
