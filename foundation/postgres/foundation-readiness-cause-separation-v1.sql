-- Foundation Layer 51: separate own-runtime failure from dependency impact.
-- Prevents Gateway health failure from being mislabelled as dependency-blocked,
-- and makes dependency remediation explicitly not-applicable when no dependency
-- scopes are affected.

create or replace function foundation.evaluate_foundation_readiness_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, foundation
as $layer30$
declare
  v_deployment jsonb;
  v_health jsonb;
  v_graph jsonb;
  v_dependency jsonb;
  v_routes jsonb;
  v_policy jsonb;
  v_audit jsonb;
  v_defence jsonb;

  v_required_core_count integer := 0;
  v_inactive_required_core_count integer := 0;
  v_service_registry_state text := 'unknown';

  v_expected_version text;
  v_health_runtime_version text;
  v_current_runtime_complete_traces integer := 0;
  v_current_runtime_broken_traces integer := 0;

  v_deployment_state text;
  v_health_state text;
  v_graph_state text;
  v_dependency_state text;
  v_dependency_impact_state text := 'operational';
  v_route_state text;
  v_policy_state text;
  v_audit_state text;
  v_defence_state text;

  v_guarded_scopes text[] := '{}'::text[];
  v_degraded_scopes text[] := '{}'::text[];
  v_blocked_scopes text[] := '{}'::text[];

  v_reasons text[] := '{}'::text[];
  v_readiness text := 'ready';
  v_safe_mode text := 'normal';
  v_privileged_mode text := 'normal';
  v_worker_mode text := 'normal';

  v_fingerprint_payload jsonb;
  v_fingerprint text;
