-- Shine Defence external attestation dispatcher cron v1.
-- Supabase Cron invokes the dispatcher with a short-lived single-use DB lease.
-- The lease is custom inbound authentication for the public Edge Function.

create or replace function foundation.invoke_defence_external_attestation_dispatcher_v1(
  p_as_of timestamptz default now()
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog,foundation,net
as $invoke_external_dispatcher$
declare
  v_lease jsonb;
  v_request_id bigint;
begin
  if p_as_of is null then
    raise exception 'invalid-defence-external-dispatcher-invocation'
      using errcode='22023';
  end if;

  v_lease := foundation.issue_defence_external_dispatch_lease_v1(
    p_as_of,120
  );

  select net.http_post(
    url := 'https://sjpxqeyewahraxvidvcc.supabase.co/functions/v1/defence-external-attestation-dispatcher',
    body := jsonb_build_object(
      'contract','shine-defence/external-attestation-dispatch-trigger-v1',
      'schemaVersion','1.0.0',
      'leaseId',v_lease->>'leaseId',
      'leaseToken',v_lease->>'leaseToken'
    ),
    params := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'User-Agent','Shine-Defence-External-Dispatcher-Cron/1.0'
    ),
    timeout_milliseconds := 30000
  ) into v_request_id;

  return v_request_id;
end;
$invoke_external_dispatcher$;

revoke all on function foundation.invoke_defence_external_attestation_dispatcher_v1(
  timestamptz
) from public,anon,authenticated,foundation_gateway,foundation_runtime,shine_defence_runtime;

grant execute on function foundation.invoke_defence_external_attestation_dispatcher_v1(
  timestamptz
) to service_role;


do $schedule_external_dispatcher$
begin
  if exists(
    select 1 from cron.job
    where jobname='shine-defence-external-attestation-dispatcher-10m'
  ) then
    perform cron.unschedule('shine-defence-external-attestation-dispatcher-10m');
  end if;

  perform cron.schedule(
    'shine-defence-external-attestation-dispatcher-10m',
    '6,16,26,36,46,56 * * * *',
    $cron$
      select foundation.invoke_defence_external_attestation_dispatcher_v1(now());
    $cron$
  );
end;
$schedule_external_dispatcher$;
