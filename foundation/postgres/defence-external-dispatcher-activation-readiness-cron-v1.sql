-- Shine Defence external dispatcher activation readiness cron v1.
-- Periodically verifies GitHub App configuration without dispatching workflows.

create or replace function foundation.invoke_defence_external_dispatcher_readiness_v1(
  p_as_of timestamptz default now()
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog,foundation,net
as $invoke_dispatcher_readiness$
declare
  v_lease jsonb;
  v_request_id bigint;
begin
  if p_as_of is null then
    raise exception 'invalid-defence-dispatcher-readiness-invocation'
      using errcode='22023';
  end if;

  v_lease := foundation.issue_defence_external_dispatcher_readiness_lease_v1(
    p_as_of,120
  );

  select net.http_post(
    url := 'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/defence-external-dispatcher-readiness',
    body := jsonb_build_object(
      'contract','shine-defence/external-dispatcher-readiness-trigger-v1',
      'schemaVersion','1.0.0',
      'leaseId',v_lease->>'leaseId',
      'leaseToken',v_lease->>'leaseToken'
    ),
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'User-Agent','Shine-Defence-Dispatcher-Readiness-Cron/1.0'
    ),
    timeout_milliseconds := 30000
  ) into v_request_id;

  return v_request_id;
end;
$invoke_dispatcher_readiness$;

revoke all on function foundation.invoke_defence_external_dispatcher_readiness_v1(
  timestamptz
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

grant execute on function foundation.invoke_defence_external_dispatcher_readiness_v1(
  timestamptz
) to service_role;


do $schedule_dispatcher_readiness$
begin
  if exists(
    select 1 from cron.job
    where jobname='shine-defence-external-dispatcher-readiness-30m'
  ) then
    perform cron.unschedule('shine-defence-external-dispatcher-readiness-30m');
  end if;

  perform cron.schedule(
    'shine-defence-external-dispatcher-readiness-30m',
    '1,31 * * * *',
    $cron$
      select foundation.invoke_defence_external_dispatcher_readiness_v1(now());
    $cron$
  );
end;
$schedule_dispatcher_readiness$;
