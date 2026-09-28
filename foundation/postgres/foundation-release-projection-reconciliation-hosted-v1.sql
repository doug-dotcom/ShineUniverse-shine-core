-- Foundation Layer 36 hosted wiring: continuously reconcile registry/release/binding truth.
-- Stagger one minute after the five-minute Foundation readiness/health cycle.

do $layer36_unschedule$
begin
  if exists (
    select 1 from cron.job
    where jobname='shine-foundation-release-projection-5m'
  ) then
    perform cron.unschedule('shine-foundation-release-projection-5m');
  end if;
end;
$layer36_unschedule$;

select cron.schedule(
  'shine-foundation-release-projection-5m',
  '1,6,11,16,21,26,31,36,41,46,51,56 * * * *',
  $$select foundation.record_foundation_release_projection_observation_v1('production',now());$$
);
