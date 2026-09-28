-- Shine Defence Sentinel hosted scheduler v1.
-- Hosted-only integration: Supabase Cron / pg_cron is not part of the vanilla
-- PostgreSQL clean-rebuild used by repository CI.

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.schedule(
  'shine-defence-sentinel-hourly',
  '17 * * * *',
  $$select foundation.run_defence_sentinel_v1('production',now());$$
);

select cron.schedule(
  'shine-defence-sentinel-history-prune',
  '43 3 * * 0',
  $$
    delete from cron.job_run_details
    where jobid=(
      select jobid
      from cron.job
      where jobname='shine-defence-sentinel-hourly'
      limit 1
    )
    and end_time < now()-interval '30 days';
  $$
);
