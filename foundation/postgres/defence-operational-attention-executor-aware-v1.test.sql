begin;

insert into foundation.defence_estate_targets(
  target_id,display_name,provider,provider_project_ref,environment_ref,service_ref,
  target_role,required_for_estate,allowed_runtime_states,lifecycle,metadata
) values (
  'railway:test-executor-attention','Executor Attention Test','railway',
  '91111111-1111-4111-8111-111111111111',
  '92222222-2222-4222-8222-222222222222',
  '93333333-3333-4333-8333-333333333333',
  'primary_service',true,array['active','sleeping']::text[],'active',
  '{"sleepAllowed":true,"sleepAware":true,"healthMonitoringMode":"on_demand"}'::jsonb
);

insert into foundation.defence_on_demand_executor_profiles(
  target_id,direct_railway_enabled,native_git_enabled,
  native_git_repository,native_git_branch,native_git_trigger_path_prefix,
  native_git_proof_commit_sha,native_git_proof_deployment_id,
  native_git_proven_at,effective_at,evidence_ref,metadata
) values (
  'railway:test-executor-attention',false,false,
  null,null,null,null,null,null,
  now()-interval '1 minute',
  'test:executor-attention:blocked',
  '{"test":true}'::jsonb
);

do $overlay$
declare
  base jsonb;
  v jsonb;
begin
  base := jsonb_build_object(
    'defenceOperationalAttention','shine-defence/operational-attention-v1',
    'schemaVersion','1.2.0',
    'attentionState','attention_required',
    'rawEstateState','warning',
    'rawEstateStateOverridden',false,
    'rawHealthEvidencePreserved',true,
    'counts','{}'::jsonb,
    'estateItems','[]'::jsonb,
    'targetItems',jsonb_build_array(
      jsonb_build_object(
        'scope','target',
        'targetId','railway:test-executor-attention',
        'causeClass','on_demand_revalidation_required',
        'attentionClass','human_authorisation',
        'nextAction','request_on_demand_revalidation'
      )
    ),
    'queueItems','[]'::jsonb
  );

  select foundation.apply_defence_on_demand_executor_selection_v1(
    base,now()
  ) into v;

  if v->>'schemaVersion'<>'1.3.0'
     or v#>>'{executorSelection,contract}'<>
        'shine-defence/on-demand-executor-selection-v1'
     or not exists (
       select 1
       from jsonb_array_elements(v->'targetItems') x
       where x->>'targetId'='railway:test-executor-attention'
         and x->>'attentionClass'='executor_unavailable'
         and x->>'nextAction'='repair_on_demand_executor_readiness'
         and x#>>'{executorSelection,state}'='blocked'
     )
     or (v#>>'{counts,onDemandExecutorBlockedTargets}')::integer<>1 then
    raise exception 'Executor-aware attention transformation invalid: %',v;
  end if;
end;
$overlay$;

do $security$
begin
  if has_function_privilege(
       'anon',
       'foundation.apply_defence_on_demand_executor_selection_v1(jsonb,timestamp with time zone)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_defence_operational_attention_executor_aware_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_defence_operational_attention_executor_aware_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_defence_operational_attention_executor_aware_v1(timestamp with time zone,integer,integer,numeric)',
       'EXECUTE'
     ) then
    raise exception 'Executor-aware attention privilege boundary invalid';
  end if;
end;
$security$;

rollback;
