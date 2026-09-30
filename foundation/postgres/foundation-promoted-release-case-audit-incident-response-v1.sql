-- Foundation Layer 75: response policy for promotion-trust case-audit incidents.
-- Structural audit incidents may make diagnosis/work materialisation urgent, but they
-- never grant permission to rewrite case history or expand release-truth authority.

create or replace function foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer75_cause$
declare
  v_incident jsonb;
  v_audit jsonb;
  v_incident_state text;
  v_audit_state text;
  v_reason text;
  v_cause_class text;
  v_source_domain text;
  v_next_evidence text;
begin
  v_incident :=
    foundation.get_foundation_promoted_release_case_audit_incident_summary_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_audit :=
    foundation.get_foundation_promoted_release_case_audit_observation_summary_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_incident_state := coalesce(v_incident->>'state','warning');
  v_audit_state := coalesce(v_audit->>'state','unknown');
  v_reason := coalesce(
    v_audit->>'reasonCode',
    'promotion-case-audit-response-cause-unknown'
  );

  if v_incident_state='normal' and v_audit_state='normal' then
    v_cause_class := 'none';
    v_source_domain := 'none';
    v_next_evidence := 'none';

  elsif v_audit_state='gap'
     or v_reason='promotion-case-audit-gap' then
    v_cause_class := 'case-chain-gap';
    v_source_domain := 'case-materialisation';
    v_next_evidence := 'inspect-promotion-case-audit';

  elsif v_audit_state='invalid'
     or v_reason='promotion-case-audit-invalid' then
    v_cause_class := 'case-chain-integrity';
    v_source_domain := 'case-integrity';
    v_next_evidence := 'inspect-promotion-case-history';

  elsif v_audit_state='drift'
     or v_reason='promotion-case-audit-observation-drift' then
    v_cause_class := 'observer-drift';
    v_source_domain := 'case-audit-observer';
    v_next_evidence := 'record-fresh-promotion-case-audit-observation';

  elsif v_audit_state='unknown'
     and v_reason in (
       'promotion-case-audit-observation-missing',
       'promotion-case-audit-observation-stale'
     ) then
    v_cause_class := 'observer-freshness';
    v_source_domain := 'case-audit-observer';
    v_next_evidence := 'record-fresh-promotion-case-audit-observation';

  else
    v_cause_class := 'unknown';
    v_source_domain := 'case-audit';
    v_next_evidence := 'inspect-promotion-case-audit';
  end if;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentCause',
      'shine-foundation/promoted-release-case-audit-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'caseAuditState',v_audit_state,
    'reasonCode',v_reason,
    'causeClass',v_cause_class,
    'sourceDomain',v_source_domain,
    'nextEvidenceAction',v_next_evidence,
    'incidentSummary',v_incident,
    'caseAuditSummary',v_audit,
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer75_cause$;

revoke all on function foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
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
as $layer75_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'promotion-case-audit-response-action-not-registered';
  v_delegated jsonb;
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'promotion-case-audit-response-action-invalid';
  end if;

  v_cause :=
    foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  v_incident_state := coalesce(v_cause->>'incidentState','warning');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-promotion-case-audit' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'promotion-case-audit-response-inspect-audit';

  elsif p_action_key='inspect-promotion-case-history' then
    v_action_class := 'observe';
    if v_cause_class='case-chain-integrity' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'promotion-case-audit-response-inspect-history';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'promotion-case-audit-response-history-inspection-not-relevant';
    end if;

  elsif p_action_key='record-fresh-promotion-case-audit-observation' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','warning','critical')
       and v_cause_class in (
         'observer-drift','observer-freshness','unknown'
       ) then
      v_decision := 'admit';
      v_required_control := 'evidence-only';
      v_reason := 'promotion-case-audit-response-refresh-observation';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'promotion-case-audit-response-observation-refresh-not-relevant';
    end if;

  elsif p_action_key='materialise-current-owner-handoff' then
    v_action_class := 'work-materialisation';
    if v_incident_state in ('watching','warning','critical')
       and v_cause_class='case-chain-gap' then
      v_decision := 'admit';
      v_required_control := 'layer-67-bounded-generator';
      v_reason := 'promotion-case-audit-response-materialise-current-handoff';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'promotion-case-audit-response-handoff-materialisation-not-relevant';
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

    if v_incident_state='normal' then
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'promotion-case-audit-response-release-action-not-applicable';
    else
      v_delegated :=
        foundation.evaluate_control_plane_incident_response_v1(
          p_action_key,p_environment
        );

      v_decision := coalesce(v_delegated->>'decision','deny');
      v_required_control := coalesce(
        v_delegated->>'requiredControl','prohibited'
      );
      v_reason := 'promotion-case-audit-response-delegated-to-layer-38';
    end if;

  elsif p_action_key in (
    'auto-repair-case-chain',
    'rewrite-case-chain-history',
    'delete-case-chain-history',
    'suppress-case-audit-incident',
    'delete-case-audit-incident-history'
  ) then
    v_action_class := case
      when p_action_key='auto-repair-case-chain' then 'automatic-repair'
      else 'history-mutation'
    end;
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'promotion-case-audit-response-history-repair-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentResponseDecision',
      'shine-foundation/promoted-release-case-audit-incident-response-decision-v1',
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
    'delegatedLayer38Decision',v_delegated,
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',coalesce(v_action_class='authoritative-mutation',false),
    'mutatesIncidentHistory',coalesce(v_action_class='history-mutation',false),
    'executesAction',false,
    'cause',v_cause
  );
end;
$layer75_evaluate$;

revoke all on function foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_observation_max_age_seconds integer default 600
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer75_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause :=
    foundation.get_foundation_promoted_release_case_audit_incident_cause_v1(
      p_environment,p_as_of,p_observation_max_age_seconds
    );

  select jsonb_agg(
    foundation.evaluate_foundation_promoted_release_case_audit_incident_response_v1(
      action_key,p_environment,p_as_of,p_observation_max_age_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-promotion-case-audit'),
      (2,'inspect-promotion-case-history'),
      (3,'record-fresh-promotion-case-audit-observation'),
      (4,'materialise-current-owner-handoff'),
      (5,'request-release-reattestation'),
      (6,'propose-registry-repair'),
      (7,'propose-release-ledger-repair'),
      (8,'apply-registry-repair'),
      (9,'apply-release-ledger-repair'),
      (10,'rebind-release-identity'),
      (11,'auto-repair-case-chain'),
      (12,'rewrite-case-chain-history'),
      (13,'delete-case-chain-history'),
      (14,'suppress-case-audit-incident'),
      (15,'delete-case-audit-incident-history')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAuditIncidentResponsePlan',
      'shine-foundation/promoted-release-case-audit-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'caseAuditState',v_cause->>'caseAuditState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticRepairAllowed',false,
    'historyRewriteAllowed',false,
    'caseGapWorkMaterialiser',
      'foundation.generate_foundation_promoted_release_owner_handoff_v1',
    'releaseTruthAuthority',
      'foundation.evaluate_control_plane_incident_response_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer75_plan$;

revoke all on function foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_case_audit_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
