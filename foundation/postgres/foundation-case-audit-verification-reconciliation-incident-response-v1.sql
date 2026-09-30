-- Foundation Layer 85: governed response policy for Layer-84 reconciliation-coverage incidents.
-- A reconciliation-coverage incident may justify read-only diagnosis or, only
-- for a pure reconciliation omission, admission of one bounded Layer-82
-- reconciliation. This layer never executes that action and never permits
-- proof/receipt repair, upstream reruns, incident suppression, or release-truth mutation.

create or replace function foundation.get_case_audit_verify_reconcile_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer85_cause$
declare
  v_incident jsonb;
  v_coverage jsonb;
  v_incident_state text;
  v_coverage_state text;
  v_reason text;
  v_overdue integer := 0;
  v_invalid_reconciliation integer := 0;
  v_missing_proof integer := 0;
  v_receipt_mismatch integer := 0;
  v_invalid_proof integer := 0;
  v_evidence_drift integer := 0;
  v_coverage_drift integer := 0;
  v_cause_class text;
  v_source_domain text;
  v_next_evidence text;
begin
  v_incident :=
    foundation.get_case_audit_verify_reconcile_incident_summary_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds
    );

  v_coverage :=
    foundation.get_case_audit_verify_reconcile_coverage_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds,100
    );

  v_incident_state := coalesce(v_incident->>'state','normal');
  v_coverage_state := coalesce(v_coverage->>'state','invalid');
  v_reason := coalesce(
    nullif(v_coverage->>'reasonCode',''),
    'case-audit-reconciliation-response-cause-unknown'
  );

  v_overdue := coalesce((v_coverage->>'overdueCount')::integer,0);
  v_invalid_reconciliation :=
    coalesce((v_coverage->>'invalidReconciliationCount')::integer,0);
  v_missing_proof := coalesce((v_coverage->>'missingProofCount')::integer,0);
  v_receipt_mismatch :=
    coalesce((v_coverage->>'receiptMismatchCount')::integer,0);
  v_invalid_proof := coalesce((v_coverage->>'invalidProofCount')::integer,0);
  v_evidence_drift := coalesce((v_coverage->>'evidenceDriftCount')::integer,0);
  v_coverage_drift := coalesce((v_coverage->>'coverageDriftCount')::integer,0);

  if v_incident_state='normal'
     and v_coverage_state in ('idle','normal','pending') then
    v_cause_class := 'none';
    v_source_domain := 'none';
    v_next_evidence := 'none';

  elsif v_invalid_reconciliation>0 or v_coverage_state='invalid' then
    v_cause_class := 'reconciliation-receipt-integrity';
    v_source_domain := 'layer-82-reconciliation-receipt';
    v_next_evidence := 'inspect-reconciliation-receipt';

  elsif v_invalid_proof>0 then
    v_cause_class := 'verification-proof-integrity';
    v_source_domain := 'layer-77-verification-proof';
    v_next_evidence := 'inspect-verification-chain';

  elsif v_receipt_mismatch>0 then
    v_cause_class := 'executor-receipt-mismatch';
    v_source_domain := 'layer-81-executor-receipt';
    v_next_evidence := 'inspect-executor-receipt';

  elsif v_missing_proof>0 then
    v_cause_class := 'verification-proof-missing';
    v_source_domain := 'layer-77-verification-proof';
    v_next_evidence := 'inspect-verification-chain';

  elsif v_evidence_drift>0 then
    v_cause_class := 'durable-evidence-drift';
    v_source_domain := 'layer-73-or-67-durable-evidence';
    v_next_evidence := 'inspect-durable-evidence-chain';

  elsif v_coverage_drift>0 then
    v_cause_class := 'verification-coverage-drift';
    v_source_domain := 'layer-78-verification-coverage';
    v_next_evidence := 'inspect-verification-coverage';

  elsif v_overdue>0 then
    v_cause_class := 'reconciliation-omission';
    v_source_domain := 'layer-82-reconciliation-coverage';
    v_next_evidence := 'run-independent-reconciliation';

  elsif v_coverage_state='gap' then
    v_cause_class := 'reconciliation-coverage-gap';
    v_source_domain := 'layer-83-reconciliation-coverage';
    v_next_evidence := 'inspect-reconciliation-coverage';

  else
    v_cause_class := 'unknown';
    v_source_domain := 'reconciliation-coverage';
    v_next_evidence := 'inspect-reconciliation-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationIncidentCause',
      'shine-foundation/case-audit-verification-reconciliation-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'coverageState',v_coverage_state,
    'reasonCode',v_reason,
    'causeClass',v_cause_class,
    'sourceDomain',v_source_domain,
    'nextEvidenceAction',v_next_evidence,
    'overdueCount',v_overdue,
    'invalidReconciliationCount',v_invalid_reconciliation,
    'missingProofCount',v_missing_proof,
    'receiptMismatchCount',v_receipt_mismatch,
    'invalidProofCount',v_invalid_proof,
    'evidenceDriftCount',v_evidence_drift,
    'coverageDriftCount',v_coverage_drift,
    'incidentSummary',v_incident,
    'coverage',v_coverage,
    'authorityExpansion',false,
    'automaticReconciliationAllowed',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'reconciliationReceiptRewriteAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer85_cause$;

