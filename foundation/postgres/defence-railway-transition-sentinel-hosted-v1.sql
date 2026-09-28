-- Hosted-only Railway transition Sentinel schedule.

select cron.schedule(
  'shine-defence-railway-transition-sentinel-5m',
  '1,6,11,16,21,26,31,36,41,46,51,56 * * * *',
  $$select foundation.run_defence_railway_transition_sentinel_v1(now());$$
);
