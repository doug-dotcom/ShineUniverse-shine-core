-- Foundation Layer 90: governed response policy for Layer-89 incidents.
-- Persistent Layer-88 coverage trouble may justify read-only diagnosis or, only
-- for a pure Layer-87 reconciliation omission, admission of one bounded Layer-87
-- reconciliation. This layer never executes that action and never permits repair,
-- receipt/proof mutation, upstream reruns, incident suppression, or release-truth mutation.

create or replace function foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer90_cause$
declare
  v_incident jsonb;
  v_coverage jsonb;
  v_incident_state text;
  v_coverage_state text;
  v_reason text;
  v_overdue integer := 0;
  v_invalid87 integer := 0;
  v_missing82 integer := 0;
  v_invalid82 integer := 0;
  v_exec_mismatch integer := 0;
  v_policy_drift integer := 0;
  v_incident_drift integer := 0;
  v_coverage_drift integer := 0;
  v_cause text;
  v_domain text;
  v_next text;
begin
  v_incident :=
    foundation.get_case_audit_reconcile_exec_coverage_incident_summary_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds
    );

  v_coverage :=
    foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds,100
    );

  v_incident_state := coalesce(v_incident->>'state','normal');
  v_coverage_state := coalesce(v_coverage->>'state','invalid');
  v_reason := coalesce(
    nullif(v_coverage->>'reasonCode',''),
    'case-audit-layer87-response-cause-unknown'
  );

  v_overdue := coalesce((v_coverage->>'overdueCount')::integer,0);
  v_invalid87 :=
    coalesce((v_coverage->>'invalidLayer87ReconciliationCount')::integer,0);
  v_missing82 :=
    coalesce((v_coverage->>'missingLayer82ReceiptCount')::integer,0);
  v_invalid82 :=
    coalesce((v_coverage->>'invalidLayer82ReceiptCount')::integer,0);
  v_exec_mismatch :=
    coalesce((v_coverage->>'executionReceiptMismatchCount')::integer,0);
  v_policy_drift :=
    coalesce((v_coverage->>'policyDriftCount')::integer,0);
  v_incident_drift :=
    coalesce((v_coverage->>'incidentDriftCount')::integer,0);
  v_coverage_drift :=
    coalesce((v_coverage->>'coverageDriftCount')::integer,0);

  if v_incident_state='normal'
     and v_coverage_state in ('idle','normal','pending') then
    v_cause := 'none';
    v_domain := 'none';
    v_next := 'none';

  elsif v_invalid87>0 or v_coverage_state='invalid' then
    v_cause := 'layer87-receipt-integrity';
    v_domain := 'layer-87-reconciliation-receipt';
    v_next := 'inspect-layer87-reconciliation-receipt';

  elsif v_invalid82>0 then
    v_cause := 'layer82-receipt-integrity';
    v_domain := 'layer-82-reconciliation-receipt';
    v_next := 'inspect-layer82-reconciliation-chain';

  elsif v_exec_mismatch>0 then
    v_cause := 'layer86-execution-receipt-mismatch';
    v_domain := 'layer-86-execution-receipt';
    v_next := 'inspect-layer86-execution-receipt';

  elsif v_policy_drift>0 then
    v_cause := 'layer85-policy-drift';
    v_domain := 'layer-85-response-policy-binding';
    v_next := 'inspect-layer85-policy-binding';

  elsif v_incident_drift>0 then
    v_cause := 'layer84-incident-binding-drift';
    v_domain := 'layer-84-reconciliation-incident-binding';
    v_next := 'inspect-layer84-incident-binding';

  elsif v_coverage_drift>0 then
    v_cause := 'layer83-coverage-binding-drift';
    v_domain := 'layer-83-reconciliation-coverage-binding';
    v_next := 'inspect-layer83-coverage-binding';

  elsif v_missing82>0 then
    v_cause := 'layer82-receipt-missing';
    v_domain := 'layer-82-reconciliation-chain';
    v_next := 'inspect-layer82-reconciliation-chain';

  elsif v_overdue>0 then
    v_cause := 'layer87-reconciliation-omission';
    v_domain := 'layer-87-reconciliation-coverage';
    v_next := 'run-independent-layer87-reconciliation';

  elsif v_coverage_state='gap' then
    v_cause := 'layer87-reconciliation-coverage-gap';
    v_domain := 'layer-88-reconciliation-coverage';
    v_next := 'inspect-layer88-coverage';

  else
    v_cause := 'unknown';
    v_domain := 'layer-88-reconciliation-coverage';
    v_next := 'inspect-layer88-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionCoverageIncidentCause',
      'shine-foundation/case-audit-reconciliation-execution-coverage-incident-cause-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_incident_state,
    'coverageState',v_coverage_state,
    'reasonCode',v_reason,
    'causeClass',v_cause,
    'sourceDomain',v_domain,
    'nextEvidenceAction',v_next,
    'overdueCount',v_overdue,
    'invalidLayer87ReconciliationCount',v_invalid87,
    'missingLayer82ReceiptCount',v_missing82,
    'invalidLayer82ReceiptCount',v_invalid82,
    'executionReceiptMismatchCount',v_exec_mismatch,
    'policyDriftCount',v_policy_drift,
    'incidentDriftCount',v_incident_drift,
    'coverageDriftCount',v_coverage_drift,
    'incidentSummary',v_incident,
    'coverage',v_coverage,
    'authorityExpansion',false,
    'automaticLayer87ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'layer86ReceiptRewriteAllowed',false,
    'layer82ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer90_cause$;

