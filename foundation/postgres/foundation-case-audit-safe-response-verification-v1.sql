-- Foundation Layer 77: independently verify Layer-76 safe-response execution receipts.
-- An "executed" receipt is not trusted merely because the dispatcher recorded it.
-- Layer 77 resolves the durable target evidence directly and records an immutable
-- verification proof without re-running either Layer-73 or Layer-67 targets.

create table foundation.case_audit_safe_response_verifications (
  verification_sequence bigint generated always as identity
    constraint case_audit_safe_response_verifications_pkey primary key,
  verification_id uuid not null
    constraint case_audit_safe_response_verifications_id_key unique
    default gen_random_uuid(),
  execution_event_id uuid not null
    constraint case_audit_safe_response_verifications_exec_key unique
    references foundation.case_audit_safe_response_exec_events(event_id),
  environment text not null
    constraint case_audit_safe_response_verifications_environment_check
    check (environment ~ '^[a-z0-9][a-z0-9._-]*$'),
  incident_event_id uuid not null
    constraint case_audit_safe_response_verifications_incident_fkey
    references foundation.foundation_promoted_release_case_audit_incident_events(event_id),
  action_key text not null
    constraint case_audit_safe_response_verifications_action_check
    check (
      action_key in (
        'record-fresh-promotion-case-audit-observation',
        'materialise-current-owner-handoff'
      )
    ),
  execution_policy_fingerprint text not null
    constraint case_audit_safe_response_verifications_policy_check
    check (execution_policy_fingerprint ~ '^[a-f0-9]{64}$'),
  verification_state text not null
    constraint case_audit_safe_response_verifications_state_check
    check (verification_state in ('verified','missing','mismatch')),
  reason_code text not null
    constraint case_audit_safe_response_verifications_reason_check
    check (reason_code ~ '^[a-z0-9][a-z0-9._:-]*$'),
  durable_evidence_id uuid,
  durable_evidence_fingerprint text
    constraint case_audit_safe_response_verifications_evidence_fp_check
    check (
      durable_evidence_fingerprint is null
      or durable_evidence_fingerprint ~ '^[a-f0-9]{64}$'
    ),
  durable_evidence_snapshot jsonb
    constraint case_audit_safe_response_verifications_evidence_check
    check (
      durable_evidence_snapshot is null
      or jsonb_typeof(durable_evidence_snapshot)='object'
    ),
  execution_action_result jsonb not null
    constraint case_audit_safe_response_verifications_result_check
    check (jsonb_typeof(execution_action_result)='object'),
  verification_proof jsonb not null
    constraint case_audit_safe_response_verifications_proof_check
    check (jsonb_typeof(verification_proof)='object'),
  verification_proof_sha256 text not null
    constraint case_audit_safe_response_verifications_proof_hash_check
    check (verification_proof_sha256 ~ '^[a-f0-9]{64}$'),
  verified_at timestamptz not null,
  recorded_at timestamptz not null default now()
);

alter table foundation.case_audit_safe_response_verifications
  enable row level security;

create policy foundation_runtime_case_audit_safe_verify_select
on foundation.case_audit_safe_response_verifications
for select
to foundation_runtime
using (true);

revoke all on foundation.case_audit_safe_response_verifications
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime,service_role;
grant select on foundation.case_audit_safe_response_verifications
  to foundation_runtime,service_role;

create index case_audit_safe_verify_incident_idx
  on foundation.case_audit_safe_response_verifications(
    incident_event_id,verified_at desc,verification_sequence desc
  );

create index case_audit_safe_verify_state_idx
  on foundation.case_audit_safe_response_verifications(
    verification_state,verified_at desc,verification_sequence desc
  );

create trigger case_audit_safe_verify_append_only
before update or delete
on foundation.case_audit_safe_response_verifications
for each row execute function foundation.reject_append_only_mutation();


