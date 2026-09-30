-- Foundation Layer 80: governed response policy for Layer-79 verification-coverage incidents.
-- A verification-coverage incident may justify diagnosis or a bounded Layer-77
-- verification attempt for an overdue unverified execution. It never grants
-- permission to rerun Layer 76, manufacture evidence, rewrite verification
-- proofs, suppress incident history, or mutate authoritative release truth.

create or replace function foundation.get_case_audit_verify_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer80_cause$
declare
  v_incident jsonb;
  v_coverage jsonb;
  v_incident_state text;
  v_coverage_state text;
  v_reason text;
  v_unverified integer := 0;
  v_missing integer := 0;
  v_mismatch integer := 0;
  v_invalid integer := 0;
  v_cause_class text;
  v_source_domain text;
  v_next_evidence text;
begin
  v_incident :=
    foundation.get_case_audit_verify_incident_summary_v1(
      p_environment,p_as_of,p_verification_grace_seconds
    );

  v_coverage :=
    foundation.get_case_audit_safe_response_verification_coverage_v1(
      p_environment,p_as_of,p_verification_grace_seconds,100
    );

  v_incident_state := coalesce(v_incident->>'state','normal');
  v_coverage_state := coalesce(v_coverage->>'state','invalid');
  v_reason := coalesce(
    nullif(v_coverage->>'reasonCode',''),
    'case-audit-verification-response-cause-unknown'
  );
  v_unverified := coalesce((v_coverage->>'unverifiedCount')::integer,0);
  v_missing := coalesce((v_coverage->>'missingEvidenceCount')::integer,0);
  v_mismatch := coalesce((v_coverage->>'mismatchCount')::integer,0);
  v_invalid := coalesce((v_coverage->>'invalidProofCount')::integer,0);

  if v_incident_state='normal'
     and v_coverage_state in ('idle','normal','pending') then
    v_cause_class := 'none';
    v_source_domain := 'none';
    v_next_evidence := 'none';

  elsif v_invalid>0 or v_coverage_state='invalid' then
    v_cause_class := 'verification-proof-integrity';
    v_source_domain := 'layer-77-verification-proof';
    v_next_evidence := 'inspect-verification-proof';

  elsif v_unverified>0 then
    v_cause_class := 'verification-omission';
    v_source_domain := 'layer-77-verification-coverage';
    v_next_evidence := 'run-independent-verification';

  elsif v_missing>0 then
    v_cause_class := 'durable-evidence-missing';
    v_source_domain := 'layer-76-durable-evidence';
    v_next_evidence := 'inspect-durable-evidence-chain';

  elsif v_mismatch>0 then
    v_cause_class := 'durable-evidence-mismatch';
    v_source_domain := 'layer-76-durable-evidence';
    v_next_evidence := 'inspect-durable-evidence-chain';

  elsif v_coverage_state='gap' then
    v_cause_class := 'verification-coverage-gap';
    v_source_domain := 'layer-77-verification-coverage';
    v_next_evidence := 'inspect-verification-coverage';

  else
    v_cause_class := 'unknown';
    v_source_domain := 'verification-coverage';
    v_next_evidence := 'inspect-verification-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditVerificationIncidentCause',
      'shine-foundation/case-audit-verification-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'coverageState',v_coverage_state,
    'reasonCode',v_reason,
    'causeClass',v_cause_class,
    'sourceDomain',v_source_domain,
    'nextEvidenceAction',v_next_evidence,
    'unverifiedCount',v_unverified,
    'missingEvidenceCount',v_missing,
    'mismatchCount',v_mismatch,
    'invalidProofCount',v_invalid,
    'incidentSummary',v_incident,
    'coverage',v_coverage,
    'authorityExpansion',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer80_cause$;