revoke all on function foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
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
as $layer90_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'case-audit-layer87-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer87-response-action-invalid';
  end if;

  v_cause :=
    foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds
    );
  v_incident_state := coalesce(v_cause->>'incidentState','normal');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-layer88-coverage' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer87-response-inspect-layer88-coverage';

  elsif p_action_key='inspect-layer89-incident-state' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer87-response-inspect-layer89-incident';

  elsif p_action_key='inspect-overdue-layer87-reconciliations' then
    v_action_class := 'observe';
    if v_cause_class in (
      'layer87-reconciliation-omission',
      'layer87-reconciliation-coverage-gap'
    ) then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer87-response-inspect-overdue';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-overdue-not-relevant';
    end if;

  elsif p_action_key='inspect-layer87-reconciliation-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer87-receipt-integrity' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer87-response-inspect-layer87-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-layer87-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer82-reconciliation-chain' then
    v_action_class := 'observe';
    if v_cause_class in (
      'layer82-receipt-integrity','layer82-receipt-missing'
    ) then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer87-response-inspect-layer82-chain';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-layer82-chain-not-relevant';
    end if;

  elsif p_action_key='inspect-layer86-execution-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer86-execution-receipt-mismatch' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer87-response-inspect-layer86-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-layer86-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer85-policy-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer85-policy-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer87-response-inspect-layer85-policy';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-layer85-policy-not-relevant';
    end if;

  elsif p_action_key='inspect-layer84-incident-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer84-incident-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer87-response-inspect-layer84-incident';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-layer84-incident-not-relevant';
    end if;

  elsif p_action_key='inspect-layer83-coverage-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer83-coverage-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer87-response-inspect-layer83-coverage';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-layer83-coverage-not-relevant';
    end if;

  elsif p_action_key='run-independent-layer87-reconciliation' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','critical')
       and v_cause_class='layer87-reconciliation-omission' then
      v_decision := 'admit';
      v_required_control := 'layer-87-bounded-reconciler';
      v_reason := 'case-audit-layer87-response-run-bounded-reconciliation';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer87-response-reconciliation-not-relevant';
    end if;

  elsif p_action_key in (
    'rerun-layer86','rerun-layer82','rerun-layer81','rerun-verification',
    'manufacture-layer87-reconciliation','rewrite-layer87-reconciliation',
    'delete-layer87-reconciliation','repair-layer87-ledger',
    'manufacture-layer86-execution-receipt','rewrite-layer86-execution-receipt',
    'manufacture-layer82-reconciliation-receipt',
    'rewrite-layer82-reconciliation-receipt',
    'repair-upstream-evidence',
    'suppress-layer89-coverage-incident',
    'delete-layer89-coverage-incident-history',
    'mutate-release-truth'
  ) then
    v_action_class := case
      when p_action_key='rerun-layer86' then 'layer86-reexecution'
      when p_action_key='rerun-layer82' then 'layer82-reexecution'
      when p_action_key='rerun-layer81' then 'layer81-reexecution'
      when p_action_key='rerun-verification' then 'verification-reexecution'
      when p_action_key in (
        'manufacture-layer87-reconciliation','rewrite-layer87-reconciliation',
        'delete-layer87-reconciliation','repair-layer87-ledger'
      ) then 'layer87-receipt-mutation'
      when p_action_key in (
        'manufacture-layer86-execution-receipt','rewrite-layer86-execution-receipt'
      ) then 'layer86-receipt-mutation'
      when p_action_key in (
        'manufacture-layer82-reconciliation-receipt',
        'rewrite-layer82-reconciliation-receipt'
      ) then 'layer82-receipt-mutation'
      when p_action_key='repair-upstream-evidence' then 'evidence-mutation'
      when p_action_key='mutate-release-truth' then 'authoritative-mutation'
      else 'history-mutation'
    end;
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'case-audit-layer87-response-mutation-or-rerun-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionCoverageIncidentResponseDecision',
      'shine-foundation/case-audit-reconciliation-execution-coverage-incident-response-decision-v1',
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
      'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1',
    'authorityExpansion',false,
    'automaticLayer87ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'layer86ReceiptRewriteAllowed',false,
    'layer82ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',
      coalesce(v_action_class='authoritative-mutation',false),
    'mutatesIncidentHistory',
      coalesce(v_action_class='history-mutation',false),
    'mutatesLayer87Receipt',
      coalesce(v_action_class='layer87-receipt-mutation',false),
    'mutatesLayer86Receipt',
      coalesce(v_action_class='layer86-receipt-mutation',false),
    'mutatesLayer82Receipt',
      coalesce(v_action_class='layer82-receipt-mutation',false),
    'rerunsLayer86',
      coalesce(v_action_class='layer86-reexecution',false),
    'rerunsLayer82',
      coalesce(v_action_class='layer82-reexecution',false),
    'rerunsLayer81',
      coalesce(v_action_class='layer81-reexecution',false),
    'rerunsVerification',
      coalesce(v_action_class='verification-reexecution',false),
    'executesAction',false,
    'cause',v_cause
  );
