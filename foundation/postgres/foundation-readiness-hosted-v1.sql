-- Foundation Layer 30 hosted wiring: continuously record meaningful readiness changes.

do $layer30_unschedule$
begin
  if exists (
    select 1 from cron.job
    where jobname='shine-foundation-readiness-5m'
  ) then
    perform cron.unschedule('shine-foundation-readiness-5m');
  end if;
end;
$layer30_unschedule$;

select cron.schedule(
  'shine-foundation-readiness-5m',
  '*/5 * * * *',
  $$select foundation.record_foundation_readiness_observation_v1('production',now());$$
);
