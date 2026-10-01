begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-control-overlay','Control Overlay Test','railway',
  '81111111-1111-4111-8111-111111111111',
  '82222222-2222-4222-8222-222222222222',
  '83333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active','sleeping']::text[],'active',
  '{"sleepAllowed":true,"sleepAware":true,"healthMonitoringMode":"on_demand"}'::jsonb
);

insert into foundation.defence_on_demand_revalidation_requests(
  request_id,target_id,requested_by,requested_at,expires_at,
  reason_code,scope_snapshot,evidence_fingerprint,request,request_sha256
) values (
  '80000001-0000-4000-8000-000000000001',
  'railway:test-control-overlay',
  'human:test-owner',
  now()-interval '1 minute',
  now()+interval '29 minutes',
  'on-demand-source-ahead',
  '{"test":true}'::jsonb,
  repeat('a',64),
  '{"test":true}'::jsonb,
  repeat('b',64)
);

do $pending$
declare
  base jsonb;
  v jsonb;
begin
  base := jsonb_build_object(
    'defenceOperationalAttention','shine-defence/operational-attention-v1',
    'schemaVersion','1.1.0',
    'attentionState','attention_required',
    'rawEstateState','warning',
    'rawEstateStateOverridden',false,
    'rawHealthEvidencePreserved',true,
    'counts','{}'::jsonb,
    'estateItems','[]'::jsonb,
    'targetItems',jsonb_build_array(
      jsonb_build_object(
        'scope','target',
        'targetId','railway:test-control-overlay',
        'causeClass','on_demand_revalidation_required',
        'attentionClass','target_investigation',
        'nextAction','wake_and_revalidate_on_demand_target'
      )
    ),
    'queueItems','[]'::jsonb
  );

  select foundation.apply_defence_on_demand_revalidation_control_v1(
    base,now()
  ) into v;

  if v->>'schemaVersion'<>'1.2.0'
     or v#>>'{revalidationControl,approvalRequired}'<>'true'
     or not exists (
       select 1
       from jsonb_array_elements(v->'targetItems') x
       where x->>'targetId'='railway:test-control-overlay'
         and x->>'attentionClass'='human_authorisation'
         and x->>'nextAction'='approve_on_demand_revalidation_request'
         and x#>>'{revalidationControl,state}'='pending_approval'
     )
     or (v#>>'{counts,onDemandRevalidationPendingApproval}')::integer<>1 then
    raise exception 'Pending approval overlay invalid: %',v;
  end if;
end;
$pending$;

do $live_contract$
declare
  v jsonb;
begin
  select foundation.get_defence_operational_attention_revalidation_aware_v1(
    now(),2700,3,0.5
  ) into v;

  if v->>'defenceOperationalAttention'<>
       'shine-defence/operational-attention-v1'
     or v->>'schemaVersion'<>'1.2.0'
     or v#>>'{revalidationControl,rawEstateStateOverridden}'<>'false'
     or v#>>'{revalidationControl,externalMutationAutomatic}'<>'false' then
    raise exception 'Live revalidation-aware attention contract invalid: %',v;
  end if;
end;
$live_contract$;

do $security$
begin
  if has_function_privilege(
       'anon',
       'foundation.get_defence_operational_attention_revalidation_aware_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_operational_attention_revalidation_aware_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_operational_attention_revalidation_aware_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     ) then
    raise exception 'Revalidation-aware attention privilege boundary invalid';
  end if;
end;
$security$;

rollback;
