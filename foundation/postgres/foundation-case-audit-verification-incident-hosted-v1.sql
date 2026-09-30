-- Foundation Layer 79 hosted wiring.
-- Run one verification-coverage incident evaluation every five minutes.
-- The Layer-78 reader already owns the 300-second verification grace window;
-- Layer 79 adds a separate 300-second persistence threshold before opening an incident.

do $layer79_unschedule$
begin
  if exists (
    select 1
    from cron.job
    where jobname='shine-foundation-case-audit-verify-incident-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-case-audit-verify-incident-5m'
    );
  end if;
end;
$layer79_unschedule$;

select cron.schedule(
  'shine-foundation-case-audit-verify-incident-5m',
  '2,7,12,17,22,27,32,37,42,47,52,57 * * * *',
  $$select foundation.run_case_audit_verify_incident_sentinel_v1(
      'production',now(),300,300
    );$$
);