end;
$layer90_evaluate$;

revoke all on function foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer90_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause :=
    foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(
      p_environment,p_as_of,p_reconciliation_grace_seconds
    );

  select jsonb_agg(
    foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
      action_key,p_environment,p_as_of,p_reconciliation_grace_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-layer88-coverage'),
      (2,'inspect-layer89-incident-state'),
      (3,'inspect-overdue-layer87-reconciliations'),
      (4,'inspect-layer87-reconciliation-receipt'),
      (5,'inspect-layer82-reconciliation-chain'),
      (6,'inspect-layer86-execution-receipt'),
      (7,'inspect-layer85-policy-binding'),
      (8,'inspect-layer84-incident-binding'),
      (9,'inspect-layer83-coverage-binding'),
      (10,'run-independent-layer87-reconciliation'),
      (11,'rerun-layer86'),
      (12,'rerun-layer82'),
      (13,'rerun-layer81'),
      (14,'rerun-verification'),
      (15,'manufacture-layer87-reconciliation'),
      (16,'rewrite-layer87-reconciliation'),
      (17,'delete-layer87-reconciliation'),
      (18,'repair-layer87-ledger'),
      (19,'manufacture-layer86-execution-receipt'),
      (20,'rewrite-layer86-execution-receipt'),
      (21,'manufacture-layer82-reconciliation-receipt'),
      (22,'rewrite-layer82-reconciliation-receipt'),
      (23,'repair-upstream-evidence'),
      (24,'suppress-layer89-coverage-incident'),
      (25,'delete-layer89-coverage-incident-history'),
      (26,'mutate-release-truth')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionCoverageIncidentResponsePlan',
      'shine-foundation/case-audit-reconciliation-execution-coverage-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'coverageState',v_cause->>'coverageState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticLayer87ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'layer86ReceiptRewriteAllowed',false,
    'layer82ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'boundedReconciler',
      'foundation.run_case_audit_verify_reconcile_exec_reconciliation_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer90_plan$;

revoke all on function foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
