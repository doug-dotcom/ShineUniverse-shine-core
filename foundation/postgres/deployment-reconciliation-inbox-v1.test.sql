begin;

insert into foundation.service_registry(
  service_id,display_name,owner_component,service_kind,contract_ref,
  required_for_core,lifecycle,metadata
)
values (
  'test.layer31.service',
  'Layer 31 Test Service',
  'shine-core',
  'internal-service',
  'test/layer31',
  false,
  'active',
  '{}'::jsonb
);

do $$
declare
  v jsonb;
begin
  select foundation.submit_service_deployment_receipt_v1(
    'test.layer31.service',
    'test',
    'manual-verified',
    'test://layer31/runtime',
    '2',
    repeat('a',64),
    'active',
    'github://doug-dotcom/ShineUniverse-shine-core/commit/1111111111111111111111111111111111111111',
    'test:provider:evidence:v2',
    now(),
    'layer31-test',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status' <> 'reconciled' then
    raise exception 'deployment receipt should reconcile: %',v;
  end if;

  if v#>>'{deploymentTruth,deploymentState}' <> 'aligned' then
    raise exception 'receipt should produce aligned deployment truth: %',v;
  end if;

  select foundation.get_deployment_reconciliation_status_v1(
    'test.layer31.service','test'
  ) into v;

  if v->>'state' <> 'awaiting-proof' then
    raise exception 'new runtime without health should await proof: %',v;
  end if;

  select foundation.submit_service_deployment_receipt_v1(
    'test.layer31.service',
    'test',
    'manual-verified',
    'test://layer31/runtime',
    '2',
    repeat('a',64),
    'active',
    'github://doug-dotcom/ShineUniverse-shine-core/commit/1111111111111111111111111111111111111111',
    'test:provider:evidence:v2',
    now(),
    'layer31-test',
    '{"test":true}'::jsonb
  ) into v;

  if v->>'status' <> 'replayed' then
    raise exception 'identical deployment receipt should replay idempotently: %',v;
  end if;
end;
$$;


do $$
begin
  begin
    perform foundation.submit_service_deployment_receipt_v1(
      'test.layer31.service','test','manual-verified','test://layer31/runtime',
      '1',repeat('b',64),'active',
      'github://doug-dotcom/ShineUniverse-shine-core/commit/2222222222222222222222222222222222222222',
      'test:provider:evidence:v1',now(),'layer31-test','{}'::jsonb
    );
    raise exception 'version regression unexpectedly accepted';
  exception
    when others then
      if sqlerrm='version regression unexpectedly accepted' then raise; end if;
      if position('deployment-receipt-version-regression' in sqlerrm)=0 then raise; end if;
  end;

  begin
    perform foundation.submit_service_deployment_receipt_v1(
      'foundation.gateway','production','supabase-edge',
      'supabase://wrong/functions/foundation-gateway',
      '999',repeat('c',64),'active',
      'github://doug-dotcom/ShineUniverse-shine-core/commit/3333333333333333333333333333333333333333',
      'test:provider:evidence:v999',now(),'layer31-test','{}'::jsonb
    );
    raise exception 'wrong Gateway runtime ref unexpectedly accepted';
  exception
    when others then
      if sqlerrm='wrong Gateway runtime ref unexpectedly accepted' then raise; end if;
      if position('deployment-receipt-runtime-ref-mismatch' in sqlerrm)=0 then raise; end if;
  end;
end;
$$;


do $$
begin
  begin
    update foundation.service_deployment_receipts
    set runtime_version='mutated'
    where service_id='test.layer31.service';
    raise exception 'append-only receipt mutation unexpectedly succeeded';
  exception
    when sqlstate '55000' then null;
  end;

  if has_table_privilege(
    'foundation_gateway',
    'foundation.service_deployment_receipts',
    'INSERT'
  ) then
    raise exception 'Gateway must not directly insert deployment receipts';
  end if;

  if has_function_privilege(
    'foundation_gateway',
    'foundation.submit_service_deployment_receipt_v1(text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Gateway must not submit management-plane receipts';
  end if;

  if has_function_privilege(
    'foundation_runtime',
    'foundation.submit_service_deployment_receipt_v1(text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'Foundation runtime must not submit management-plane receipts';
  end if;

  if not has_function_privilege(
    'service_role',
    'foundation.submit_service_deployment_receipt_v1(text,text,text,text,text,text,text,text,text,timestamptz,text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'service_role must submit verified deployment receipts';
  end if;

  if not has_function_privilege(
    'foundation_runtime',
    'foundation.get_deployment_reconciliation_status_v1(text,text)',
    'EXECUTE'
  ) then
    raise exception 'Foundation runtime must read reconciliation status';
  end if;

  if has_function_privilege(
    'anon',
    'foundation.get_deployment_reconciliation_status_v1(text,text)',
    'EXECUTE'
  ) then
    raise exception 'anon must not read deployment reconciliation status';
  end if;
end;
$$;

rollback;
