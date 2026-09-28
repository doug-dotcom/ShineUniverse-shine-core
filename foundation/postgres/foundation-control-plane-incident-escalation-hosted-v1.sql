-- Foundation Layer 37 hosted wiring: escalate persistent release-projection
-- FAIL/UNKNOWN states after one full five-minute persistence window.

do $layer37_unschedule$
begin
  if exists (
    select 1 from cron.job
    where jobname='shine-foundation-control-plane-incident-5m'
  ) then
    perform cron.unschedule('shine-foundation-control-plane-incident-5m');
  end if;
end;
$layer37_unschedule$;

select cron.schedule(
  'shine-foundation-control-plane-incident-5m',
  '2,7,12,17,22,27,32,37,42,47,52,57 * * * *',
  $$select foundation.run_foundation_control_plane_incident_sentinel_v1(
      'production',now(),300
    );$$
);
