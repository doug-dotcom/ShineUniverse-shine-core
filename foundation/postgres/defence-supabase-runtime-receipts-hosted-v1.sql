-- Shine Defence hosted Supabase runtime receipt collector v1.
-- Credential-free polling of the six protected Supabase estate projects.

create or replace function foundation.enqueue_defence_supabase_runtime_receipts_v1()
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net
as $$
declare
  v_target foundation.defence_estate_targets%rowtype;
  v_external_request_id bigint;
  v_queued integer := 0;
  v_url text;
begin
  for v_target in
    select *
    from foundation.defence_estate_targets
    where provider='supabase'
      and lifecycle='active'
      and required_for_estate
      and metadata->>'runtimeReceiptRequired'='true'
    order by target_id
  loop
    v_url :=
      'https://' || v_target.provider_project_ref ||
      '.supabase.co/functions/v1/' ||
      coalesce(v_target.metadata->>'receiptFunction','defence-runtime-receipt');

    v_external_request_id := net.http_get(
      url := v_url,
      headers := jsonb_build_object(
        'Accept','application/json',
        'User-Agent','Shine-Defence-Supabase-Receipt/1.0',
        'x-region',v_target.metadata->>'projectRegion'
      ),
      timeout_milliseconds := 10000
    );

    insert into foundation.defence_supabase_runtime_receipt_requests(
      target_id,external_request_id,target_url,queued_at,evidence_ref,metadata
    ) values (
      v_target.target_id,
      v_external_request_id,
      v_url,
      now(),
      'pg-net:supabase-runtime-receipt-request:' ||
        v_target.target_id || ':' || v_external_request_id::text,
      jsonb_build_object(
        'collector','shine-defence/supabase-runtime-receipt-v1'
      )
    );

    v_queued := v_queued+1;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'collector','shine-defence/supabase-runtime-receipt-v1',
    'queued',v_queued
  );
end;
$$;

revoke all on function foundation.enqueue_defence_supabase_runtime_receipts_v1()
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.enqueue_defence_supabase_runtime_receipts_v1()
  to service_role;


create or replace function foundation.harvest_defence_supabase_runtime_receipts_v1(
  p_limit integer default 100
)
returns jsonb
language plpgsql
security invoker
set search_path = pg_catalog, foundation, net
as $$
declare
  v_row record;
  v_payload jsonb;
  v_result jsonb;
  v_harvested integer := 0;
  v_recorded integer := 0;
  v_rejected integer := 0;
begin
  if p_limit < 1 or p_limit > 500 then
    raise exception 'p_limit must be between 1 and 500';
  end if;

  for v_row in
    select
      q.request_id,
      q.target_id,
      q.external_request_id,
      q.queued_at,
      r.status_code,
      r.content,
      r.created as response_at
    from foundation.defence_supabase_runtime_receipt_requests q
    join net._http_response r
      on r.id=q.external_request_id
    left join foundation.defence_supabase_runtime_receipt_observations existing
      on existing.evidence_ref like (
        'supabase-runtime-receipt:' || q.target_id || ':%'
      )
      and existing.observed_at=r.created
    where q.external_request_id is not null
      and existing.observation_id is null
    order by q.queued_at
    limit p_limit
  loop
    begin
      v_payload := v_row.content::jsonb;
    exception
      when others then
        v_payload := '{}'::jsonb;
    end;

    v_result := foundation.record_defence_supabase_runtime_receipt_v1(
      v_row.target_id,
      v_payload,
      v_row.status_code,
      v_row.response_at
    );

    v_harvested := v_harvested+1;

    if v_result->>'status'='recorded' then
      v_recorded := v_recorded+1;
    elsif v_result->>'status'='rejected' then
      v_rejected := v_rejected+1;
    end if;
  end loop;

  return jsonb_build_object(
    'status','ok',
    'collector','shine-defence/supabase-runtime-receipt-v1',
    'harvested',v_harvested,
    'recorded',v_recorded,
    'rejected',v_rejected
  );
end;
$$;

revoke all on function foundation.harvest_defence_supabase_runtime_receipts_v1(integer)
  from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.harvest_defence_supabase_runtime_receipts_v1(integer)
  to service_role;


select cron.schedule(
  'shine-defence-supabase-runtime-receipt-probe-5m',
  '4,9,14,19,24,29,34,39,44,49,54,59 * * * *',
  $$select foundation.enqueue_defence_supabase_runtime_receipts_v1();$$
);

select cron.schedule(
  'shine-defence-supabase-runtime-receipt-harvest-1m',
  '* * * * *',
  $$select foundation.harvest_defence_supabase_runtime_receipts_v1(100);$$
);

select cron.schedule(
  'shine-defence-supabase-runtime-receipt-sentinel-hourly',
  '28 * * * *',
  $$select foundation.run_defence_supabase_runtime_receipt_sentinel_v1(now());$$
);
