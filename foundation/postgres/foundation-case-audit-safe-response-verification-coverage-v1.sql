-- Foundation Layer 78: verification coverage audit for Layer-76/77.
-- A successful Layer-76 execution is not considered covered until it has one
-- immutable Layer-77 verification proof. This audit is read-only and distinguishes
-- grace-period pending work from overdue gaps, explicit evidence failures, and
-- structurally invalid verification proofs.

create or replace function foundation.get_case_audit_safe_response_verification_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer78_coverage$
declare
  v_result jsonb;
begin
  if p_environment is null
     or p_environment !~ '^[a-z0-9][a-z0-9._-]*$'
     or p_as_of is null
     or p_verification_grace_seconds is null
     or p_verification_grace_seconds<60
     or p_verification_grace_seconds>3600
     or p_limit is null
     or p_limit<1
     or p_limit>100 then
    raise exception 'case-audit-safe-response-verification-coverage-input-invalid';
  end if;

  with executed as (
    select
      e.event_sequence,
      e.event_id,
      e.environment,
      e.incident_event_id,
      e.action_key,
      e.policy_fingerprint,
      e.action_result,
      e.requested_at,
      greatest(
        0,
        floor(extract(epoch from (p_as_of-e.requested_at)))::integer
      ) as age_seconds,
      v.verification_id,
      v.verification_state,
      v.reason_code as verification_reason_code,
      v.durable_evidence_id,
      v.durable_evidence_fingerprint,
      v.execution_action_result,
      v.verification_proof,
      v.verification_proof_sha256,
      v.verified_at
    from foundation.case_audit_safe_response_exec_events e
    left join foundation.case_audit_safe_response_verifications v
      on v.execution_event_id=e.event_id
    where e.environment=p_environment
      and e.event_type='executed'
      and e.requested_at<=p_as_of
  ),
  inspected as (
    select
      x.*,
      case
        when x.verification_id is null then null
        else
          encode(
            extensions.digest(
              convert_to(x.verification_proof::text,'UTF8'),
              'sha256'
            ),
            'hex'
          ) is not distinct from x.verification_proof_sha256
          and x.execution_action_result is not distinct from x.action_result
          and x.verification_proof->>'executionEventId'
                is not distinct from x.event_id::text
          and x.verification_proof->>'environment'
                is not distinct from x.environment
          and x.verification_proof->>'incidentEventId'
                is not distinct from x.incident_event_id::text
          and x.verification_proof->>'actionKey'
                is not distinct from x.action_key
          and x.verification_proof->>'executionPolicyFingerprint'
                is not distinct from x.policy_fingerprint
          and x.verification_proof->>'verificationState'
                is not distinct from x.verification_state
          and x.verification_proof->>'reasonCode'
                is not distinct from x.verification_reason_code
          and x.verification_proof->>'durableEvidenceId'
                is not distinct from x.durable_evidence_id::text
          and x.verification_proof->>'durableEvidenceFingerprint'
                is not distinct from x.durable_evidence_fingerprint
          and x.verification_proof->>'foundationCaseAuditSafeResponseVerificationProof'
                is not distinct from
                'shine-foundation/case-audit-safe-response-verification-proof-v1'
          and x.verification_proof->>'schemaVersion'
                is not distinct from '1.0.0'
          and x.verification_proof->'independentDurableEvidenceRead'
                = 'true'::jsonb
          and x.verification_proof->'targetReexecuted'
                = 'false'::jsonb
          and x.verification_proof->'historyRewritePerformed'
                = 'false'::jsonb
          and x.verification_proof->'releaseTruthMutationPerformed'
                = 'false'::jsonb
          and x.verification_proof->'incidentHistoryMutationPerformed'
                = 'false'::jsonb
          and x.verification_proof->'approvalGranted'
                = 'false'::jsonb
          and x.verification_proof->'executionAuthorityGranted'
                = 'false'::jsonb
          and x.verification_proof->'mutationPerformed'
                = 'false'::jsonb
      end as proof_integrity_verified
    from executed x
  ),
  classified as (
    select
      x.*,
      case
        when x.verification_id is null
             and x.age_seconds<=p_verification_grace_seconds
          then 'pending'
        when x.verification_id is null
          then 'unverified'
        when coalesce(x.proof_integrity_verified,false)=false
          then 'invalid'
        when x.verification_state='verified'
          then 'verified'
        when x.verification_state='missing'
          then 'missing'
        when x.verification_state='mismatch'
          then 'mismatch'
        else 'invalid'
      end as coverage_state,
      case
        when x.verification_id is null
             and x.age_seconds<=p_verification_grace_seconds
          then 'case-audit-safe-response-verification-within-grace'
        when x.verification_id is null
          then 'case-audit-safe-response-verification-overdue'
        when coalesce(x.proof_integrity_verified,false)=false
          then 'case-audit-safe-response-verification-proof-invalid'
        when x.verification_state='verified'
          then 'case-audit-safe-response-verification-covered'
        when x.verification_state='missing'
          then 'case-audit-safe-response-durable-evidence-missing'
        when x.verification_state='mismatch'
          then 'case-audit-safe-response-durable-evidence-mismatch'
        else 'case-audit-safe-response-verification-state-invalid'
      end as coverage_reason_code
    from inspected x
  ),
  totals as (
    select
      count(*)::integer as execution_count,
      count(*) filter (where coverage_state='verified')::integer as verified_count,
      count(*) filter (where coverage_state='pending')::integer as pending_count,
      count(*) filter (where coverage_state='unverified')::integer as unverified_count,
      count(*) filter (where coverage_state='missing')::integer as missing_count,
      count(*) filter (where coverage_state='mismatch')::integer as mismatch_count,
      count(*) filter (where coverage_state='invalid')::integer as invalid_count,
      count(*) filter (where verification_id is not null)::integer as verification_proof_count
    from classified
  ),
  visible as (
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'executionEventId',q.event_id,
          'incidentEventId',q.incident_event_id,
          'actionKey',q.action_key,
          'executionPolicyFingerprint',q.policy_fingerprint,
          'executionRequestedAt',q.requested_at,
          'executionAgeSeconds',q.age_seconds,
          'coverageState',q.coverage_state,
          'reasonCode',q.coverage_reason_code,
          'verificationId',q.verification_id,
          'verificationState',q.verification_state,
          'verificationReasonCode',q.verification_reason_code,
          'proofIntegrityVerified',q.proof_integrity_verified,
          'durableEvidenceId',q.durable_evidence_id,
          'durableEvidenceFingerprint',q.durable_evidence_fingerprint,
          'verifiedAt',q.verified_at
        )
        order by q.event_sequence desc
      ),
      '[]'::jsonb
    ) as items
    from (
      select *
      from classified
      order by event_sequence desc
      limit p_limit
    ) q
  )
  select jsonb_build_object(
    'foundationCaseAuditSafeResponseVerificationCoverage',
      'shine-foundation/case-audit-safe-response-verification-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'verificationGraceSeconds',p_verification_grace_seconds,
    'state',case
      when t.execution_count=0 then 'idle'
      when t.invalid_count>0 then 'invalid'
      when t.unverified_count>0
        or t.missing_count>0
        or t.mismatch_count>0 then 'gap'
      when t.pending_count>0 then 'pending'
      else 'normal'
    end,
    'reasonCode',case
      when t.execution_count=0
        then 'case-audit-safe-response-verification-no-executions'
      when t.invalid_count>0
        then 'case-audit-safe-response-verification-proof-invalid'
      when t.unverified_count>0
        then 'case-audit-safe-response-verification-overdue'
      when t.missing_count>0
        then 'case-audit-safe-response-durable-evidence-missing'
      when t.mismatch_count>0
        then 'case-audit-safe-response-durable-evidence-mismatch'
      when t.pending_count>0
        then 'case-audit-safe-response-verification-within-grace'
      else 'case-audit-safe-response-verification-covered'
    end,
    'executionCount',t.execution_count,
    'verificationRequiredCount',t.execution_count,
    'verificationProofCount',t.verification_proof_count,
    'verifiedCount',t.verified_count,
    'pendingCount',t.pending_count,
    'unverifiedCount',t.unverified_count,
    'missingEvidenceCount',t.missing_count,
    'mismatchCount',t.mismatch_count,
    'invalidProofCount',t.invalid_count,
    'problemCount',
      t.unverified_count+t.missing_count+t.mismatch_count+t.invalid_count,
    'verificationCoveragePercent',case
      when t.execution_count=0 then 100.00
      else round(
        (100.0*t.verification_proof_count/t.execution_count)::numeric,
        2
      )
    end,
    'healthyVerificationPercent',case
      when t.execution_count=0 then 100.00
      else round(
        (100.0*t.verified_count/t.execution_count)::numeric,
        2
      )
    end,
    'visibleCount',jsonb_array_length(v.items),
    'hasMore',t.execution_count>jsonb_array_length(v.items),
    'items',v.items,
    'onlyExecutedReceiptsRequireVerification',true,
    'proofIntegrityRecomputed',true,
    'targetReexecuted',false,
    'historyRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  )
  into v_result
  from totals t
  cross join visible v;

  return v_result;
end;
$layer78_coverage$;

revoke all on function foundation.get_case_audit_safe_response_verification_coverage_v1(
  text,timestamptz,integer,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_safe_response_verification_coverage_v1(
  text,timestamptz,integer,integer
) to foundation_runtime,service_role;
