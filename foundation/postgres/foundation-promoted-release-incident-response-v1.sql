-- Foundation Layer 66: promoted-release incident response policy.
-- A consumer-trust incident may make diagnosis urgent, but it never expands
-- authoritative mutation rights. Layer 66 classifies the likely trust cause,
-- admits only read/evidence actions directly, and delegates all release-truth
-- mutation/proposal authority to the existing Layer-38 control-plane gate.

create or replace function foundation.get_foundation_promoted_release_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer66_cause$
declare
  v_incident jsonb;
  v_trust jsonb;
  v_incident_state text;
  v_trust_state text;
  v_reason text;
  v_cause_class text;
  v_source_domain text;
  v_next_evidence text;
begin
  v_incident :=
    foundation.get_foundation_promoted_release_incident_summary_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_trust :=
    foundation.get_foundation_promoted_release_observation_summary_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_incident_state := coalesce(v_incident->>'state','warning');
  v_trust_state := coalesce(v_trust->>'state','unknown');
  v_reason := coalesce(
    v_trust->>'reasonCode',
    'promoted-release-cause-unknown'
  );

  if v_incident_state='normal' and v_trust_state='normal' then
    v_cause_class := 'none';
    v_source_domain := 'none';
    v_next_evidence := 'none';

  elsif v_reason in (
    'canonical-source-truth-not-pass',
    'canonical-binding-missing'
  ) then
    v_cause_class := 'canonical-source-truth';
    v_source_domain := 'source-truth';
    v_next_evidence := 'inspect-canonical-source-truth';

  elsif v_reason='promotion-closure-receipt-missing' then
    v_cause_class := 'promotion-closure-open';
    v_source_domain := 'promotion-closure';
    v_next_evidence := 'inspect-promotion-closure';

  elsif v_reason='promotion-closure-integrity-failed' then
    v_cause_class := 'promotion-closure-integrity';
    v_source_domain := 'promotion-closure';
    v_next_evidence := 'inspect-promotion-closure';

  elsif v_reason='promotion-closure-no-longer-current' then
    v_cause_class := 'promotion-closure-stale';
    v_source_domain := 'promotion-closure';
    v_next_evidence := 'inspect-canonical-source-truth';

  elsif v_reason='promoted-release-observation-drift' then
    v_cause_class := 'observer-drift';
    v_source_domain := 'promotion-observer';
    v_next_evidence := 'record-fresh-promoted-release-observation';

  elsif v_reason in (
    'promoted-release-observation-missing',
    'promoted-release-observation-stale'
  ) then
    v_cause_class := 'observer-freshness';
    v_source_domain := 'promotion-observer';
    v_next_evidence := 'record-fresh-promoted-release-observation';

  elsif v_trust_state='hold' then
    v_cause_class := 'promotion-hold-other';
    v_source_domain := 'promotion-closure';
    v_next_evidence := 'inspect-promotion-closure';

  else
    v_cause_class := 'unknown';
    v_source_domain := 'promotion-trust';
    v_next_evidence := 'inspect-promoted-release-trust';
  end if;

  return jsonb_build_object(
    'foundationPromotedReleaseIncidentCauseResponse',
      'shine-foundation/promoted-release-incident-cause-response-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'trustState',v_trust_state,
    'reasonCode',v_reason,
    'causeClass',v_cause_class,
    'sourceDomain',v_source_domain,
    'nextEvidenceAction',v_next_evidence,
    'incidentSummary',v_incident,
    'trustSummary',v_trust,
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'mutatesAuthoritativeTruth',false
  );
end;
$layer66_cause$;

