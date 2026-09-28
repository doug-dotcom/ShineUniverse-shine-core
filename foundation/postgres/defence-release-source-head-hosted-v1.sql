-- Hosted-only release source-head Sentinel schedule.

select cron.schedule(
  'shine-defence-release-source-head-sentinel-5m',
  '3,8,13,18,23,28,33,38,43,48,53,58 * * * *',
  $$select foundation.run_defence_release_source_head_sentinel_v1(now());$$
);
