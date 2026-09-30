-- Foundation Layer 72: end-to-end promotion-trust case integrity audit.
-- Read-only control-plane audit across Layers 65-71. Detects orphaned, skipped,
-- mis-bound or overdue stages without changing any incident, trust or owner state.

create or replace function foundation.get_foundation_promoted_release_case_audit_v1(
  p_environment text default 'production',
  p_limit integer default 25,
  p_as_of timestamptz default now(),
  p_handoff_grace_seconds integer default 180
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer72_audit$
declare
  v_incident jsonb;
  v_incident_state text;
  v_current_event_id uuid;
  v_current_event_at timestamptz;
  v_current_event_age integer;
  v_active_requires_handoff boolean := false;
  v_current_handoff_present boolean := false;
  v_active_handoff_state text := 'not-required';

  v_rec record;
  v_items jsonb := '[]'::jsonb;
  v_case_count integer := 0;
  v_visible_count integer := 0;
  v_invalid_count integer := 0;
  v_active_case_count integer := 0;
  v_pending_count integer := 0;
  v_terminal_count integer := 0;
  v_historical_count integer := 0;

  v_handoff_integrity boolean;
  v_response_integrity boolean;
  v_evidence_integrity boolean;
  v_verification_integrity boolean;
  v_response_binding boolean;
  v_evidence_binding boolean;
  v_verification_binding boolean;
  v_case_valid boolean;
  v_case_current boolean;
  v_case_stage text;
  v_terminal boolean;
  v_overall_state text;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$' then
    raise exception 'promoted-release-case-audit-environment-invalid';
  end if;

  if p_limit is null or p_limit<1 or p_limit>100 then
    raise exception 'promoted-release-case-audit-limit-invalid';
  end if;

  if p_as_of is null then
    raise exception 'promoted-release-case-audit-time-invalid';
  end if;

  if p_handoff_grace_seconds is null
     or p_handoff_grace_seconds<60
     or p_handoff_grace_seconds>900 then
    raise exception 'promoted-release-case-audit-grace-invalid';
  end if;

  v_incident :=
    foundation.get_foundation_promoted_release_incident_summary_v1(
      p_environment,p_as_of,600
    );

  v_incident_state := coalesce(v_incident->>'state','unknown');
  v_active_requires_handoff := v_incident_state in ('warning','critical');

  begin
    v_current_event_id :=
      nullif(v_incident#>>'{currentEvent,eventId}','')::uuid;
  exception when invalid_text_representation then
    v_current_event_id := null;
  end;

  if v_active_requires_handoff and v_current_event_id is not null then
    select i.occurred_at
    into v_current_event_at
    from foundation.foundation_promoted_release_incident_events i
    where i.event_id=v_current_event_id
      and i.environment=p_environment;

    if v_current_event_at is not null then
      v_current_event_age := greatest(
        0,
        floor(extract(epoch from (p_as_of-v_current_event_at)))::integer
      );
    end if;

    select exists(
      select 1
      from foundation.foundation_promoted_release_owner_handoffs h
      where h.environment=p_environment
        and h.incident_event_id=v_current_event_id
        and h.owner_service_id='foundation.gateway'
        and h.owner_component='shine-core'
    )
    into v_current_handoff_present;

    v_active_handoff_state := case
      when v_current_handoff_present then 'present'
      when v_current_event_at is null then 'missing'
      when v_current_event_age<=p_handoff_grace_seconds then 'grace'
      else 'missing'
    end;
  elsif v_active_requires_handoff then
    v_active_handoff_state := 'missing';
  end if;

  for v_rec in
    select
      h.*,
      h.response_plan_fingerprint as handoff_response_plan_fingerprint,
      r.response_id,
      r.response_state,
      r.incident_event_id as response_incident_event_id,
      r.environment as response_environment,
      r.owner_service_id as response_owner_service_id,
      r.owner_component as response_owner_component,
      r.handoff_sha256 as response_handoff_sha256,
      r.response_plan_fingerprint as response_response_plan_fingerprint,
      r.response as response_doc,
      r.response_sha256,
      r.responded_at,
      e.evidence_return_id,
      e.response_id as evidence_response_id,
      e.incident_event_id as evidence_incident_event_id,
      e.environment as evidence_environment,
      e.owner_service_id as evidence_owner_service_id,
      e.owner_component as evidence_owner_component,
      e.owner_reported_outcome,
      e.handoff_sha256 as evidence_handoff_sha256,
      e.response_sha256 as evidence_response_sha256,
      e.response_plan_fingerprint as evidence_response_plan_fingerprint,
      e.evidence_return,
      e.evidence_return_sha256,
      e.returned_at,
      v.verification_id,
      v.handoff_id as verification_handoff_id,
      v.response_id as verification_response_id,
      v.incident_event_id as verification_incident_event_id,
      v.environment as verification_environment,
      v.source_evidence_return_sha256,
      v.verification_state,
      v.owner_claim_alignment,
      v.verification_proof,
      v.verification_proof_sha256,
      v.verified_at
    from foundation.foundation_promoted_release_owner_handoffs h
    left join foundation.foundation_promoted_release_owner_handoff_responses r
      on r.handoff_id=h.handoff_id
    left join foundation.foundation_promoted_release_owner_evidence_returns e
      on e.handoff_id=h.handoff_id
    left join foundation.foundation_promoted_release_owner_evidence_verifications v
      on v.evidence_return_id=e.evidence_return_id
    where h.environment=p_environment
      and h.owner_service_id='foundation.gateway'
      and h.owner_component='shine-core'
    order by h.handoff_sequence desc
  loop
    v_case_count := v_case_count+1;

    v_handoff_integrity :=
      encode(
        extensions.digest(
          convert_to(v_rec.handoff::text,'UTF8'),
          'sha256'
        ),
        'hex'
      ) = v_rec.handoff_sha256;

    v_response_integrity :=
      v_rec.response_id is null
      or encode(
        extensions.digest(
          convert_to(v_rec.response_doc::text,'UTF8'),
          'sha256'
        ),
        'hex'
      ) = v_rec.response_sha256;

    v_evidence_integrity :=
      v_rec.evidence_return_id is null
      or encode(
        extensions.digest(
          convert_to(v_rec.evidence_return::text,'UTF8'),
          'sha256'
        ),
        'hex'
      ) = v_rec.evidence_return_sha256;

    v_verification_integrity :=
      v_rec.verification_id is null
      or encode(
        extensions.digest(
          convert_to(v_rec.verification_proof::text,'UTF8'),
          'sha256'
        ),
        'hex'
      ) = v_rec.verification_proof_sha256;

    v_response_binding :=
      v_rec.response_id is null
      or (
        v_rec.response_incident_event_id is not distinct from v_rec.incident_event_id
        and v_rec.response_environment is not distinct from v_rec.environment
        and v_rec.response_owner_service_id is not distinct from v_rec.owner_service_id
        and v_rec.response_owner_component is not distinct from v_rec.owner_component
        and v_rec.response_handoff_sha256 is not distinct from v_rec.handoff_sha256
        and v_rec.response_response_plan_fingerprint is not distinct from
            v_rec.handoff_response_plan_fingerprint
      );

    v_evidence_binding :=
      v_rec.evidence_return_id is null
      or (
        v_rec.response_id is not null
        and v_rec.evidence_response_id is not distinct from v_rec.response_id
        and v_rec.evidence_incident_event_id is not distinct from v_rec.incident_event_id
        and v_rec.evidence_environment is not distinct from v_rec.environment
        and v_rec.evidence_owner_service_id is not distinct from v_rec.owner_service_id
        and v_rec.evidence_owner_component is not distinct from v_rec.owner_component
        and v_rec.evidence_handoff_sha256 is not distinct from v_rec.handoff_sha256
        and v_rec.evidence_response_sha256 is not distinct from v_rec.response_sha256
        and v_rec.evidence_response_plan_fingerprint is not distinct from
            v_rec.handoff_response_plan_fingerprint
      );

    v_verification_binding :=
      v_rec.verification_id is null
      or (
        v_rec.evidence_return_id is not null
        and v_rec.verification_handoff_id is not distinct from v_rec.handoff_id
        and v_rec.verification_response_id is not distinct from v_rec.response_id
        and v_rec.verification_incident_event_id is not distinct from v_rec.incident_event_id
        and v_rec.verification_environment is not distinct from v_rec.environment
        and v_rec.source_evidence_return_sha256 is not distinct from
            v_rec.evidence_return_sha256
      );

    v_case_valid :=
      v_handoff_integrity
      and v_response_integrity
      and v_evidence_integrity
      and v_verification_integrity
      and v_response_binding
      and v_evidence_binding
      and v_verification_binding
      and not (v_rec.evidence_return_id is not null and v_rec.response_id is null)
      and not (v_rec.verification_id is not null and v_rec.evidence_return_id is null);

    v_case_current :=
      v_active_requires_handoff
      and v_current_event_id is not null
      and v_rec.incident_event_id=v_current_event_id;

    v_case_stage := case
      when not v_case_valid then 'invalid'
      when v_rec.response_id is null then 'awaiting-owner-response'
      when v_rec.response_state='rejected' then 'owner-rejected'
      when v_rec.response_state='clarification-requested' then 'clarification-requested'
      when v_rec.response_state='accepted'
       and v_rec.evidence_return_id is null then 'awaiting-owner-evidence'
      when v_rec.response_state='accepted'
       and v_rec.evidence_return_id is not null
       and v_rec.verification_id is null then 'awaiting-independent-verification'
      when v_rec.verification_id is not null then 'verified'
      else 'invalid'
    end;

    v_terminal := v_case_stage in ('owner-rejected','verified');

    if not v_case_valid then
      v_invalid_count := v_invalid_count+1;
    end if;

    if v_case_current then
      v_active_case_count := v_active_case_count+1;
    else
      v_historical_count := v_historical_count+1;
    end if;

    if not v_terminal and v_case_valid then
      v_pending_count := v_pending_count+1;
    end if;

    if v_terminal and v_case_valid then
      v_terminal_count := v_terminal_count+1;
    end if;

    if v_visible_count<p_limit then
      v_items := v_items || jsonb_build_array(
        jsonb_build_object(
          'handoffId',v_rec.handoff_id,
          'incidentEventId',v_rec.incident_event_id,
          'currentCase',v_case_current,
          'historical',not v_case_current,
          'caseStage',v_case_stage,
          'terminal',v_terminal,
          'structurallyValid',v_case_valid,
          'ownerServiceId',v_rec.owner_service_id,
          'ownerComponent',v_rec.owner_component,
          'causeClass',v_rec.cause_class,
          'sourceDomain',v_rec.source_domain,
          'responseState',v_rec.response_state,
          'evidenceReturnId',v_rec.evidence_return_id,
          'ownerReportedOutcome',v_rec.owner_reported_outcome,
          'verificationId',v_rec.verification_id,
          'verificationState',v_rec.verification_state,
          'ownerClaimAlignment',v_rec.owner_claim_alignment,
          'integrityChecks',jsonb_build_object(
            'handoff',v_handoff_integrity,
            'response',v_response_integrity,
            'evidence',v_evidence_integrity,
            'verification',v_verification_integrity
          ),
          'bindingChecks',jsonb_build_object(
            'response',v_response_binding,
            'evidence',v_evidence_binding,
            'verification',v_verification_binding
          ),
          'handoffSha256',v_rec.handoff_sha256,
          'responseSha256',v_rec.response_sha256,
          'evidenceReturnSha256',v_rec.evidence_return_sha256,
          'verificationProofSha256',v_rec.verification_proof_sha256,
          'createdAt',v_rec.created_at,
          'respondedAt',v_rec.responded_at,
          'returnedAt',v_rec.returned_at,
          'verifiedAt',v_rec.verified_at
        )
      );
      v_visible_count := v_visible_count+1;
    end if;
  end loop;

  v_overall_state := case
    when v_invalid_count>0 then 'invalid'
    when v_active_handoff_state='missing' then 'gap'
    when v_active_requires_handoff then 'active-work'
    when v_case_count=0 then 'idle'
    else 'historical'
  end;

  return jsonb_build_object(
    'foundationPromotedReleaseCaseAudit',
      'shine-foundation/promoted-release-case-audit-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'overallState',v_overall_state,
    'structuralIntegrityPass',
      v_invalid_count=0 and v_active_handoff_state<>'missing',
    'incidentState',v_incident_state,
    'activeIncidentEventId',v_current_event_id,
    'activeIncidentEventAgeSeconds',v_current_event_age,
    'activeIncidentHandoffState',v_active_handoff_state,
    'handoffGraceSeconds',p_handoff_grace_seconds,
    'caseCount',v_case_count,
    'visibleCount',v_visible_count,
    'invalidCount',v_invalid_count,
    'activeCaseCount',v_active_case_count,
    'pendingCaseCount',v_pending_count,
    'terminalCaseCount',v_terminal_count,
    'historicalCaseCount',v_historical_count,
    'hasMore',v_case_count>v_visible_count,
    'cases',v_items,
    'incidentSummary',v_incident,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false,
    'grantsApproval',false,
    'grantsExecutionAuthority',false
  );
end;
$layer72_audit$;

revoke all on function foundation.get_foundation_promoted_release_case_audit_v1(
  text,integer,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_foundation_promoted_release_case_audit_v1(
  text,integer,timestamptz,integer
) to foundation_runtime,service_role;
