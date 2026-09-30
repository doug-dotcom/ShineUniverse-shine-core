begin;

-- Deterministic Layer-66 summaries. Tests replace readers transactionally only.

create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer66_normal_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','normal',
    'activeIncidentCount',0,
    'watchCount',0,
    'trustState','normal',
    'trustReasonCode','promoted-release-current',
    'automaticRepair',false
  );
$layer66_normal_incident$;

create or replace function foundation.get_foundation_promoted_release_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer66_normal_trust$
  select jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','normal',
    'reasonCode','promoted-release-current',
    'observationFresh',true,
    'observationMatchesLive',true
  );
$layer66_normal_trust$;

do $layer66_normal$
declare
  cause jsonb;
  inspect_decision jsonb;
  refresh_decision jsonb;
begin
  cause:=foundation.get_foundation_promoted_release_incident_cause_v1(
    'production',now(),600
  );

  if cause->>'causeClass'<>'none'
     or cause->>'sourceDomain'<>'none'
     or cause->>'authorityExpansion'<>'false' then
    raise exception 'Layer 66 normal cause invalid: %',cause;
  end if;

  inspect_decision:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'inspect-promoted-release-trust','production',now(),600
    );

  if inspect_decision->>'decision'<>'admit'
     or inspect_decision->>'requiredControl'<>'read-only' then
    raise exception 'Layer 66 trust inspection must remain available: %',inspect_decision;
  end if;

  refresh_decision:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'record-fresh-promoted-release-observation','production',now(),600
    );

  if refresh_decision->>'decision'<>'not-applicable' then
    raise exception 'Layer 66 healthy observer refresh should be not-applicable: %',refresh_decision;
  end if;
end;
$layer66_normal$;


create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer66_critical_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','critical',
    'activeIncidentCount',1,
    'watchCount',0,
    'trustState','hold',
    'trustReasonCode','canonical-source-truth-not-pass',
    'automaticRepair',false
  );
$layer66_critical_incident$;

create or replace function foundation.get_foundation_promoted_release_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer66_hold_trust$
  select jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','hold',
    'reasonCode','canonical-source-truth-not-pass',
    'observationFresh',true,
    'observationMatchesLive',true
  );
$layer66_hold_trust$;

-- Stub Layer 38 to prove Layer 66 delegates rather than upgrades mutation authority.
create or replace function foundation.evaluate_control_plane_incident_response_v1(
  p_action_key text,
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer66_layer38_gate$
  select jsonb_build_object(
    'foundationIncidentResponseDecisionResponse',
      'shine-foundation/incident-response-decision-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'actionKey',p_action_key,
    'decision',case
      when p_action_key in (
        'apply-registry-repair',
        'apply-release-ledger-repair'
      ) then 'approval-required'
      when p_action_key='rebind-release-identity' then 'deny'
      when p_action_key like 'propose-%' then 'admit'
      when p_action_key='request-release-reattestation' then 'admit'
      else 'deny'
    end,
    'requiredControl',case
      when p_action_key in (
        'apply-registry-repair',
        'apply-release-ledger-repair'
      ) then 'external-approval'
      when p_action_key like 'propose-%' then 'operator-proposal'
      when p_action_key='request-release-reattestation' then 'evidence-only'
      else 'prohibited'
    end,
    'authorityExpansion',false
  );
$layer66_layer38_gate$;

do $layer66_critical$
declare
  cause jsonb;
  inspect_source jsonb;
  apply_registry jsonb;
  rebind jsonb;
  auto_repair jsonb;
  plan jsonb;
begin
  cause:=foundation.get_foundation_promoted_release_incident_cause_v1(
    'production',now(),600
  );

  if cause->>'causeClass'<>'canonical-source-truth'
     or cause->>'sourceDomain'<>'source-truth'
     or cause->>'nextEvidenceAction'<>'inspect-canonical-source-truth' then
    raise exception 'Layer 66 critical cause classification invalid: %',cause;
  end if;

  inspect_source:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'inspect-canonical-source-truth','production',now(),600
    );

  if inspect_source->>'decision'<>'admit'
     or inspect_source->>'requiredControl'<>'read-only' then
    raise exception 'Layer 66 critical source inspection must be admitted: %',inspect_source;
  end if;

  apply_registry:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'apply-registry-repair','production',now(),600
    );

  if apply_registry->>'decision'<>'approval-required'
     or apply_registry->>'requiredControl'<>'external-approval'
     or apply_registry->>'authorityExpansion'<>'false'
     or apply_registry->>'reasonCode'<>
        'promoted-release-response-delegated-to-control-plane-policy' then
    raise exception 'Layer 66 must preserve delegated registry authority: %',apply_registry;
  end if;

  rebind:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'rebind-release-identity','production',now(),600
    );

  if rebind->>'decision'<>'deny'
     or rebind->>'requiredControl'<>'prohibited' then
    raise exception 'Layer 66 must preserve delegated rebind denial: %',rebind;
  end if;

  auto_repair:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'auto-repair-authoritative-truth','production',now(),600
    );

  if auto_repair->>'decision'<>'deny'
     or auto_repair->>'automaticRepairAllowed'<>'false' then
    raise exception 'Layer 66 auto repair must remain denied: %',auto_repair;
  end if;

  plan:=foundation.get_foundation_promoted_release_incident_response_plan_v1(
    'production',now(),600
  );

  if plan->>'incidentState'<>'critical'
     or plan->>'causeClass'<>'canonical-source-truth'
     or plan->>'authorityExpansion'<>'false'
     or plan->>'automaticRepairAllowed'<>'false'
     or jsonb_array_length(plan->'actions')<>13 then
    raise exception 'Layer 66 critical response plan invalid: %',plan;
  end if;