revoke all on function foundation.get_case_audit_verify_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_verify_incident_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer80_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'case-audit-verification-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-verification-response-action-invalid';
  end if;

  v_cause :=
    foundation.get_case_audit_verify_incident_cause_v1(
      p_environment,p_as_of,p_verification_grace_seconds
    );

  v_incident_state := coalesce(v_cause->>'incidentState','normal');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-verification-coverage' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-verification-response-inspect-coverage';

  elsif p_action_key='inspect-unverified-executions' then
    v_action_class := 'observe';
    if v_cause_class in ('verification-omission','verification-coverage-gap') then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-verification-response-inspect-unverified';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-verification-response-unverified-inspection-not-relevant';
    end if;

  elsif p_action_key='inspect-durable-evidence-chain' then
    v_action_class := 'observe';
    if v_cause_class in (
      'durable-evidence-missing','durable-evidence-mismatch'
    ) then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-verification-response-inspect-durable-evidence';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-verification-response-durable-evidence-inspection-not-relevant';
    end if;

  elsif p_action_key='inspect-verification-proof' then
    v_action_class := 'observe';
    if v_cause_class='verification-proof-integrity' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-verification-response-inspect-proof';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-verification-response-proof-inspection-not-relevant';
    end if;

  elsif p_action_key='run-independent-verification' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','critical')
       and v_cause_class='verification-omission' then
      v_decision := 'admit';
      v_required_control := 'layer-77-bounded-verifier';
      v_reason := 'case-audit-verification-response-run-bounded-verification';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-verification-response-verification-not-relevant';
    end if;

  elsif p_action_key in (
    'rerun-safe-response',
    'manufacture-durable-evidence',
    'repair-durable-evidence',
    'rewrite-verification-proof',
    'delete-verification-proof',
    'repair-verification-ledger',
    'suppress-verification-coverage-incident',
    'delete-verification-coverage-incident-history',
    'mutate-release-truth'
  ) then
    v_action_class := case
      when p_action_key='rerun-safe-response' then 'reexecution'
      when p_action_key in ('manufacture-durable-evidence','repair-durable-evidence')
        then 'evidence-mutation'
      when p_action_key in (
        'rewrite-verification-proof','delete-verification-proof',
        'repair-verification-ledger'
      ) then 'verification-proof-mutation'
      when p_action_key='mutate-release-truth' then 'authoritative-mutation'
      else 'history-mutation'
    end;
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'case-audit-verification-response-mutation-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationCaseAuditVerificationIncidentResponseDecision',
      'shine-foundation/case-audit-verification-incident-response-decision-v1',
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
    'boundedVerifier',
      'foundation.run_case_audit_safe_response_verification_v1',
    'authorityExpansion',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',
      coalesce(v_action_class='history-mutation',false),
    'mutatesVerificationProof',
      coalesce(v_action_class='verification-proof-mutation',false),
    'rerunsSafeResponse',
      coalesce(v_action_class='reexecution',false),
    'executesAction',false,
    'cause',v_cause
  );
end;
$layer80_evaluate$;

revoke all on function foundation.evaluate_case_audit_verify_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_verify_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_case_audit_verify_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer80_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause :=
    foundation.get_case_audit_verify_incident_cause_v1(
      p_environment,p_as_of,p_verification_grace_seconds
    );

  select jsonb_agg(
    foundation.evaluate_case_audit_verify_incident_response_v1(
      action_key,p_environment,p_as_of,p_verification_grace_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-verification-coverage'),
      (2,'inspect-unverified-executions'),
      (3,'inspect-durable-evidence-chain'),
      (4,'inspect-verification-proof'),
      (5,'run-independent-verification'),
      (6,'rerun-safe-response'),
      (7,'manufacture-durable-evidence'),
      (8,'repair-durable-evidence'),
      (9,'rewrite-verification-proof'),
      (10,'delete-verification-proof'),
      (11,'repair-verification-ledger'),
      (12,'suppress-verification-coverage-incident'),
      (13,'delete-verification-coverage-incident-history'),
      (14,'mutate-release-truth')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationCaseAuditVerificationIncidentResponsePlan',
      'shine-foundation/case-audit-verification-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'coverageState',v_cause->>'coverageState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'boundedVerifier',
      'foundation.run_case_audit_safe_response_verification_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer80_plan$;

revoke all on function foundation.get_case_audit_verify_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,shine_core_control_plane,shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
