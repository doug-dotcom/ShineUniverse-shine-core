-- Foundation Layer 56: cause-aware readiness response routing and runtime-health investigation proposals.
-- Fixes the Layer-45 generic proposal route so runtime-only incidents do not suggest
-- dependency remediation, and creates a bounded non-executing investigation packet
-- for the Foundation Gateway's own runtime health.

insert into foundation.readiness_incident_response_actions(
  action_key,action_class,description
) values (
  'propose-runtime-health-investigation',
  'proposal',
  'Prepare a bounded runtime-health investigation proposal without changing health policy, runtime deployment or canonical release truth.'
)
on conflict(action_key) do update
set description=excluded.description,
    lifecycle='active';


create or replace function foundation.evaluate_readiness_incident_response_v1(
 p_action_key text,p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer56_eval$
declare
 a foundation.readiness_incident_response_actions%rowtype;
 s jsonb;
 r jsonb;
 state text;
 decision text;
 control text;
 reason text;
 dependency_state text;
 health_state text;
 dependency_scope_count integer;
 runtime_cause boolean;
 dependency_cause boolean;
begin
 select * into a
 from foundation.readiness_incident_response_actions
 where action_key=p_action_key
   and lifecycle='active';

 s:=foundation.get_foundation_readiness_incident_summary_v1(p_environment);
 r:=foundation.evaluate_foundation_readiness_v1(p_environment,now());
 state:=coalesce(s->>'state','normal');

 dependency_state:=coalesce(r#>>'{checks,dependencyRollup,state}','unknown');
 health_state:=coalesce(r#>>'{checks,health,state}','unknown');

 dependency_scope_count:=
   jsonb_array_length(coalesce(r#>'{checks,dependencyRollup,degradedScopes}','[]'::jsonb))
   + jsonb_array_length(coalesce(r#>'{checks,dependencyRollup,guardedScopes}','[]'::jsonb))
   + jsonb_array_length(coalesce(r#>'{checks,dependencyRollup,blockedScopes}','[]'::jsonb));

 runtime_cause:=
   health_state in ('unhealthy','degraded','unknown')
   and (
     coalesce(r->'reasonCodes','[]'::jsonb) ? 'runtime-unhealthy'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'runtime-degraded'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'runtime-health-unknown'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'health-runtime-version-mismatch'
   );

 dependency_cause:=
   dependency_state in ('blocked','guarded','degraded','unknown')
   and (
     dependency_scope_count>0
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-blocked'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-guarded'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-degraded'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-unknown'
   );

 if a.action_key is null then
  return jsonb_build_object(
    'decision','deny',
    'requiredControl','prohibited',
    'reasonCode','readiness-response-action-not-registered'
  );
 end if;

 if a.action_class='observe' then
   decision:='admit';
   control:='read-only';
   reason:='readiness-response-observe';
 elsif a.action_class='evidence' then
   decision:='admit';
   control:='evidence-only';
   reason:='readiness-response-evidence';
 elsif state='watching' then
   decision:='not-applicable';
   control:='none';
   reason:='readiness-watch-not-persistent';
 elsif state='incident' and a.action_class='containment' then
   decision:='admit';
   control:='existing-safe-mode';
   reason:='persistent-readiness-incident-containment';
 elsif state='incident'
   and a.action_key='propose-dependency-remediation'
   and dependency_cause then
   decision:='admit';
   control:='operator-proposal';
   reason:='persistent-dependency-readiness-incident-proposal';
 elsif state='incident'
   and a.action_key='propose-dependency-remediation'
   and not dependency_cause then
   decision:='not-applicable';
   control:='none';
   reason:='readiness-incident-not-dependency-caused';
 elsif state='incident'
   and a.action_key='propose-runtime-health-investigation'
   and runtime_cause then
   decision:='admit';
   control:='operator-investigation-proposal';
   reason:='persistent-runtime-health-incident-investigation';
 elsif state='incident'
   and a.action_key='propose-runtime-health-investigation'
   and not runtime_cause then
   decision:='not-applicable';
   control:='none';
   reason:='readiness-incident-not-runtime-health-caused';
 elsif state='incident' and a.action_class='proposal' then
   decision:='not-applicable';
   control:='none';
   reason:='readiness-response-proposal-cause-not-matched';
 else
   decision:='not-applicable';
   control:='none';
   reason:='readiness-response-not-applicable';
 end if;

 return jsonb_build_object(
  'foundationReadinessIncidentResponseDecision',
    'shine-foundation/readiness-incident-response-decision-v1',
  'schemaVersion','1.0.0',
  'environment',p_environment,
  'incidentState',state,
  'actionKey',a.action_key,
  'actionClass',a.action_class,
  'decision',decision,
  'requiredControl',control,
  'reasonCode',reason,
  'runtimeCause',runtime_cause,
  'dependencyCause',dependency_cause,
  'healthState',health_state,
  'dependencyImpactState',dependency_state,
  'dependencyScopeCount',dependency_scope_count,
  'authorityExpansion',false,
  'mutatesAuthoritativeTruth',false,
  'degradedScopes',coalesce(r#>'{checks,dependencyRollup,degradedScopes}','[]'::jsonb),
  'guardedScopes',coalesce(r#>'{checks,dependencyRollup,guardedScopes}','[]'::jsonb),
  'blockedScopes',coalesce(r#>'{checks,dependencyRollup,blockedScopes}','[]'::jsonb),
  'privilegedOperationsMode',r->>'privilegedOperationsMode',
  'workerOperationsMode',r->>'workerOperationsMode',
  'incidentSummary',s
 );
end;
$layer56_eval$;

revoke all on function foundation.evaluate_readiness_incident_response_v1(text,text)
 from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.evaluate_readiness_incident_response_v1(text,text)
 to foundation_runtime,service_role;


create or replace function foundation.get_readiness_incident_containment_plan_v1(
  p_environment text default 'production'
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer56_plan$
declare
 s jsonb;
 r jsonb;
 state text;
 dependency_state text;
 health_state text;
 dependency_scope_count integer;
 runtime_cause boolean;
 dependency_cause boolean;
begin
 s:=foundation.get_foundation_readiness_incident_summary_v1(p_environment);
 r:=foundation.evaluate_foundation_readiness_v1(p_environment,now());
 state:=coalesce(s->>'state','normal');

 dependency_state:=coalesce(r#>>'{checks,dependencyRollup,state}','unknown');
 health_state:=coalesce(r#>>'{checks,health,state}','unknown');

 dependency_scope_count:=
   jsonb_array_length(coalesce(r#>'{checks,dependencyRollup,degradedScopes}','[]'::jsonb))
   + jsonb_array_length(coalesce(r#>'{checks,dependencyRollup,guardedScopes}','[]'::jsonb))
   + jsonb_array_length(coalesce(r#>'{checks,dependencyRollup,blockedScopes}','[]'::jsonb));

 runtime_cause:=
   health_state in ('unhealthy','degraded','unknown')
   and (
     coalesce(r->'reasonCodes','[]'::jsonb) ? 'runtime-unhealthy'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'runtime-degraded'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'runtime-health-unknown'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'health-runtime-version-mismatch'
   );

 dependency_cause:=
   dependency_state in ('blocked','guarded','degraded','unknown')
   and (
     dependency_scope_count>0
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-blocked'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-guarded'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-degraded'
     or coalesce(r->'reasonCodes','[]'::jsonb) ? 'dependency-unknown'
   );

 return jsonb_build_object(
  'foundationReadinessContainmentPlan',
    'shine-foundation/readiness-containment-plan-v1',
  'schemaVersion','1.0.0',
  'environment',p_environment,
  'incidentState',state,
  'containmentActive',state='incident',
  'runtimeCause',runtime_cause,
  'dependencyCause',dependency_cause,
  'healthState',health_state,
  'dependencyImpactState',dependency_state,
  'dependencyScopeCount',dependency_scope_count,
  'degradedScopes',coalesce(r#>'{checks,dependencyRollup,degradedScopes}','[]'::jsonb),
  'guardedScopes',coalesce(r#>'{checks,dependencyRollup,guardedScopes}','[]'::jsonb),
  'blockedScopes',coalesce(r#>'{checks,dependencyRollup,blockedScopes}','[]'::jsonb),
  'privilegedOperationsMode',r->>'privilegedOperationsMode',
  'workerOperationsMode',r->>'workerOperationsMode',
  'canonicalTruthMutationAllowed',false,
  'releaseRebindAllowedByThisPolicy',false,
  'automaticDependencyRepair',false,
  'automaticRuntimeRepair',false,
  'recommendedAction',case
    when state='watching' then 'collect-fresh-evidence'
    when state='incident' and runtime_cause and dependency_cause
      then 'maintain-safe-mode-and-propose-runtime-and-dependency-investigation'
    when state='incident' and runtime_cause
      then 'maintain-safe-mode-and-propose-runtime-health-investigation'
    when state='incident' and dependency_cause
      then 'contain-existing-scopes-and-propose-dependency-remediation'
    when state='incident'
      then 'inspect-incident-evidence'
    else 'none'
  end
 );
end;
$layer56_plan$;

revoke all on function foundation.get_readiness_incident_containment_plan_v1(text)
 from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_incident_containment_plan_v1(text)
 to foundation_runtime,service_role;


create table foundation.readiness_runtime_health_investigation_proposals(
 proposal_sequence bigint generated always as identity primary key,
 proposal_id uuid not null unique default gen_random_uuid(),
 environment text not null,
 service_id text not null references foundation.service_registry(service_id),
 owner_component text not null,
 readiness_incident_event_id uuid not null
   references foundation.foundation_readiness_incident_events(event_id),
 condition_fingerprint text not null
   check(condition_fingerprint ~ '^[a-f0-9]{32}$'),
 severity text not null,
 health_state text not null
   check(health_state in ('unhealthy','degraded','unknown')),
 health_reason_codes jsonb not null check(jsonb_typeof(health_reason_codes)='array'),
 health_evidence_ref text,
 runtime_version text,
 proposal jsonb not null check(jsonb_typeof(proposal)='object'),
 proposal_sha256 text not null check(proposal_sha256 ~ '^[a-f0-9]{64}$'),
 status text not null default 'proposed' check(status='proposed'),
 created_at timestamptz not null default now(),
 unique(readiness_incident_event_id,condition_fingerprint)
);

alter table foundation.readiness_runtime_health_investigation_proposals
 enable row level security;

create policy foundation_runtime_readiness_runtime_health_proposals_select
on foundation.readiness_runtime_health_investigation_proposals
for select to foundation_runtime using(true);

revoke all on foundation.readiness_runtime_health_investigation_proposals
 from public,anon,authenticated,foundation_gateway,service_role,shine_defence_runtime;
grant select on foundation.readiness_runtime_health_investigation_proposals
 to foundation_runtime,service_role;

create index readiness_runtime_health_proposals_incident_idx
 on foundation.readiness_runtime_health_investigation_proposals(readiness_incident_event_id);

create trigger readiness_runtime_health_investigation_proposals_append_only
before update or delete on foundation.readiness_runtime_health_investigation_proposals
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.propose_readiness_runtime_health_investigation_v1(
 p_environment text default 'production',
 p_created_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $layer56_propose$
declare
 i foundation.foundation_readiness_incident_events%rowtype;
 svc foundation.service_registry%rowtype;
 existing foundation.readiness_runtime_health_investigation_proposals%rowtype;
 response_policy jsonb;
 health jsonb;
 deployment jsonb;
 cfp text;
 p jsonb;
 h text;
 pid uuid;
 health_state text;
 health_ref text;
 runtime_version text;
begin
 if p_created_at<now()-interval '5 minutes'
    or p_created_at>now()+interval '5 minutes' then
   raise exception 'runtime-health-investigation-created-at-invalid';
 end if;

 response_policy:=foundation.evaluate_readiness_incident_response_v1(
   'propose-runtime-health-investigation',p_environment
 );

 if response_policy->>'decision'<>'admit' then
   return jsonb_build_object(
     'foundationReadinessRuntimeHealthInvestigationProposalResponse',
       'shine-foundation/readiness-runtime-health-investigation-proposal-response-v1',
     'schemaVersion','1.0.0',
     'proposed',false,
     'status','not-applicable',
     'reasonCode',response_policy->>'reasonCode',
     'responseDecision',response_policy->>'decision',
     'executionAuthorityGranted',false,
     'approvalGranted',false,
     'executesRemediation',false
   );
 end if;

 select * into i
 from foundation.current_foundation_readiness_incident_state
 where incident_key=p_environment||':readiness';

 if i.event_id is null or i.event_type not in('opened','changed') then
   return jsonb_build_object(
     'foundationReadinessRuntimeHealthInvestigationProposalResponse',
       'shine-foundation/readiness-runtime-health-investigation-proposal-response-v1',
     'schemaVersion','1.0.0',
     'proposed',false,
     'status','not-applicable',
     'reasonCode','active-readiness-incident-required',
     'executionAuthorityGranted',false,
     'approvalGranted',false,
     'executesRemediation',false
   );
 end if;

 select * into svc
 from foundation.service_registry
 where service_id='foundation.gateway';

 if svc.service_id is null
    or svc.lifecycle<>'active'
    or svc.owner_component<>'shine-core' then
   raise exception 'runtime-health-investigation-gateway-ownership-invalid';
 end if;

 health:=foundation.get_service_health_v1('foundation.gateway',p_environment);
 health_state:=coalesce(health->>'healthState','unknown');

 if health_state not in ('unhealthy','degraded','unknown') then
   return jsonb_build_object(
     'foundationReadinessRuntimeHealthInvestigationProposalResponse',
       'shine-foundation/readiness-runtime-health-investigation-proposal-response-v1',
     'schemaVersion','1.0.0',
     'proposed',false,
     'status','not-applicable',
     'reasonCode','runtime-health-investigation-health-currently-healthy',
     'healthState',health_state,
     'executionAuthorityGranted',false,
     'approvalGranted',false,
     'executesRemediation',false
   );
 end if;

 deployment:=foundation.get_service_deployment_truth_v1(
   'foundation.gateway',p_environment
 );

 cfp:=coalesce(
   i.condition_fingerprint,
   md5(jsonb_build_object(
     'readinessState',i.readiness_state,
     'reasonCodes',i.reason_codes,
     'degradedScopes',i.degraded_scopes,
     'guardedScopes',i.guarded_scopes,
     'blockedScopes',i.blocked_scopes,
     'privilegedOperationsMode',i.snapshot#>>'{current,privilegedOperationsMode}',
     'workerOperationsMode',i.snapshot#>>'{current,workerOperationsMode}'
   )::text)
 );

 select * into existing
 from foundation.readiness_runtime_health_investigation_proposals
 where readiness_incident_event_id=i.event_id
   and condition_fingerprint=cfp
 order by proposal_sequence desc
 limit 1;

 if existing.proposal_id is not null then
   return jsonb_build_object(
     'foundationReadinessRuntimeHealthInvestigationProposalResponse',
       'shine-foundation/readiness-runtime-health-investigation-proposal-response-v1',
     'schemaVersion','1.0.0',
     'proposed',true,
     'status','existing',
     'proposalId',existing.proposal_id,
     'proposalSha256',existing.proposal_sha256,
     'ownerComponent',existing.owner_component,
     'healthState',existing.health_state,
     'executionAuthorityGranted',false,
     'approvalGranted',false,
     'executesRemediation',false,
     'proposal',existing.proposal
   );
 end if;

 health_ref:=health#>>'{metrics,evidenceRef}';
 runtime_version:=health#>>'{metrics,runtimeVersion}';

 p:=jsonb_build_object(
   'readinessRuntimeHealthInvestigationProposal',
     'shine-foundation/readiness-runtime-health-investigation-proposal-v1',
   'schemaVersion','1.0.0',
   'environment',p_environment,
   'incidentEventId',i.event_id,
   'conditionFingerprint',cfp,
   'readinessState',i.readiness_state,
   'severity',i.severity,
   'serviceId',svc.service_id,
   'serviceKind',svc.service_kind,
   'ownerComponent',svc.owner_component,
   'runtimeVersion',runtime_version,
   'health',health,
   'deploymentTruth',deployment,
   'investigationClass','runtime-health',
   'requestedOutcome','identify-runtime-health-cause-and-return-fresh-evidence',
   'requestedWork',jsonb_build_array(
     'inspect-health-probe-latency-distribution',
     'inspect-foundation-gateway-runtime-logs',
     'compare-health-endpoint-execution-path',
     'inspect-recent-runtime-or-platform-changes',
     'collect-fresh-health-window',
     'return-investigation-evidence'
   ),
   'prohibitedWork',jsonb_build_array(
     'relax-health-thresholds-to-clear-readiness',
     'mutate-or-delete-health-evidence',
     'restart-runtime-without-separate-admission',
     'redeploy-runtime-without-separate-admission',
     'rebind-foundation-release',
     'bypass-safe-mode',
     'automatic-unapproved-repair'
   ),
   'completionCriteria',jsonb_build_array(
     'fresh-runtime-health-evidence-collected',
     'latency-cause-identified-or-explicitly-inconclusive',
     'health-policy-left-unchanged-unless-separately-approved',
     'runtime-mutation-left-unperformed-unless-separately-admitted',
     'semantic-readiness-retest-remains-independent'
   ),
   'readinessChanged',false,
   'incidentClosurePerformed',false,
   'approvalGranted',false,
   'executionAuthorityGranted',false,
   'executesRemediation',false,
   'createdAt',p_created_at
 );

 h:=encode(
   extensions.digest(convert_to(p::text,'UTF8'),'sha256'),
   'hex'
 );

 insert into foundation.readiness_runtime_health_investigation_proposals(
   environment,service_id,owner_component,readiness_incident_event_id,
   condition_fingerprint,severity,health_state,health_reason_codes,
   health_evidence_ref,runtime_version,proposal,proposal_sha256,created_at
 )
 values(
   p_environment,svc.service_id,svc.owner_component,i.event_id,
   cfp,i.severity,health_state,coalesce(health->'reasonCodes','[]'::jsonb),
   health_ref,runtime_version,p,h,p_created_at
 )
 returning proposal_id into pid;

 return jsonb_build_object(
   'foundationReadinessRuntimeHealthInvestigationProposalResponse',
     'shine-foundation/readiness-runtime-health-investigation-proposal-response-v1',
   'schemaVersion','1.0.0',
   'proposed',true,
   'status','generated',
   'proposalId',pid,
   'proposalSha256',h,
   'ownerComponent',svc.owner_component,
   'healthState',health_state,
   'executionAuthorityGranted',false,
   'approvalGranted',false,
   'executesRemediation',false,
   'proposal',p
 );
end;
$layer56_propose$;

revoke all on function foundation.propose_readiness_runtime_health_investigation_v1(
 text,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.propose_readiness_runtime_health_investigation_v1(
 text,timestamptz
) to service_role;


create or replace function foundation.get_readiness_runtime_health_investigation_proposal_status_v1(
 p_proposal_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $layer56_status$
declare
 p foundation.readiness_runtime_health_investigation_proposals%rowtype;
 i foundation.foundation_readiness_incident_events%rowtype;
 current_cfp text;
 expected_hash text;
 state text;
begin
 select * into p
 from foundation.readiness_runtime_health_investigation_proposals
 where proposal_id=p_proposal_id;

 if p.proposal_id is null then
   return jsonb_build_object(
     'state','not-found',
     'usable',false
   );
 end if;

 expected_hash:=encode(
   extensions.digest(convert_to(p.proposal::text,'UTF8'),'sha256'),
   'hex'
 );

 select * into i
 from foundation.current_foundation_readiness_incident_state
 where incident_key=p.environment||':readiness';

 current_cfp:=case
   when i.event_id is null then null
   else coalesce(
     i.condition_fingerprint,
     md5(jsonb_build_object(
       'readinessState',i.readiness_state,
       'reasonCodes',i.reason_codes,
       'degradedScopes',i.degraded_scopes,
       'guardedScopes',i.guarded_scopes,
       'blockedScopes',i.blocked_scopes,
       'privilegedOperationsMode',i.snapshot#>>'{current,privilegedOperationsMode}',
       'workerOperationsMode',i.snapshot#>>'{current,workerOperationsMode}'
     )::text)
   )
 end;

 state:=case
   when expected_hash is distinct from p.proposal_sha256 then 'invalid'
   when i.event_type not in('opened','changed') then 'stale'
   when i.event_id is distinct from p.readiness_incident_event_id then 'stale'
   when current_cfp is distinct from p.condition_fingerprint then 'stale'
   else 'current'
 end;

 return jsonb_build_object(
   'foundationReadinessRuntimeHealthInvestigationProposalStatus',
     'shine-foundation/readiness-runtime-health-investigation-proposal-status-v1',
   'schemaVersion','1.0.0',
   'state',state,
   'usable',state='current',
   'proposalId',p.proposal_id,
   'incidentEventId',p.readiness_incident_event_id,
   'conditionFingerprint',p.condition_fingerprint,
   'serviceId',p.service_id,
   'ownerComponent',p.owner_component,
   'healthState',p.health_state,
   'healthEvidenceRef',p.health_evidence_ref,
   'runtimeVersion',p.runtime_version,
   'proposalSha256',p.proposal_sha256,
   'integrityVerified',expected_hash=p.proposal_sha256,
   'readinessChanged',false,
   'incidentClosurePerformed',false,
   'approvalGranted',false,
   'executionAuthorityGranted',false,
   'executesRemediation',false
 );
end;
$layer56_status$;

revoke all on function foundation.get_readiness_runtime_health_investigation_proposal_status_v1(uuid)
 from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_readiness_runtime_health_investigation_proposal_status_v1(uuid)
 to foundation_runtime,service_role;