begin
  select
    count(*) filter (where required_for_core),
    count(*) filter (where required_for_core and lifecycle<>'active')
  into v_required_core_count,v_inactive_required_core_count
  from foundation.service_registry;

  v_service_registry_state := case
    when v_required_core_count=0 then 'fail'
    when v_inactive_required_core_count>0 then 'fail'
    else 'pass'
  end;

  v_deployment := foundation.get_service_deployment_truth_v1(
    'foundation.gateway',p_environment
  );
  v_health := foundation.get_service_health_v1(
    'foundation.gateway',p_environment
  );
  v_graph := foundation.get_dependency_graph_health_v1(p_environment);
  v_dependency := foundation.get_foundation_dependency_rollup_v1(
    p_environment,p_as_of
  );
  v_routes := foundation.get_gateway_operation_registry_health_v1(p_environment);
  v_policy := foundation.get_gateway_operation_policy_coverage_v1(p_environment);
  v_audit := foundation.get_gateway_operation_audit_health_v1(p_environment,300);
  v_defence := foundation.get_service_native_state_v1(
    'foundation.defence',p_environment,p_as_of
  );

  v_deployment_state := coalesce(v_deployment->>'truthState','unknown');
  v_health_state := coalesce(v_health->>'healthState','unknown');
  v_graph_state := coalesce(v_graph->>'state','fail');
  v_dependency_state := coalesce(v_dependency->>'effectiveState','unknown');
  v_route_state := coalesce(v_routes->>'state','fail');
  v_policy_state := coalesce(v_policy->>'state','fail');
  v_audit_state := coalesce(v_audit->>'state','unknown');
  v_defence_state := coalesce(v_defence->>'operationalState','unknown');

  v_expected_version := v_deployment#>>'{expected,version}';
  v_health_runtime_version := v_health#>>'{metrics,runtimeVersion}';

  select coalesce(array_agg(x order by x),'{}'::text[])
    into v_guarded_scopes
  from jsonb_array_elements_text(
    coalesce(
      (select s->'guardedScopes'
       from jsonb_array_elements(coalesce(v_dependency->'coreServices','[]'::jsonb)) s
       where s->>'serviceId'='foundation.gateway'
       limit 1),
      '[]'::jsonb
    )
  ) x;

  select coalesce(array_agg(x order by x),'{}'::text[])
    into v_degraded_scopes
  from jsonb_array_elements_text(
    coalesce(
      (select s->'degradedScopes'
       from jsonb_array_elements(coalesce(v_dependency->'coreServices','[]'::jsonb)) s
       where s->>'serviceId'='foundation.gateway'
       limit 1),
      '[]'::jsonb
    )
  ) x;

  select coalesce(array_agg(x order by x),'{}'::text[])
    into v_blocked_scopes
  from jsonb_array_elements_text(
    coalesce(
      (select s->'blockedScopes'
       from jsonb_array_elements(coalesce(v_dependency->'coreServices','[]'::jsonb)) s
       where s->>'serviceId'='foundation.gateway'
       limit 1),
      '[]'::jsonb
    )
  ) x;

  -- Layer 51 separates Gateway's own runtime state from dependency impact.
  -- get_service_dependency_rollup_v1 deliberately folds own health into effectiveState;
  -- readiness already evaluates Gateway health independently, so dependency reasons must
  -- be derived only from dependency-edge impacts.
  select case
    when cardinality(v_blocked_scopes)>0 then 'blocked'
    when cardinality(v_guarded_scopes)>0 then 'guarded'
    when exists (
      select 1
      from jsonb_array_elements(
        coalesce(
          (select s->'dependencies'
           from jsonb_array_elements(coalesce(v_dependency->'coreServices','[]'::jsonb)) s
           where s->>'serviceId'='foundation.gateway'
           limit 1),
          '[]'::jsonb
        )
      ) d
      where d->>'impact'='unknown'
    ) then 'unknown'
    when cardinality(v_degraded_scopes)>0 then 'degraded'
    else 'operational'
  end
  into v_dependency_impact_state;

  if v_expected_version is not null then
    select
      count(*) filter (
        where exists (
          select 1
          from foundation.gateway_operation_audit_events o
          where o.operation_audit_id=p.operation_audit_id
            and o.phase='outcome'
            and o.previous_event_hash=p.event_hash
        )
      ),
      count(*) filter (
        where exists (
          select 1
          from foundation.gateway_operation_audit_events o
          where o.operation_audit_id=p.operation_audit_id
            and o.phase='outcome'
            and o.previous_event_hash is distinct from p.event_hash
        )
      )
    into v_current_runtime_complete_traces,v_current_runtime_broken_traces
    from foundation.gateway_operation_audit_events p
    where p.environment=p_environment
      and p.runtime_version=v_expected_version
      and p.phase='policy'
      and p.occurred_at>=coalesce(
        (v_deployment#>>'{observed,observedAt}')::timestamptz,
        '-infinity'::timestamptz
      );
  end if;

  if v_service_registry_state<>'pass' then
    v_reasons := array_append(v_reasons,'service-registry-invalid');
  end if;

  if v_deployment_state='drift' then
    v_reasons := array_append(v_reasons,'deployment-drift');
  elsif v_deployment_state='unknown' then
    v_reasons := array_append(v_reasons,'deployment-unknown');
  end if;

  if v_health_state='unhealthy' then
    v_reasons := array_append(v_reasons,'runtime-unhealthy');
  elsif v_health_state='degraded' then
    v_reasons := array_append(v_reasons,'runtime-degraded');
  elsif v_health_state='unknown' then
    v_reasons := array_append(v_reasons,'runtime-health-unknown');
  end if;

  if v_expected_version is not null
     and v_health_runtime_version is distinct from v_expected_version then
    v_reasons := array_append(v_reasons,'health-runtime-version-mismatch');
  end if;

  if v_graph_state<>'pass' then
    v_reasons := array_append(v_reasons,'dependency-graph-invalid');
  end if;

  if v_dependency_impact_state='blocked' then
    v_reasons := array_append(v_reasons,'dependency-blocked');
  elsif v_dependency_impact_state='guarded' then
    v_reasons := array_append(v_reasons,'dependency-guarded');
  elsif v_dependency_impact_state='degraded' then
    v_reasons := array_append(v_reasons,'dependency-degraded');
  elsif v_dependency_impact_state='unknown' then
    v_reasons := array_append(v_reasons,'dependency-unknown');
  end if;

  if v_route_state<>'pass' then
    v_reasons := array_append(v_reasons,'gateway-route-registry-invalid');
  end if;

  if v_policy_state<>'pass' then
    v_reasons := array_append(v_reasons,'gateway-operation-policy-incomplete');
  end if;

  if v_audit_state='fail' then
    v_reasons := array_append(v_reasons,'operation-audit-integrity-failed');
  elsif v_audit_state='degraded' then
    v_reasons := array_append(v_reasons,'operation-audit-degraded');
  elsif v_audit_state='unknown' then
    v_reasons := array_append(v_reasons,'operation-audit-unknown');
  end if;

  if v_current_runtime_broken_traces>0 then
    v_reasons := array_append(v_reasons,'current-runtime-audit-chain-broken');
  elsif coalesce(v_current_runtime_complete_traces,0)=0 then
    v_reasons := array_append(v_reasons,'current-runtime-audit-proof-missing');
  end if;

  -- Hard failures take precedence.
  if v_service_registry_state<>'pass'
     or v_deployment_state='drift'
     or v_health_state='unhealthy'
     or v_graph_state<>'pass'
     or v_dependency_impact_state='blocked'
     or v_route_state<>'pass'
     or v_policy_state<>'pass'
     or v_audit_state='fail'
     or v_current_runtime_broken_traces>0 then
    v_readiness := 'not-ready';
    v_safe_mode := 'blocked';
    v_privileged_mode := 'blocked';
    v_worker_mode := 'blocked';

  -- Missing or version-mismatched evidence means Foundation cannot claim readiness.
  elsif v_deployment_state='unknown'
     or v_health_state='unknown'
     or v_dependency_impact_state='unknown'
     or v_audit_state='unknown'
     or (v_expected_version is not null and v_health_runtime_version is distinct from v_expected_version)
     or coalesce(v_current_runtime_complete_traces,0)=0 then
    v_readiness := 'unknown';
    v_safe_mode := 'unknown';
    v_privileged_mode := 'unknown';
    v_worker_mode := 'unknown';

  -- Guarded dependencies are safe because privileged scopes fail closed.
  elsif v_dependency_impact_state='guarded' then
    v_readiness := 'restricted';
    v_safe_mode := 'guarded';
    v_privileged_mode := 'guarded';
    v_worker_mode := 'normal';

  elsif v_health_state='degraded'
     or v_dependency_impact_state='degraded'
     or v_audit_state='degraded' then
    v_readiness := 'degraded';
    v_safe_mode := 'degraded';
    v_privileged_mode := 'degraded';
    v_worker_mode := 'degraded';

  else
    v_readiness := 'ready';
    v_safe_mode := 'normal';
    v_privileged_mode := 'normal';
    v_worker_mode := 'normal';
  end if;

  v_fingerprint_payload := jsonb_build_object(
    'readinessState',v_readiness,
    'safeMode',v_safe_mode,
    'serviceRegistryState',v_service_registry_state,
    'requiredCoreServices',v_required_core_count,
    'inactiveRequiredCoreServices',v_inactive_required_core_count,
    'deploymentState',v_deployment_state,
    'expectedVersion',v_expected_version,
    'deploymentSourceRef',v_deployment#>>'{expected,sourceRef}',
    'artifactSha256',v_deployment#>>'{expected,artifactSha256}',
    'healthState',v_health_state,
    'healthRuntimeVersion',v_health_runtime_version,
    'healthReasonCodes',coalesce(v_health->'reasonCodes','[]'::jsonb),
    'dependencyGraphState',v_graph_state,
    'dependencyServiceEffectiveState',v_dependency_state,
    'dependencyImpactState',v_dependency_impact_state,
    'guardedScopes',to_jsonb(v_guarded_scopes),
    'degradedScopes',to_jsonb(v_degraded_scopes),
    'blockedScopes',to_jsonb(v_blocked_scopes),
    'routeRegistryState',v_route_state,
    'routeCount',v_routes->>'routeCount',
    'policyCoverageState',v_policy_state,
    'privilegedOperationCount',v_policy->>'privilegedOperationCount',
    'coveredOperationCount',v_policy->>'coveredOperationCount',
    'auditState',v_audit_state,
    'auditOpenTraceCount',v_audit->>'openTraceCount',
    'auditBrokenChainCount',v_audit->>'brokenChainCount',
    'currentRuntimeAuditProof',v_current_runtime_complete_traces>0,
    'currentRuntimeAuditBroken',v_current_runtime_broken_traces>0,
    'defenceState',v_defence_state,
    'defenceEvidenceRef',v_defence->>'sourceEvidenceRef',
    'defenceObservedAt',v_defence#>>'{sourceState,observedAt}'
  );

  v_fingerprint := md5(v_fingerprint_payload::text);

  return jsonb_build_object(
    'foundationReadinessResponse','shine-foundation/control-plane-readiness-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'readinessState',v_readiness,
    'safeMode',v_safe_mode,
    'privilegedOperationsMode',v_privileged_mode,
    'workerOperationsMode',v_worker_mode,
    'reasonCodes',to_jsonb(v_reasons),
    'evidenceFingerprint',v_fingerprint,
    'recommendedAction',case v_readiness
      when 'ready' then 'normal-operations'
      when 'restricted' then 'keep-guarded-scopes-fail-closed'
      when 'degraded' then 'continue-with-monitoring-and-remediation'
      when 'not-ready' then 'block-privileged-operations-and-remediate'
      else 'gather-fresh-control-plane-evidence'
    end,
    'checks',jsonb_build_object(
      'serviceRegistry',jsonb_build_object(
        'state',v_service_registry_state,
        'requiredCoreServices',v_required_core_count,
        'inactiveRequiredCoreServices',v_inactive_required_core_count
      ),
      'deployment',jsonb_build_object(
        'state',v_deployment_state,
        'expectedVersion',v_expected_version,
        'observedVersion',v_deployment#>>'{observed,version}',
        'sourceRef',v_deployment#>>'{expected,sourceRef}',
        'artifactSha256',v_deployment#>>'{expected,artifactSha256}'
      ),
      'health',jsonb_build_object(
        'state',v_health_state,
        'runtimeVersion',v_health_runtime_version,
        'evidenceRef',v_health#>>'{metrics,evidenceRef}',
        'reasonCodes',coalesce(v_health->'reasonCodes','[]'::jsonb)
      ),
      'dependencyGraph',jsonb_build_object(
        'state',v_graph_state,
        'cycleCount',v_graph->>'cycleCount'
      ),
      'dependencyRollup',jsonb_build_object(
        'state',v_dependency_impact_state,
        'serviceEffectiveState',v_dependency_state,
        'guardedScopes',to_jsonb(v_guarded_scopes),
        'degradedScopes',to_jsonb(v_degraded_scopes),
        'blockedScopes',to_jsonb(v_blocked_scopes)
      ),
      'routeRegistry',jsonb_build_object(
        'state',v_route_state,
        'routeCount',v_routes->>'routeCount',
        'invalidContractCount',v_routes->>'invalidContractCount'
      ),
      'operationPolicyCoverage',jsonb_build_object(
        'state',v_policy_state,
        'privilegedOperationCount',v_policy->>'privilegedOperationCount',
        'coveredOperationCount',v_policy->>'coveredOperationCount',
        'missingPolicyCount',v_policy->>'missingPolicyCount',
        'missingAdmissionBindingCount',v_policy->>'missingAdmissionBindingCount',
        'missingDependencyScopeCount',v_policy->>'missingDependencyScopeCount'
      ),
      'operationAudit',jsonb_build_object(
        'state',v_audit_state,
        'openTraceCount',v_audit->>'openTraceCount',
        'brokenChainCount',v_audit->>'brokenChainCount',
        'currentRuntimeCompleteTraceCount',v_current_runtime_complete_traces,
        'currentRuntimeBrokenTraceCount',v_current_runtime_broken_traces
      ),
      'defence',jsonb_build_object(
        'state',v_defence_state,
        'evidenceRef',v_defence->>'sourceEvidenceRef',
        'observedAt',v_defence#>>'{sourceState,observedAt}',
        'validUntil',v_defence#>>'{sourceState,validUntil}'
      )
    )
  );
end;
$layer30$;

revoke all on function foundation.evaluate_foundation_readiness_v1(text,timestamptz)
  from public,anon,authenticated;
grant execute on function foundation.evaluate_foundation_readiness_v1(text,timestamptz)
  to foundation_runtime;

create or replace function foundation.propose_readiness_dependency_remediation_v1(
 p_environment text default 'production',p_created_at timestamptz default now()
)
returns jsonb language plpgsql security definer set search_path='' as $proposal$
declare
 i foundation.foundation_readiness_incident_events%rowtype;
 existing foundation.readiness_dependency_remediation_proposals%rowtype;
 cfp text;
 p jsonb;
 h text;
 pid uuid;
 scopes jsonb;
 scope_plan jsonb;
 response_policy jsonb;
begin
 response_policy:=foundation.evaluate_readiness_incident_response_v1(
   'propose-dependency-remediation',p_environment
 );

 if response_policy->>'decision'<>'admit' then
  return jsonb_build_object(
   'foundationReadinessDependencyRemediationProposalResponse',
     'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
   'schemaVersion','1.0.0','proposed',false,
   'reasonCode','readiness-remediation-proposal-not-admitted',
   'responseDecision',response_policy->>'decision',
   'executionAuthorityGranted',false,'approvalGranted',false
  );
 end if;

 select * into i
 from foundation.current_foundation_readiness_incident_state
 where incident_key=p_environment||':readiness';

 if i.event_id is null or i.event_type not in('opened','changed') then
  return jsonb_build_object(
   'foundationReadinessDependencyRemediationProposalResponse',
     'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
   'schemaVersion','1.0.0','proposed',false,
   'reasonCode','active-readiness-incident-required',
   'executionAuthorityGranted',false,'approvalGranted',false
  );
 end if;

 cfp:=coalesce(
   i.condition_fingerprint,
   md5(jsonb_build_object(
    'readinessState',i.readiness_state,'reasonCodes',i.reason_codes,
    'degradedScopes',i.degraded_scopes,'guardedScopes',i.guarded_scopes,
    'blockedScopes',i.blocked_scopes,
    'privilegedOperationsMode',i.snapshot#>>'{current,privilegedOperationsMode}',
    'workerOperationsMode',i.snapshot#>>'{current,workerOperationsMode}'
   )::text)
 );

 select * into existing
 from foundation.readiness_dependency_remediation_proposals
 where readiness_incident_event_id=i.event_id
   and condition_fingerprint=cfp
 order by proposal_sequence desc
 limit 1;

 if existing.proposal_id is not null then
  return jsonb_build_object(
   'foundationReadinessDependencyRemediationProposalResponse',
     'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
   'schemaVersion','1.0.0','proposed',true,'status','existing',
   'proposalId',existing.proposal_id,'proposalSha256',existing.proposal_sha256,
   'executionAuthorityGranted',false,'approvalGranted',false,
   'proposal',existing.proposal
  );
 end if;

 select coalesce(jsonb_agg(scope order by scope),'[]'::jsonb)
 into scopes
 from (
   select value as scope from jsonb_array_elements_text(coalesce(i.degraded_scopes,'[]'::jsonb)) t(value)
   union
   select value from jsonb_array_elements_text(coalesce(i.guarded_scopes,'[]'::jsonb)) t(value)
   union
   select value from jsonb_array_elements_text(coalesce(i.blocked_scopes,'[]'::jsonb)) t(value)
 ) x;

 select coalesce(
   jsonb_agg(
     jsonb_build_object(
       'scope',scope,
       'disposition',disposition,
       'work',jsonb_build_array(
         'collect-fresh-scope-evidence',
         'identify-degraded-upstream-dependency',
         'prepare-upstream-remediation',
         'rerun-foundation-readiness-verification'
       )
     )
     order by scope
   ),
   '[]'::jsonb
 )
 into scope_plan
 from (
   select scope,max(disposition) filter(where rank=max_rank) as disposition
   from (
     select scope,disposition,rank,max(rank) over(partition by scope) max_rank
     from (
       select value scope,'degraded'::text disposition,1 rank
       from jsonb_array_elements_text(coalesce(i.degraded_scopes,'[]'::jsonb)) t(value)
       union all
       select value,'guarded',2
       from jsonb_array_elements_text(coalesce(i.guarded_scopes,'[]'::jsonb)) t(value)
       union all
       select value,'blocked',3
       from jsonb_array_elements_text(coalesce(i.blocked_scopes,'[]'::jsonb)) t(value)
     ) r
   ) ranked
   group by scope,max_rank
 ) final;

 if jsonb_array_length(scopes)=0 then
  return jsonb_build_object(
   'foundationReadinessDependencyRemediationProposalResponse',
     'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
   'schemaVersion','1.0.0',
   'proposed',false,
   'status','not-applicable',
   'reasonCode','readiness-remediation-no-dependency-scopes',
   'incidentEventId',i.event_id,
   'conditionFingerprint',cfp,
   'executionAuthorityGranted',false,
   'approvalGranted',false
  );
 end if;

 p:=jsonb_build_object(
  'readinessDependencyRemediationProposal',
    'shine-foundation/readiness-dependency-remediation-proposal-v1',
  'schemaVersion','1.0.0','environment',p_environment,
  'incidentEventId',i.event_id,'conditionFingerprint',cfp,
  'readinessState',i.readiness_state,'severity',i.severity,
  'reasonCodes',i.reason_codes,'affectedScopes',scopes,'scopePlan',scope_plan,
  'requestedOutcome','restore-readiness-without-release-identity-mutation',
  'allowedWork',jsonb_build_array(
    'investigate-dependency-evidence',
    'repair-external-dependency-or-defence-posture',
    'collect-fresh-readiness-evidence'
  ),
  'prohibitedWork',jsonb_build_array(
    'mutate-foundation-canonical-truth',
    'rebind-foundation-release',
    'bypass-safe-mode',
    'automatic-unapproved-repair'
  ),
  'completionCriteria',jsonb_build_array(
    'fresh-readiness-evidence-collected',
    'affected-scope-condition-cleared-or-improved',
    'semantic-readiness-retest-run',
    'readiness-incident-recovered-or-materially-updated'
  ),
  'executionAuthorityGranted',false,'approvalGranted',false,
  'createdAt',p_created_at
 );

 h:=encode(extensions.digest(convert_to(p::text,'UTF8'),'sha256'),'hex');

 insert into foundation.readiness_dependency_remediation_proposals(
  environment,readiness_incident_event_id,condition_fingerprint,severity,
  reason_codes,affected_scopes,proposal,proposal_sha256,created_at
 ) values(
  p_environment,i.event_id,cfp,i.severity,i.reason_codes,
  scopes,p,h,p_created_at
 )
 returning proposal_id into pid;

 return jsonb_build_object(
  'foundationReadinessDependencyRemediationProposalResponse',
    'shine-foundation/readiness-dependency-remediation-proposal-response-v1',
  'schemaVersion','1.0.0','proposed',true,'status','generated',
  'proposalId',pid,'proposalSha256',h,
  'executionAuthorityGranted',false,'approvalGranted',false,'proposal',p
 );
end;
$proposal$;

revoke all on function foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)
 from public,anon,authenticated,foundation_runtime,foundation_gateway;
grant execute on function foundation.propose_readiness_dependency_remediation_v1(text,timestamptz)
 to service_role;
