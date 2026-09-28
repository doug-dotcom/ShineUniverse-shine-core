-- Hosted-only Shine Defence release admission reconciliation v1.
-- Decision-only: this never calls Railway or performs rollback actions.

select cron.unschedule(jobid)
from cron.job
where jobname='shine-defence-release-admission-1m';

select cron.schedule(
  'shine-defence-release-admission-1m',
  '* * * * *',
  $$select foundation.reconcile_defence_release_admission_v1(now());$$
);
