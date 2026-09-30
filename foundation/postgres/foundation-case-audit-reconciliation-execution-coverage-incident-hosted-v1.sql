-- Foundation Layer 89 hosted wiring.
-- Evaluate persistent Layer-88 reconciliation-coverage failures every five minutes.
-- Layer 88 owns the 300-second reconciliation grace window; Layer 89 adds a
-- separate 300-second persistence threshold before opening an incident.

do $layer89_unschedule$
begin
  if exists (
    select 1
    from cron.job
    where jobname='shine-foundation-case-audit-reconcile-exec-coverage-incident-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-case-audit-reconcile-exec-coverage-incident-5m'
    );
  end if;
end;
$layer89_unschedule$;

select cron.schedule(
  'shine-foundation-case-audit-reconcile-exec-coverage-incident-5m',
  '3,8,13,18,23,28,33,38,43,48,53,58 * * * *',
  $$select foundation.run_case_audit_reconcile_exec_coverage_incident_sentinel_v1(
      'production',now(),300,300
    );$$
);
