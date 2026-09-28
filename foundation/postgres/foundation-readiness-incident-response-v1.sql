-- Foundation Layer 45: readiness-incident response policy and containment plan.
-- Evaluates only. Does not mutate canonical truth or route policy.

create table foundation.readiness_incident_response_actions(
 action_key text primary key,
 action_class text not null check(action_class in('observe','evidence','containment','proposal')),
 mutates_authoritative_truth boolean not null default false check(not mutates_authoritative_truth),
 description text not null,
 lifecycle text not null default 'active' check(lifecycle in('active','disabled','retired')),
 registered_at timestamptz not null default now()
);
alter table foundation.readiness_incident_response_actions enable row level security;
create policy foundation_runtime_readiness_response_actions_select on foundation.readiness_incident_response_actions for select to foundation_runtime using(true);
revoke all on foundation.readiness_incident_response_actions from public,anon,authenticated,foundation_gateway;
grant select on foundation.readiness_incident_response_actions to foundation_runtime,service_role;

insert into foundation.readiness_incident_response_actions(action_key,action_class,description) values
('inspect-readiness-evidence','observe','Inspect current readiness incident and dependency-scope evidence.'),
('collect-fresh-readiness-evidence','evidence','Collect fresh readiness, Defence and dependency evidence.'),
('contain-degraded-scopes','containment','Apply existing safe-mode semantics to scopes already marked degraded/guarded/blocked.'),
('propose-dependency-remediation','proposal','Prepare a dependency remediation proposal without changing canonical release truth.')
on conflict(action_key) do nothing;

create or replace function foundation.evaluate_readiness_incident_response_v1(
 p_action_key text,p_environment text default 'production'
)
returns jsonb language plpgsql stable security definer set search_path='' as $eval$
declare
 a foundation.readiness_incident_response_actions%rowtype;
 s jsonb; r jsonb; state text; decision text; control text; reason text;
begin
 select * into a from foundation.readiness_incident_response_actions where action_key=p_action_key and lifecycle='active';
 s:=foundation.get_foundation_readiness_incident_summary_v1(p_environment);
 r:=foundation.evaluate_foundation_readiness_v1(p_environment,now());
 state:=coalesce(s->>'state','normal');

 if a.action_key is null then
  return jsonb_build_object('decision','deny','requiredControl','prohibited','reasonCode','readiness-response-action-not-registered');
 end if;

 if a.action_class='observe' then decision:='admit';control:='read-only';reason:='readiness-response-observe';
 elsif a.action_class='evidence' then decision:='admit';control:='evidence-only';reason:='readiness-response-evidence';
 elsif state='watching' then decision:='not-applicable';control:='none';reason:='readiness-watch-not-persistent';
 elsif state='incident' and a.action_class='containment' then decision:='admit';control:='existing-safe-mode';reason:='persistent-readiness-incident-containment';
 elsif state='incident' and a.action_class='proposal' then decision:='admit';control:='operator-proposal';reason:='persistent-readiness-incident-proposal';
 else decision:='not-applicable';control:='none';reason:='readiness-response-not-applicable';
 end if;

 return jsonb_build_object(
  'foundationReadinessIncidentResponseDecision','shine-foundation/readiness-incident-response-decision-v1',
  'schemaVersion','1.0.0','environment',p_environment,'incidentState',state,
  'actionKey',a.action_key,'actionClass',a.action_class,'decision',decision,
  'requiredControl',control,'reasonCode',reason,'authorityExpansion',false,
  'mutatesAuthoritativeTruth',false,
  'degradedScopes',coalesce(r#>'{checks,dependencyRollup,degradedScopes}','[]'::jsonb),
  'guardedScopes',coalesce(r#>'{checks,dependencyRollup,guardedScopes}','[]'::jsonb),
  'blockedScopes',coalesce(r#>'{checks,dependencyRollup,blockedScopes}','[]'::jsonb),
  'privilegedOperationsMode',r->>'privilegedOperationsMode',
  'workerOperationsMode',r->>'workerOperationsMode',
  'incidentSummary',s
 );
end;
$eval$;

revoke all on function foundation.evaluate_readiness_incident_response_v1(text,text) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.evaluate_readiness_incident_response_v1(text,text) to foundation_runtime,service_role;

create or replace function foundation.get_readiness_incident_containment_plan_v1(p_environment text default 'production')
returns jsonb language plpgsql stable security definer set search_path='' as $plan$
declare
 s jsonb;r jsonb;state text;
begin
 s:=foundation.get_foundation_readiness_incident_summary_v1(p_environment);
 r:=foundation.evaluate_foundation_readiness_v1(p_environment,now());
 state:=coalesce(s->>'state','normal');
 return jsonb_build_object(
  'foundationReadinessContainmentPlan','shine-foundation/readiness-containment-plan-v1',
  'schemaVersion','1.0.0','environment',p_environment,'incidentState',state,
  'containmentActive',state='incident',
  'degradedScopes',coalesce(r#>'{checks,dependencyRollup,degradedScopes}','[]'::jsonb),
  'guardedScopes',coalesce(r#>'{checks,dependencyRollup,guardedScopes}','[]'::jsonb),
  'blockedScopes',coalesce(r#>'{checks,dependencyRollup,blockedScopes}','[]'::jsonb),
  'privilegedOperationsMode',r->>'privilegedOperationsMode',
  'workerOperationsMode',r->>'workerOperationsMode',
  'canonicalTruthMutationAllowed',false,
  'releaseRebindAllowedByThisPolicy',false,
  'automaticDependencyRepair',false,
  'recommendedAction',case when state='watching' then 'collect-fresh-evidence'
                           when state='incident' then 'contain-existing-scopes-and-propose-remediation'
                           else 'none' end
 );
end;
$plan$;

revoke all on function foundation.get_readiness_incident_containment_plan_v1(text) from public,anon,authenticated,foundation_gateway;
grant execute on function foundation.get_readiness_incident_containment_plan_v1(text) to foundation_runtime,service_role;
