-- Foundation Layer 74 hosted wiring.
-- Layer 73 records the complete case audit at :04/:09/... . Evaluate the
-- case-audit incident lifecycle one minute later.

do $layer74_unschedule$
begin
  if exists (
    select 1
    from cron.job
    where jobname='shine-foundation-promoted-release-case-audit-incident-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-promoted-release-case-audit-incident-5m'
    );
  end if;
end;
$layer74_unschedule$;

select cron.schedule(
  'shine-foundation-promoted-release-case-audit-incident-5m',
  '0,5,10,15,20,25,30,35,40,45,50,55 * * * *',
  $$select foundation.run_foundation_promoted_release_case_audit_incident_sentinel_v1(
      'production',now(),300,600
    );$$
);