revoke all on function foundation.get_case_audit_verify_reconcile_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_reconcile_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
  p_action_key text,
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer85_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'case-audit-reconciliation-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-reconciliation-response-action-invalid';
  end if;

  v_cause :=
    foundation.get_case_audit_verify_reconcile_incident_cause_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds
    );

  v_incident_state := coalesce(v_cause->>'incidentState','normal');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-reconciliation-coverage' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-reconciliation-response-inspect-coverage';

  elsif p_action_key='inspect-overdue-reconciliations' then
    v_action_class := 'observe';
    if v_cause_class in ('reconciliation-omission','reconciliation-coverage-gap') then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-reconciliation-response-inspect-overdue';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-reconciliation-response-overdue-inspection-not-relevant';
    end if;

  elsif p_action_key='inspect-reconciliation-receipt' then
    v_action_class := 'observe';
    if v_cause_class='reconciliation-receipt-integrity' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-reconciliation-response-inspect-reconciliation-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-reconciliation-response-receipt-inspection-not-relevant';
    end if;

  elsif p_action_key='inspect-executor-receipt' then
    v_action_class := 'observe';
    if v_cause_class='executor-receipt-mismatch' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-reconciliation-response-inspect-executor-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-reconciliation-response-executor-inspection-not-relevant';
    end if;

  elsif p_action_key='inspect-verification-chain' then
    v_action_class := 'observe';
    if v_cause_class in ('verification-proof-missing','verification-proof-integrity') then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-reconciliation-response-inspect-verification-chain';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-reconciliation-response-verification-inspection-not-relevant';
    end if;

  elsif p_action_key='inspect-durable-evidence-chain' then
    v_action_class := 'observe';
    if v_cause_class='durable-evidence-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-reconciliation-response-inspect-durable-evidence';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-reconciliation-response-durable-evidence-inspection-not-relevant';
    end if;

  elsif p_action_key='inspect-verification-coverage' then
    v_action_class := 'observe';
    if v_cause_class='verification-coverage-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-reconciliation-response-inspect-verification-coverage';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-reconciliation-response-verification-coverage-inspection-not-relevant';
    end if;

  elsif p_action_key='run-independent-reconciliation' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','critical')
       and v_cause_class='reconciliation-omission' then
      v_decision := 'admit';
      v_required_control := 'layer-82-bounded-reconciler';
      v_reason := 'case-audit-reconciliation-response-run-bounded-reconciliation';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-reconciliation-response-reconciliation-not-relevant';
    end if;

  elsif p_action_key in (
    'rerun-layer81',
    'rerun-verification',
    'manufacture-reconciliation-receipt',
    'rewrite-reconciliation-receipt',
    'delete-reconciliation-receipt',
    'repair-reconciliation-ledger',
    'manufacture-verification-proof',
    'rewrite-verification-proof',
    'delete-verification-proof',
    'repair-durable-evidence',
    'suppress-reconciliation-coverage-incident',
    'delete-reconciliation-coverage-incident-history',
    'mutate-release-truth'
  ) then
    v_action_class := case
      when p_action_key='rerun-layer81' then 'reexecution'
      when p_action_key='rerun-verification' then 'verification-reexecution'
      when p_action_key in (
        'manufacture-reconciliation-receipt',
        'rewrite-reconciliation-receipt',
        'delete-reconciliation-receipt',
        'repair-reconciliation-ledger'
      ) then 'reconciliation-receipt-mutation'
      when p_action_key in (
        'manufacture-verification-proof',
        'rewrite-verification-proof',
        'delete-verification-proof'
      ) then 'verification-proof-mutation'
      when p_action_key='repair-durable-evidence' then 'evidence-mutation'
      when p_action_key='mutate-release-truth' then 'authoritative-mutation'
      else 'history-mutation'
    end;
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'case-audit-reconciliation-response-mutation-or-rerun-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationIncidentResponseDecision',
      'shine-foundation/case-audit-verification-reconciliation-incident-response-decision-v1',
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
    'boundedReconciler',
      'foundation.run_case_audit_verify_exec_reconciliation_v1',
    'authorityExpansion',false,
    'automaticReconciliationAllowed',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'reconciliationReceiptRewriteAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',
      coalesce(v_action_class='authoritative-mutation',false),
    'mutatesIncidentHistory',
      coalesce(v_action_class='history-mutation',false),
    'mutatesReconciliationReceipt',
      coalesce(v_action_class='reconciliation-receipt-mutation',false),
    'mutatesVerificationProof',
      coalesce(v_action_class='verification-proof-mutation',false),
    'rerunsLayer81',
      coalesce(v_action_class='reexecution',false),
    'rerunsVerification',
      coalesce(v_action_class='verification-reexecution',false),
    'executesAction',false,
    'cause',v_cause
  );
