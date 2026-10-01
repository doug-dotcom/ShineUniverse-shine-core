-- Foundation Layer 94 hosted wiring.
-- Evaluate persistent Layer-93 Layer-92 reconciliation-coverage failures every five minutes.
-- Layer 93 owns the 300-second reconciliation grace window; Layer 94 adds a
-- separate 300-second persistence threshold before opening an incident.

do $layer94_unschedule$
begin
  if exists (
    select 1
    from cron.job
    where jobname='shine-foundation-case-audit-layer92-coverage-incident-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-case-audit-layer92-coverage-incident-5m'
    );
  end if;
end;
$layer94_unschedule$;

select cron.schedule(
  'shine-foundation-case-audit-layer92-coverage-incident-5m',
  '1,6,11,16,21,26,31,36,41,46,51,56 * * * *',
  $$select foundation.run_case_audit_layer92_coverage_incident_sentinel_v1(
      'production',now(),300,300
    );$$
);