revoke all on function foundation.get_foundation_promoted_release_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_foundation_promoted_release_incident_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer66_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'promoted-release-response-action-not-registered';
  v_delegated jsonb;
  v_delegated_decision text;
  v_delegated_control text;
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'promoted-release-response-action-invalid';
  end if;

  v_cause :=
    foundation.get_foundation_promoted_release_incident_cause_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_incident_state := coalesce(v_cause->>'incidentState','warning');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-promoted-release-trust' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'promoted-release-response-observe';

  elsif p_action_key='inspect-canonical-source-truth' then
    v_action_class := 'observe';
    if v_incident_state='normal' then
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'promoted-release-response-not-applicable';
    else
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'promoted-release-response-inspect-source-truth';
    end if;

  elsif p_action_key='inspect-promotion-closure' then
    v_action_class := 'observe';
    if v_incident_state='normal' then
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'promoted-release-response-not-applicable';
    else
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'promoted-release-response-inspect-closure';
    end if;

  elsif p_action_key='record-fresh-promoted-release-observation' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','warning','critical')
       and v_cause_class in ('observer-drift','observer-freshness','unknown') then
      v_decision := 'admit';
      v_required_control := 'evidence-only';
      v_reason := 'promoted-release-response-refresh-observation';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'promoted-release-response-observation-refresh-not-relevant';
    end if;

  elsif p_action_key in (
    'request-release-reattestation',
    'propose-registry-repair',
    'propose-release-ledger-repair',
    'apply-registry-repair',
    'apply-release-ledger-repair',
    'rebind-release-identity'
  ) then
    v_action_class := case
      when p_action_key='request-release-reattestation' then 'evidence'
      when p_action_key like 'propose-%' then 'proposal'
      else 'authoritative-mutation'
    end;

    v_delegated :=
      foundation.evaluate_control_plane_incident_response_v1(
        p_action_key,p_environment
      );

    v_delegated_decision := coalesce(v_delegated->>'decision','deny');
    v_delegated_control := coalesce(
      v_delegated->>'requiredControl','prohibited'
    );

    -- Never upgrade delegated authority. Layer 38 remains the release-truth gate.
    v_decision := v_delegated_decision;
    v_required_control := v_delegated_control;
    v_reason := 'promoted-release-response-delegated-to-control-plane-policy';

  elsif p_action_key='auto-repair-authoritative-truth' then
    v_action_class := 'authoritative-mutation';
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'promoted-release-response-auto-repair-prohibited';

  elsif p_action_key in (
    'suppress-promoted-release-incident',
    'delete-promoted-release-incident-history'
  ) then
    v_action_class := 'history-mutation';
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'promoted-release-response-history-mutation-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationPromotedReleaseIncidentResponseDecision',
      'shine-foundation/promoted-release-incident-response-decision-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'causeClass',v_cause_class,
    'actionKey',p_action_key,
    'actionClass',v_action_class,
    'decision',v_decision,
    'requiredControl',v_required_control,
    'reasonCode',v_reason,
    'delegatedControlPlaneDecision',v_delegated,
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'mutatesAuthoritativeTruth',v_action_class='authoritative-mutation',
    'mutatesIncidentHistory',v_action_class='history-mutation',
    'cause',v_cause
  );
end;
$layer66_evaluate$;

revoke all on function foundation.evaluate_foundation_promoted_release_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.evaluate_foundation_promoted_release_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_foundation_promoted_release_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer66_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause :=
    foundation.get_foundation_promoted_release_incident_cause_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  select jsonb_agg(
    foundation.evaluate_foundation_promoted_release_incident_response_v1(
      action_key,p_environment,p_as_of,p_observation_max_age_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-promoted-release-trust'),
      (2,'inspect-canonical-source-truth'),
      (3,'inspect-promotion-closure'),
      (4,'record-fresh-promoted-release-observation'),
      (5,'request-release-reattestation'),
      (6,'propose-registry-repair'),
      (7,'propose-release-ledger-repair'),
      (8,'apply-registry-repair'),
      (9,'apply-release-ledger-repair'),
      (10,'rebind-release-identity'),
      (11,'auto-repair-authoritative-truth'),
      (12,'suppress-promoted-release-incident'),
      (13,'delete-promoted-release-incident-history')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationPromotedReleaseIncidentResponsePlan',
      'shine-foundation/promoted-release-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'trustState',v_cause->>'trustState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'releaseTruthAuthority',
      'foundation.evaluate_control_plane_incident_response_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer66_plan$;

revoke all on function foundation.get_foundation_promoted_release_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