end;
$layer85_evaluate$;

revoke all on function foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer85_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause :=
    foundation.get_case_audit_verify_reconcile_incident_cause_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds
    );

  select jsonb_agg(
    foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
      action_key,p_environment,p_as_of,p_reconciliation_grace_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-reconciliation-coverage'),
      (2,'inspect-overdue-reconciliations'),
      (3,'inspect-reconciliation-receipt'),
      (4,'inspect-executor-receipt'),
      (5,'inspect-verification-chain'),
      (6,'inspect-durable-evidence-chain'),
      (7,'inspect-verification-coverage'),
      (8,'run-independent-reconciliation'),
      (9,'rerun-layer81'),
      (10,'rerun-verification'),
      (11,'manufacture-reconciliation-receipt'),
      (12,'rewrite-reconciliation-receipt'),
      (13,'delete-reconciliation-receipt'),
      (14,'repair-reconciliation-ledger'),
      (15,'manufacture-verification-proof'),
      (16,'rewrite-verification-proof'),
      (17,'delete-verification-proof'),
      (18,'repair-durable-evidence'),
      (19,'suppress-reconciliation-coverage-incident'),
      (20,'delete-reconciliation-coverage-incident-history'),
      (21,'mutate-release-truth')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationIncidentResponsePlan',
      'shine-foundation/case-audit-verification-reconciliation-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'coverageState',v_cause->>'coverageState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticReconciliationAllowed',false,
    'automaticVerificationAllowed',false,
    'automaticRepairAllowed',false,
    'reconciliationReceiptRewriteAllowed',false,
    'verificationProofRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'boundedReconciler',
      'foundation.run_case_audit_verify_exec_reconciliation_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer85_plan$;

revoke all on function foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
