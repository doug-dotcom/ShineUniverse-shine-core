-- Foundation Layer 73 hosted wiring.
-- Layer 65 incident evaluation runs at :01/:06/... and Layer 67 owner handoff
-- materialisation at :03/:08/.... Observe the whole case chain at :04/:09/....

do $layer73_unschedule$
begin
  if exists (
    select 1
    from cron.job
    where jobname='shine-foundation-promoted-release-case-audit-observation-5m'
  ) then
    perform cron.unschedule(
      'shine-foundation-promoted-release-case-audit-observation-5m'
    );
  end if;
end;
$layer73_unschedule$;

select cron.schedule(
  'shine-foundation-promoted-release-case-audit-observation-5m',
  '4,9,14,19,24,29,34,39,44,49,54,59 * * * *',
  $$select foundation.record_foundation_promoted_release_case_audit_observation_v1(
      'production',now()
    );$$
);
