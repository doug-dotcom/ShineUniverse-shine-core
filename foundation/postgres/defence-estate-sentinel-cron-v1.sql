-- Shine Defence federated estate Sentinel hosted schedule v1.
-- Evaluate current cross-project observations after the core Foundation Sentinel.

select cron.schedule(
  'shine-defence-estate-sentinel-hourly',
  '29 * * * *',
  $$select foundation.run_defence_estate_sentinel_v1(now());$$
);
