begin;

-- Healthy baseline.
create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_incident_normal$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','normal','activeIncidentCount',0,'watchCount',0,
    'caseAuditState','normal','caseAuditReasonCode','promotion-case-audit-current',
    'observationFresh',true,'observationMatchesLive',true,'currentEvent',null,
    'automaticRepair',false,'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
$l75_incident_normal$;

create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_audit_normal$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','normal','reasonCode','promotion-case-audit-current',
    'observationFresh',true,'observationMatchesLive',true
  );
$l75_audit_normal$;

do $l75_normal$
declare cause jsonb; materialise jsonb; unknown_action jsonb;
begin
  cause:=foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
    'production',now(),600
  );

  if cause->>'causeClass'<>'none'
     or cause->>'sourceDomain'<>'none'
     or cause->>'authorityExpansion'<>'false'
     or cause->>'historyRewriteAllowed'<>'false' then
    raise exception 'Layer 75 healthy cause invalid: %',cause;
  end if;

  materialise:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'materialise-current-owner-handoff','production',now(),600
    );

  if materialise->>'decision'<>'not-applicable' then
    raise exception 'Layer 75 healthy handoff materialisation must be not-applicable: %',materialise;
  end if;

  unknown_action:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'invented-case-chain-magic','production',now(),600
    );

  if unknown_action->>'decision'<>'deny'
     or unknown_action->>'requiredControl'<>'prohibited' then
    raise exception 'Layer 75 unknown action must fail closed: %',unknown_action;
  end if;
end;
$l75_normal$;


-- Critical GAP: bounded handoff materialisation admitted, Layer 38 remains authority.
create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_incident_gap$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','critical','activeIncidentCount',1,'watchCount',0,
    'caseAuditState','gap','caseAuditReasonCode','promotion-case-audit-gap',
    'observationFresh',true,'observationMatchesLive',true,
    'currentEvent',jsonb_build_object(
      'eventId','75000000-0000-4000-8000-000000000001',
      'eventType','opened','sourceState','gap','severity','critical',
      'reasonCode','promotion-case-audit-gap'
    )
  );
$l75_incident_gap$;

create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_audit_gap$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','gap','reasonCode','promotion-case-audit-gap',
    'observationFresh',true,'observationMatchesLive',true
  );
$l75_audit_gap$;

create or replace function foundation.evaluate_control_plane_incident_response_v1(
  p_action_key text,
  p_environment text default 'production'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $l75_layer38_gate$
  select jsonb_build_object(
    'foundationIncidentResponseDecisionResponse',
      'shine-foundation/incident-response-decision-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'actionKey',p_action_key,
    'decision',case
      when p_action_key in ('apply-registry-repair','apply-release-ledger-repair')
        then 'approval-required'
      when p_action_key='rebind-release-identity'
        then 'deny'
      when p_action_key like 'propose-%'
        then 'admit'
      when p_action_key='request-release-reattestation'
        then 'admit'
      else 'deny'
    end,
    'requiredControl',case
      when p_action_key in ('apply-registry-repair','apply-release-ledger-repair')
        then 'external-approval'
      when p_action_key like 'propose-%'
        then 'operator-proposal'
      when p_action_key='request-release-reattestation'
        then 'evidence-only'
      else 'prohibited'
    end,
    'authorityExpansion',false
  );
$l75_layer38_gate$;

do $l75_gap$
declare
  cause jsonb;
  materialise jsonb;
  apply_registry jsonb;
  rebind jsonb;
  auto_repair jsonb;
  plan jsonb;
begin
  cause:=foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
    'production',now(),600
  );

  if cause->>'causeClass'<>'case-chain-gap'
     or cause->>'sourceDomain'<>'case-materialisation'
     or cause->>'nextEvidenceAction'<>'inspect-promotion-case-audit' then
    raise exception 'Layer 75 GAP cause invalid: %',cause;
  end if;

  materialise:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'materialise-current-owner-handoff','production',now(),600
    );

  if materialise->>'decision'<>'admit'
     or materialise->>'requiredControl'<>'layer-67-bounded-generator'
     or materialise->>'authorityExpansion'<>'false'
     or materialise->>'executesAction'<>'false' then
    raise exception 'Layer 75 GAP materialisation policy invalid: %',materialise;
  end if;

  apply_registry:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'apply-registry-repair','production',now(),600
    );

  if apply_registry->>'decision'<>'approval-required'
     or apply_registry->>'requiredControl'<>'external-approval'
     or apply_registry->>'reasonCode'<>
        'promotion-case-audit-response-delegated-to-layer-38' then
    raise exception 'Layer 75 must preserve Layer 38 registry authority: %',apply_registry;
  end if;

  rebind:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'rebind-release-identity','production',now(),600
    );

  if rebind->>'decision'<>'deny'
     or rebind->>'requiredControl'<>'prohibited' then
    raise exception 'Layer 75 must preserve Layer 38 rebind denial: %',rebind;
  end if;

  auto_repair:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'auto-repair-case-chain','production',now(),600
    );

  if auto_repair->>'decision'<>'deny'
     or auto_repair->>'historyRewriteAllowed'<>'false'
     or auto_repair->>'automaticRepairAllowed'<>'false' then
    raise exception 'Layer 75 automatic case-chain repair must remain denied: %',auto_repair;
  end if;

  plan:=foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(
    'production',now(),600
  );

  if plan->>'incidentState'<>'critical'
     or plan->>'causeClass'<>'case-chain-gap'
     or plan->>'authorityExpansion'<>'false'
     or plan->>'automaticRepairAllowed'<>'false'
     or plan->>'historyRewriteAllowed'<>'false'
     or jsonb_array_length(plan->'actions')<>15 then
    raise exception 'Layer 75 GAP response plan invalid: %',plan;
  end if;
