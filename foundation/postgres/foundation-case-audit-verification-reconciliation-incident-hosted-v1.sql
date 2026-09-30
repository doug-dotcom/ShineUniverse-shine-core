-- Foundation Layer 84 hosted wiring.
-- Run one reconciliation-coverage incident evaluation every five minutes.
-- The Layer-83 reader owns the 300-second reconciliation grace window;
-- Layer 84 adds a separate 300-second persistence threshold before opening an incident.

do $layer84_unschedule$
begin
  if exists (
    select 1
    from cron.job
    where jobname='shine-foundation-case-audit-verify-reconcile-incident-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-case-audit-verify-reconcile-incident-5m'
    );
  end if;
end;
$layer84_unschedule$;

select cron.schedule(
  'shine-foundation-case-audit-verify-reconcile-incident-5m',
  '4,9,14,19,24,29,34,39,44,49,54,59 * * * *',
  $$select foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(
      'production',now(),300,300
    );$$
);