end;
$layer66_critical$;


create or replace function foundation.get_foundation_promoted_release_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer66_warning_incident$
  select jsonb_build_object(
    'foundationPromotedReleaseIncidentSummaryResponse',
      'shine-foundation/promoted-release-incident-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','warning',
    'activeIncidentCount',1,
    'watchCount',0,
    'trustState','unknown',
    'trustReasonCode','promoted-release-observation-stale',
    'automaticRepair',false
  );
$layer66_warning_incident$;

create or replace function foundation.get_foundation_promoted_release_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $layer66_stale_trust$
  select jsonb_build_object(
    'foundationPromotedReleaseObservationSummaryResponse',
      'shine-foundation/promoted-release-observation-summary-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state','unknown',
    'reasonCode','promoted-release-observation-stale',
    'observationFresh',false,
    'observationMatchesLive',true
  );
$layer66_stale_trust$;

do $layer66_observer$
declare
  cause jsonb;
  refresh jsonb;
begin
  cause:=foundation.get_foundation_promoted_release_incident_cause_v1(
    'production',now(),600
  );

  if cause->>'causeClass'<>'observer-freshness'
     or cause->>'sourceDomain'<>'promotion-observer'
     or cause->>'nextEvidenceAction'<>
        'record-fresh-promoted-release-observation' then
    raise exception 'Layer 66 observer cause invalid: %',cause;
  end if;

  refresh:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'record-fresh-promoted-release-observation','production',now(),600
    );

  if refresh->>'decision'<>'admit'
     or refresh->>'requiredControl'<>'evidence-only'
     or refresh->>'mutatesAuthoritativeTruth'<>'false' then
    raise exception 'Layer 66 observer refresh should be evidence-only: %',refresh;
  end if;
end;
$layer66_observer$;


do $layer66_fail_closed$
declare
  unknown_action jsonb;
  suppress_history jsonb;
begin
  unknown_action:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'invented-magic-fix','production',now(),600
    );

  if unknown_action->>'decision'<>'deny'
     or unknown_action->>'requiredControl'<>'prohibited' then
    raise exception 'Layer 66 unknown action must fail closed: %',unknown_action;
  end if;

  suppress_history:=
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      'suppress-promoted-release-incident','production',now(),600
    );

  if suppress_history->>'decision'<>'deny'
     or suppress_history->>'mutatesIncidentHistory'<>'true' then
    raise exception 'Layer 66 history suppression must remain denied: %',suppress_history;
  end if;
end;
$layer66_fail_closed$;


do $layer66_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.evaluate_foundation_promoted_release_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 66 privilege boundary invalid';
  end if;
end;
$layer66_privileges$;

rollback;
