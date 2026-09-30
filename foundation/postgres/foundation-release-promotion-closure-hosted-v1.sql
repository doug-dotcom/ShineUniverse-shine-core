-- Foundation Layer 60 hosted wiring.
-- Run after the Layer-36 projection observer and Layer-37 incident sentinel.
-- Recording is evidence-only: if Layer 59 is not PASS this returns not-closed
-- and mutates no authoritative truth.

do $layer60_unschedule$
begin
  if exists (
    select 1 from cron.job
    where jobname='shine-foundation-promotion-closure-5m'
  ) then
    perform cron.unschedule('shine-foundation-promotion-closure-5m');
  end if;
end;
$layer60_unschedule$;

select cron.schedule(
  'shine-foundation-promotion-closure-5m',
  '4,9,14,19,24,29,34,39,44,49,54,59 * * * *',
  $$select foundation.record_foundation_release_promotion_closure_v1(
      'production',now()
    );$$
);
