begin;

-- Override summary/readiness to exercise watch vs persistent incident policy.
create or replace function foundation.get_foundation_readiness_incident_summary_v1(p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $watch$
 select jsonb_build_object('state','watching','activeIncidentCount',0,'watchCount',1,'current','[]'::jsonb);
$watch$;
create or replace function foundation.evaluate_foundation_readiness_v1(p_environment text default 'production',p_as_of timestamptz default now())
returns jsonb language sql stable security definer set search_path='' as $readiness$
 select jsonb_build_object(
  'readinessState','degraded','privilegedOperationsMode','degraded','workerOperationsMode','degraded',
  'checks',jsonb_build_object('dependencyRollup',jsonb_build_object(
   'degradedScopes',jsonb_build_array('protected-operations'),'guardedScopes','[]'::jsonb,'blockedScopes','[]'::jsonb
  ))
 );
$readiness$;

do $watch$
declare c jsonb;p jsonb;
begin
 c:=foundation.evaluate_readiness_incident_response_v1('contain-degraded-scopes','production');
 p:=foundation.get_readiness_incident_containment_plan_v1('production');
 if c->>'decision'<>'not-applicable' or c->>'reasonCode'<>'readiness-watch-not-persistent'
    or p->>'containmentActive'<>'false' or p->>'recommendedAction'<>'collect-fresh-evidence' then
  raise exception 'Watch must not activate containment: % %',c,p;
 end if;
end;
$watch$;

create or replace function foundation.get_foundation_readiness_incident_summary_v1(p_environment text default 'production')
returns jsonb language sql stable security definer set search_path='' as $incident$
 select jsonb_build_object('state','incident','activeIncidentCount',1,'watchCount',0,'current','[]'::jsonb);
$incident$;

do $incident$
declare o jsonb;e jsonb;c jsonb;p jsonb;
begin
 o:=foundation.evaluate_readiness_incident_response_v1('inspect-readiness-evidence','production');
 e:=foundation.evaluate_readiness_incident_response_v1('collect-fresh-readiness-evidence','production');
 c:=foundation.evaluate_readiness_incident_response_v1('contain-degraded-scopes','production');
 p:=foundation.get_readiness_incident_containment_plan_v1('production');
 if o->>'decision'<>'admit' or o->>'requiredControl'<>'read-only' then raise exception 'Observe must admit'; end if;
 if e->>'decision'<>'admit' or e->>'requiredControl'<>'evidence-only' then raise exception 'Evidence must admit'; end if;
 if c->>'decision'<>'admit' or c->>'requiredControl'<>'existing-safe-mode'
    or c->>'mutatesAuthoritativeTruth'<>'false' or c->>'authorityExpansion'<>'false' then
  raise exception 'Persistent incident containment invalid: %',c;
 end if;
 if p->>'containmentActive'<>'true' or p->>'canonicalTruthMutationAllowed'<>'false'
    or p->>'releaseRebindAllowedByThisPolicy'<>'false' or p->>'automaticDependencyRepair'<>'false'
    or not(p->'degradedScopes' ? 'protected-operations') then
  raise exception 'Containment plan invalid: %',p;
 end if;
end;
$incident$;

rollback;