end;
$l75_gap$;


-- INVALID: inspect history allowed; materialising new work does not repair history.
create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_incident_invalid$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','critical','activeIncidentCount',1,'watchCount',0,
    'caseAuditState','invalid','caseAuditReasonCode','promotion-case-audit-invalid',
    'observationFresh',true,'observationMatchesLive',true
  );
$l75_incident_invalid$;

create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_audit_invalid$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','invalid','reasonCode','promotion-case-audit-invalid',
    'observationFresh',true,'observationMatchesLive',true
  );
$l75_audit_invalid$;

do $l75_invalid$
declare cause jsonb; inspect_history jsonb; materialise jsonb; delete_history jsonb;
begin
  cause:=foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
    'production',now(),600
  );

  if cause->>'causeClass'<>'case-chain-integrity'
     or cause->>'sourceDomain'<>'case-integrity'
     or cause->>'nextEvidenceAction'<>'inspect-promotion-case-history' then
    raise exception 'Layer 75 INVALID cause invalid: %',cause;
  end if;

  inspect_history:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'inspect-promotion-case-history','production',now(),600
    );

  if inspect_history->>'decision'<>'admit'
     or inspect_history->>'requiredControl'<>'read-only' then
    raise exception 'Layer 75 INVALID history inspection invalid: %',inspect_history;
  end if;

  materialise:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'materialise-current-owner-handoff','production',now(),600
    );

  if materialise->>'decision'<>'not-applicable' then
    raise exception 'Layer 75 INVALID must not pretend new handoff repairs history: %',materialise;
  end if;

  delete_history:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'delete-case-chain-history','production',now(),600
    );

  if delete_history->>'decision'<>'deny'
     or delete_history->>'mutatesIncidentHistory'<>'true'
     or delete_history->>'historyRewriteAllowed'<>'false' then
    raise exception 'Layer 75 historical deletion must remain denied: %',delete_history;
  end if;
end;
$l75_invalid$;


-- Observer freshness only admits fresh evidence collection.
create or replace function foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_incident_unknown$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentSummary',
      'shine-foundation/promoted-release-case-audit-incident-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','warning','activeIncidentCount',1,'watchCount',0,
    'caseAuditState','unknown',
    'caseAuditReasonCode','promotion-case-audit-observation-stale',
    'observationFresh',false,'observationMatchesLive',true
  );
$l75_incident_unknown$;

create or replace function foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_max_age_seconds integer default 600
)
returns jsonb language sql stable security definer set search_path='' as $l75_audit_unknown$
  select jsonb_build_object(
    'foundationPromotedReleaseCaseAuditObservationSummary',
      'shine-foundation/promoted-release-case-audit-observation-summary-v1',
    'schemaVersion','1.0.0','environment',p_environment,'evaluatedAt',p_as_of,
    'state','unknown','reasonCode','promotion-case-audit-observation-stale',
    'observationFresh',false,'observationMatchesLive',true
  );
$l75_audit_unknown$;

do $l75_observer$
declare cause jsonb; refresh jsonb;
begin
  cause:=foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
    'production',now(),600
  );

  if cause->>'causeClass'<>'observer-freshness'
     or cause->>'sourceDomain'<>'case-audit-observer' then
    raise exception 'Layer 75 observer cause invalid: %',cause;
  end if;

  refresh:=
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      'record-fresh-promotion-case-audit-observation','production',now(),600
    );

  if refresh->>'decision'<>'admit'
     or refresh->>'requiredControl'<>'evidence-only'
     or refresh->>'mutatesAuthoritativeTruth'<>'false'
     or refresh->>'executesAction'<>'false' then
    raise exception 'Layer 75 observer refresh must remain evidence-only: %',refresh;
  end if;
end;
$l75_observer$;


do $l75_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_has_role(
       'foundation_gateway','foundation_runtime','MEMBER'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 75 case-audit response privilege boundary invalid';
  end if;
end;
$l75_privileges$;

rollback;