create or replace function foundation.evaluate_case_audit_safe_response_execution_v1(
  p_execution_event_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer77_evaluate$
declare
  v_exec foundation.case_audit_safe_response_exec_events%rowtype;
  v_observation foundation.foundation_promoted_release_case_audit_observations%rowtype;
  v_handoff foundation.foundation_promoted_release_owner_handoffs%rowtype;
  v_evidence_id uuid;
  v_evidence_fingerprint text;
  v_evidence_snapshot jsonb;
  v_recomputed_hash text;
  v_state text;
  v_reason text;
  v_checks jsonb;
begin
  if p_execution_event_id is null then
    raise exception 'case-audit-safe-response-verification-execution-id-required';
  end if;

  select * into v_exec
  from foundation.case_audit_safe_response_exec_events
  where event_id=p_execution_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditSafeResponseExecutionEvaluation',
        'shine-foundation/case-audit-safe-response-execution-evaluation-v1',
      'schemaVersion','1.0.0',
      'status','not-found',
      'executionEventId',p_execution_event_id,
      'verificationState','not-applicable',
      'reasonCode','case-audit-safe-response-execution-not-found',
      'independentDurableEvidenceRead',true,
      'targetReexecuted',false,
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditSafeResponseExecutionEvaluation',
        'shine-foundation/case-audit-safe-response-execution-evaluation-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executionEventId',v_exec.event_id,
      'environment',v_exec.environment,
      'actionKey',v_exec.action_key,
      'sourceExecutionEventType',v_exec.event_type,
      'verificationState','not-applicable',
      'reasonCode','case-audit-safe-response-execution-not-successful',
      'independentDurableEvidenceRead',true,
      'targetReexecuted',false,
      'mutationPerformed',false
    );
  end if;

  if v_exec.action_key='record-fresh-promotion-case-audit-observation' then
    begin
      v_evidence_id := nullif(v_exec.action_result->>'observationId','')::uuid;
    exception when invalid_text_representation then
      v_evidence_id := null;
    end;

    if v_evidence_id is null then
      v_state := 'mismatch';
      v_reason := 'case-audit-safe-response-observation-id-invalid';
      v_checks := jsonb_build_object(
        'actionResultContractValid',
          v_exec.action_result->>'foundationPromotedReleaseCaseAuditObservationRecord'
            ='shine-foundation/promoted-release-case-audit-observation-record-v1',
        'durableEvidenceIdValid',false,
        'durableEvidencePresent',false
      );

    else
      select * into v_observation
      from foundation.foundation_promoted_release_case_audit_observations
      where observation_id=v_evidence_id
        and environment=v_exec.environment;

      if v_observation.observation_id is null then
        v_state := 'missing';
        v_reason := 'case-audit-safe-response-observation-missing';
        v_checks := jsonb_build_object(
          'actionResultContractValid',
            v_exec.action_result->>'foundationPromotedReleaseCaseAuditObservationRecord'
              ='shine-foundation/promoted-release-case-audit-observation-record-v1',
          'durableEvidenceIdValid',true,
          'durableEvidencePresent',false
        );
      else
        v_evidence_fingerprint := v_observation.semantic_fingerprint;
        v_evidence_snapshot := jsonb_build_object(
          'evidenceType','promotion-case-audit-observation',
          'observationId',v_observation.observation_id,
          'environment',v_observation.environment,
          'auditState',v_observation.audit_state,
          'structuralIntegrityPass',v_observation.structural_integrity_pass,
          'semanticFingerprint',v_observation.semantic_fingerprint,
          'changedFromPrevious',v_observation.changed_from_previous,
          'observedAt',v_observation.observed_at
        );

        v_checks := jsonb_build_object(
          'actionResultContractValid',
            v_exec.action_result->>'foundationPromotedReleaseCaseAuditObservationRecord'
              ='shine-foundation/promoted-release-case-audit-observation-record-v1',
          'actionResultStatusValid',
            v_exec.action_result->>'status' in ('recorded-change','recorded-heartbeat'),
          'durableEvidenceIdValid',true,
          'durableEvidencePresent',true,
          'environmentMatches',
            v_observation.environment=v_exec.environment,
          'semanticFingerprintMatches',
            v_exec.action_result->>'semanticFingerprint'
              is not distinct from v_observation.semantic_fingerprint
        );

        if (v_checks->>'actionResultContractValid')::boolean
           and (v_checks->>'actionResultStatusValid')::boolean
           and (v_checks->>'environmentMatches')::boolean
           and (v_checks->>'semanticFingerprintMatches')::boolean then
          v_state := 'verified';
          v_reason := 'case-audit-safe-response-observation-durable';
        else
          v_state := 'mismatch';
          v_reason := 'case-audit-safe-response-observation-mismatch';
        end if;
      end if;
    end if;

  elsif v_exec.action_key='materialise-current-owner-handoff' then
    begin
      v_evidence_id := nullif(v_exec.action_result->>'handoffId','')::uuid;
    exception when invalid_text_representation then
      v_evidence_id := null;
    end;

    if v_evidence_id is null then
      v_state := 'mismatch';
      v_reason := 'case-audit-safe-response-handoff-id-invalid';
      v_checks := jsonb_build_object(
        'actionResultContractValid',
          v_exec.action_result->>'foundationPromotedReleaseOwnerHandoffResponse'
            ='shine-foundation/promoted-release-owner-handoff-response-v1',
        'durableEvidenceIdValid',false,
        'durableEvidencePresent',false
      );

    else
      select * into v_handoff
      from foundation.foundation_promoted_release_owner_handoffs
      where handoff_id=v_evidence_id
        and environment=v_exec.environment;

      if v_handoff.handoff_id is null then
        v_state := 'missing';
        v_reason := 'case-audit-safe-response-handoff-missing';
        v_checks := jsonb_build_object(
          'actionResultContractValid',
            v_exec.action_result->>'foundationPromotedReleaseOwnerHandoffResponse'
              ='shine-foundation/promoted-release-owner-handoff-response-v1',
          'durableEvidenceIdValid',true,
          'durableEvidencePresent',false
        );
      else
        v_recomputed_hash := encode(
          extensions.digest(
            convert_to(v_handoff.handoff::text,'UTF8'),
            'sha256'
          ),
          'hex'
        );
        v_evidence_fingerprint := v_handoff.handoff_sha256;
        v_evidence_snapshot := jsonb_build_object(
          'evidenceType','promoted-release-owner-handoff',
          'handoffId',v_handoff.handoff_id,
          'environment',v_handoff.environment,
          'incidentEventId',v_handoff.incident_event_id,
          'ownerServiceId',v_handoff.owner_service_id,
          'ownerComponent',v_handoff.owner_component,
          'responsePlanFingerprint',v_handoff.response_plan_fingerprint,
          'handoffSha256',v_handoff.handoff_sha256,
          'createdAt',v_handoff.created_at
        );

        v_checks := jsonb_build_object(
          'actionResultContractValid',
            v_exec.action_result->>'foundationPromotedReleaseOwnerHandoffResponse'
              ='shine-foundation/promoted-release-owner-handoff-response-v1',
          'actionResultStatusValid',
            v_exec.action_result->>'status' in ('generated','existing'),
          'durableEvidenceIdValid',true,
          'durableEvidencePresent',true,
          'environmentMatches',
            v_handoff.environment=v_exec.environment,
          'incidentEventIdMatches',
            v_exec.action_result->>'incidentEventId'
              is not distinct from v_handoff.incident_event_id::text,
          'ownerServiceIdMatches',
            v_exec.action_result->>'ownerServiceId'
              is not distinct from v_handoff.owner_service_id,
          'ownerComponentMatches',
            v_exec.action_result->>'ownerComponent'
              is not distinct from v_handoff.owner_component,
          'responsePlanFingerprintMatches',
            v_exec.action_result->>'responsePlanFingerprint'
              is not distinct from v_handoff.response_plan_fingerprint,
          'actionResultHashMatches',
            v_exec.action_result->>'handoffSha256'
              is not distinct from v_handoff.handoff_sha256,
          'storedDocumentHashValid',
            v_recomputed_hash is not distinct from v_handoff.handoff_sha256
        );

        if (v_checks->>'actionResultContractValid')::boolean
           and (v_checks->>'actionResultStatusValid')::boolean
           and (v_checks->>'environmentMatches')::boolean
           and (v_checks->>'incidentEventIdMatches')::boolean
           and (v_checks->>'ownerServiceIdMatches')::boolean
           and (v_checks->>'ownerComponentMatches')::boolean
           and (v_checks->>'responsePlanFingerprintMatches')::boolean
           and (v_checks->>'actionResultHashMatches')::boolean
           and (v_checks->>'storedDocumentHashValid')::boolean then
          v_state := 'verified';
          v_reason := 'case-audit-safe-response-handoff-durable';
        else
          v_state := 'mismatch';
          v_reason := 'case-audit-safe-response-handoff-mismatch';
        end if;
      end if;
    end if;

  else
    v_state := 'mismatch';
    v_reason := 'case-audit-safe-response-action-unsupported';
    v_checks := jsonb_build_object('supportedAction',false);
  end if;

  return jsonb_build_object(
    'foundationCaseAuditSafeResponseExecutionEvaluation',
      'shine-foundation/case-audit-safe-response-execution-evaluation-v1',
    'schemaVersion','1.0.0',
    'status','evaluated',
    'executionEventId',v_exec.event_id,
    'environment',v_exec.environment,
    'incidentEventId',v_exec.incident_event_id,
    'actionKey',v_exec.action_key,
    'sourceExecutionEventType',v_exec.event_type,
    'executionPolicyFingerprint',v_exec.policy_fingerprint,
    'verificationState',v_state,
    'reasonCode',v_reason,
    'durableEvidenceId',v_evidence_id,
    'durableEvidenceFingerprint',v_evidence_fingerprint,
    'checks',v_checks,
    'durableEvidence',v_evidence_snapshot,
    'executionActionResult',v_exec.action_result,
    'independentDurableEvidenceRead',true,
    'targetReexecuted',false,
    'historyRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$layer77_evaluate$;

revoke all on function foundation.evaluate_case_audit_safe_response_execution_v1(uuid)
  from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_safe_response_execution_v1(uuid)
  to foundation_runtime,service_role;


create or replace function foundation.run_case_audit_safe_response_verification_v1(
  p_execution_event_id uuid,
  p_verified_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $layer77_verify$
declare
  v_exec foundation.case_audit_safe_response_exec_events%rowtype;
  v_existing foundation.case_audit_safe_response_verifications%rowtype;
  v_evaluation jsonb;
  v_proof jsonb;
  v_proof_hash text;
  v_verification_id uuid;
  v_evidence_id uuid;
begin
  if p_execution_event_id is null then
    raise exception 'case-audit-safe-response-verification-execution-id-required';
  end if;

  if p_verified_at is null
     or p_verified_at<now()-interval '5 minutes'
     or p_verified_at>now()+interval '5 minutes' then
    raise exception 'case-audit-safe-response-verification-time-invalid';
  end if;

  select * into v_exec
  from foundation.case_audit_safe_response_exec_events
  where event_id=p_execution_event_id;

  if v_exec.event_id is null then
    return jsonb_build_object(
      'foundationCaseAuditSafeResponseVerification',
        'shine-foundation/case-audit-safe-response-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executionEventId',p_execution_event_id,
      'reasonCode','case-audit-safe-response-execution-not-found',
      'targetReexecuted',false,
      'mutationPerformed',false
    );
  end if;

  if v_exec.event_type<>'executed' then
    return jsonb_build_object(
      'foundationCaseAuditSafeResponseVerification',
        'shine-foundation/case-audit-safe-response-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','not-applicable',
      'executionEventId',v_exec.event_id,
      'sourceExecutionEventType',v_exec.event_type,
      'reasonCode','case-audit-safe-response-execution-not-successful',
      'targetReexecuted',false,
      'mutationPerformed',false
    );
  end if;

  select * into v_existing
  from foundation.case_audit_safe_response_verifications
  where execution_event_id=v_exec.event_id;

  if v_existing.verification_id is not null then
    return jsonb_build_object(
      'foundationCaseAuditSafeResponseVerification',
        'shine-foundation/case-audit-safe-response-verification-response-v1',
      'schemaVersion','1.0.0',
      'status','existing',
      'verificationId',v_existing.verification_id,
      'executionEventId',v_existing.execution_event_id,
      'verificationState',v_existing.verification_state,
      'reasonCode',v_existing.reason_code,
      'durableEvidenceId',v_existing.durable_evidence_id,
      'durableEvidenceFingerprint',v_existing.durable_evidence_fingerprint,
      'verificationProofSha256',v_existing.verification_proof_sha256,
      'targetReexecuted',false,
      'mutationPerformed',false
    );
  end if;

  v_evaluation :=
    foundation.evaluate_case_audit_safe_response_execution_v1(
      v_exec.event_id
    );

  if v_evaluation->>'status'<>'evaluated'
     or v_evaluation->>'verificationState'
          not in ('verified','missing','mismatch') then
    raise exception 'case-audit-safe-response-verification-evaluation-invalid';
  end if;

  begin
    v_evidence_id := nullif(v_evaluation->>'durableEvidenceId','')::uuid;
  exception when invalid_text_representation then
    v_evidence_id := null;
  end;

  v_proof := jsonb_build_object(
    'foundationCaseAuditSafeResponseVerificationProof',
      'shine-foundation/case-audit-safe-response-verification-proof-v1',
    'schemaVersion','1.0.0',
    'executionEventId',v_exec.event_id,
    'environment',v_exec.environment,
    'incidentEventId',v_exec.incident_event_id,
    'actionKey',v_exec.action_key,
    'executionPolicyFingerprint',v_exec.policy_fingerprint,
    'executionRequestedAt',v_exec.requested_at,
    'verificationState',v_evaluation->>'verificationState',
    'reasonCode',v_evaluation->>'reasonCode',
    'durableEvidenceId',v_evidence_id,
    'durableEvidenceFingerprint',
      nullif(v_evaluation->>'durableEvidenceFingerprint',''),
    'verificationChecks',v_evaluation->'checks',
    'durableEvidence',v_evaluation->'durableEvidence',
    'executionActionResult',v_exec.action_result,
    'independentDurableEvidenceRead',true,
    'targetReexecuted',false,
    'historyRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'mutationPerformed',false,
    'verifiedAt',p_verified_at
  );

  v_proof_hash := encode(
    extensions.digest(
      convert_to(v_proof::text,'UTF8'),
      'sha256'
    ),
    'hex'
  );

  insert into foundation.case_audit_safe_response_verifications(
    execution_event_id,
    environment,
    incident_event_id,
    action_key,
    execution_policy_fingerprint,
    verification_state,
    reason_code,
    durable_evidence_id,
    durable_evidence_fingerprint,
    durable_evidence_snapshot,
    execution_action_result,
    verification_proof,
    verification_proof_sha256,
    verified_at
  )
  values (
    v_exec.event_id,
    v_exec.environment,
    v_exec.incident_event_id,
    v_exec.action_key,
    v_exec.policy_fingerprint,
    v_evaluation->>'verificationState',
    v_evaluation->>'reasonCode',
    v_evidence_id,
    nullif(v_evaluation->>'durableEvidenceFingerprint',''),
    v_evaluation->'durableEvidence',
    v_exec.action_result,
    v_proof,
    v_proof_hash,
    p_verified_at
  )
  returning verification_id into v_verification_id;

  return jsonb_build_object(
    'foundationCaseAuditSafeResponseVerification',
      'shine-foundation/case-audit-safe-response-verification-response-v1',
    'schemaVersion','1.0.0',
    'status','recorded',
    'verificationId',v_verification_id,
    'executionEventId',v_exec.event_id,
    'verificationState',v_evaluation->>'verificationState',
    'reasonCode',v_evaluation->>'reasonCode',
    'durableEvidenceId',v_evidence_id,
    'durableEvidenceFingerprint',
      nullif(v_evaluation->>'durableEvidenceFingerprint',''),
    'verificationProofSha256',v_proof_hash,
    'independentDurableEvidenceRead',true,
    'targetReexecuted',false,
    'historyRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'approvalGranted',false,
    'executionAuthorityGranted',false,
    'mutationPerformed',false
  );
end;
$layer77_verify$;

revoke all on function foundation.run_case_audit_safe_response_verification_v1(
  uuid,timestamptz
) from public,anon,authenticated,foundation_runtime,foundation_gateway,
       shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.run_case_audit_safe_response_verification_v1(
  uuid,timestamptz
) to service_role;


create or replace function foundation.get_case_audit_safe_response_verification_summary_v1(
  p_environment text default 'production',
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer77_summary$
declare
  v_items jsonb := '[]'::jsonb;
  v_total integer := 0;
  v_verified integer := 0;
  v_missing integer := 0;
  v_mismatch integer := 0;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_limit is null
     or p_limit<1
     or p_limit>100 then
    raise exception 'case-audit-safe-response-verification-summary-input-invalid';
  end if;

  select
    count(*),
    count(*) filter (where verification_state='verified'),
    count(*) filter (where verification_state='missing'),
    count(*) filter (where verification_state='mismatch')
  into v_total,v_verified,v_missing,v_mismatch
  from foundation.case_audit_safe_response_verifications
  where environment=p_environment;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'verificationId',x.verification_id,
        'executionEventId',x.execution_event_id,
        'incidentEventId',x.incident_event_id,
        'actionKey',x.action_key,
        'verificationState',x.verification_state,
        'reasonCode',x.reason_code,
        'durableEvidenceId',x.durable_evidence_id,
        'durableEvidenceFingerprint',x.durable_evidence_fingerprint,
        'verificationProofSha256',x.verification_proof_sha256,
        'verifiedAt',x.verified_at
      )
      order by x.verification_sequence desc
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select *
    from foundation.case_audit_safe_response_verifications
    where environment=p_environment
    order by verification_sequence desc
    limit p_limit
  ) x;

  return jsonb_build_object(
    'foundationCaseAuditSafeResponseVerificationSummary',
      'shine-foundation/case-audit-safe-response-verification-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'totalCount',v_total,
    'verifiedCount',v_verified,
    'missingCount',v_missing,
    'mismatchCount',v_mismatch,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',v_total>jsonb_array_length(v_items),
    'items',v_items,
    'independentDurableEvidenceRead',true,
    'targetReexecuted',false,
    'mutationPerformed',false
  );
end;
$layer77_summary$;

revoke all on function foundation.get_case_audit_safe_response_verification_summary_v1(
  text,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_safe_response_verification_summary_v1(
  text,integer
) to foundation_runtime,service_role;
