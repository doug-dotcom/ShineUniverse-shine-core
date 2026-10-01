-- Foundation Layer 95: governed response policy for Layer-94 incidents.
-- Persistent Layer-93 coverage trouble may justify read-only diagnosis or, only
-- for a pure Layer-92 reconciliation omission, admission of one bounded Layer-92
-- reconciliation. This layer never executes that action and never permits repair,
-- receipt mutation, upstream reruns, incident suppression, or release-truth mutation.

create or replace function foundation.get_case_audit_layer92_coverage_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer95_cause$
declare
  v_incident jsonb;
  v_coverage jsonb;
  v_incident_state text;
  v_coverage_state text;
  v_reason text;
  v_overdue integer := 0;
  v_invalid92 integer := 0;
  v_missing87 integer := 0;
  v_invalid87 integer := 0;
  v_exec_mismatch integer := 0;
  v_policy_drift integer := 0;
  v_incident_drift integer := 0;
  v_coverage_drift integer := 0;
  v_cause text;
  v_domain text;
  v_next text;
begin
  v_incident := foundation.get_case_audit_layer92_coverage_incident_summary_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage := foundation.get_case_audit_layer92_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds,100
  );

  v_incident_state := coalesce(v_incident->>'state','normal');
  v_coverage_state := coalesce(v_coverage->>'state','invalid');
  v_reason := coalesce(
    nullif(v_coverage->>'reasonCode',''),
    'case-audit-layer92-response-cause-unknown'
  );

  v_overdue := coalesce((v_coverage->>'overdueCount')::integer,0);
  v_invalid92 :=
    coalesce((v_coverage->>'invalidLayer92ReconciliationCount')::integer,0);
  v_missing87 :=
    coalesce((v_coverage->>'missingLayer87ReceiptCount')::integer,0);
  v_invalid87 :=
    coalesce((v_coverage->>'invalidLayer87ReceiptCount')::integer,0);
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

  elsif v_invalid92>0 or v_coverage_state='invalid' then
    v_cause := 'layer92-receipt-integrity';
    v_domain := 'layer-92-reconciliation-receipt';
    v_next := 'inspect-layer92-reconciliation-receipt';

  elsif v_invalid87>0 then
    v_cause := 'layer87-receipt-integrity';
    v_domain := 'layer-87-reconciliation-receipt';
    v_next := 'inspect-layer87-reconciliation-chain';

  elsif v_exec_mismatch>0 then
    v_cause := 'layer91-execution-receipt-mismatch';
    v_domain := 'layer-91-execution-receipt';
    v_next := 'inspect-layer91-execution-receipt';

  elsif v_policy_drift>0 then
    v_cause := 'layer90-policy-drift';
    v_domain := 'layer-90-response-policy-binding';
    v_next := 'inspect-layer90-policy-binding';

  elsif v_incident_drift>0 then
    v_cause := 'layer89-incident-binding-drift';
    v_domain := 'layer-89-coverage-incident-binding';
    v_next := 'inspect-layer89-incident-binding';

  elsif v_coverage_drift>0 then
    v_cause := 'layer88-coverage-binding-drift';
    v_domain := 'layer-88-reconciliation-coverage-binding';
    v_next := 'inspect-layer88-coverage-binding';

  elsif v_missing87>0 then
    v_cause := 'layer87-receipt-missing';
    v_domain := 'layer-87-reconciliation-chain';
    v_next := 'inspect-layer87-reconciliation-chain';

  elsif v_overdue>0 then
    v_cause := 'layer92-reconciliation-omission';
    v_domain := 'layer-92-reconciliation-coverage';
    v_next := 'run-independent-layer92-reconciliation';

  elsif v_coverage_state='gap' then
    v_cause := 'layer92-reconciliation-coverage-gap';
    v_domain := 'layer-93-reconciliation-coverage';
    v_next := 'inspect-layer93-coverage';

  else
    v_cause := 'unknown';
    v_domain := 'layer-93-reconciliation-coverage';
    v_next := 'inspect-layer93-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer92CoverageIncidentCause',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-cause-v1',
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
    'invalidLayer92ReconciliationCount',v_invalid92,
    'missingLayer87ReceiptCount',v_missing87,
    'invalidLayer87ReceiptCount',v_invalid87,
    'executionReceiptMismatchCount',v_exec_mismatch,
    'policyDriftCount',v_policy_drift,
    'incidentDriftCount',v_incident_drift,
    'coverageDriftCount',v_coverage_drift,
    'incidentSummary',v_incident,
    'coverage',v_coverage,
    'authorityExpansion',false,
    'automaticLayer92ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'layer91ReceiptRewriteAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$layer95_cause$;

revoke all on function foundation.get_case_audit_layer92_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer92_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
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
as $layer95_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'case-audit-layer92-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer92-response-action-invalid';
  end if;

  v_cause := foundation.get_case_audit_layer92_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );
  v_incident_state := coalesce(v_cause->>'incidentState','normal');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-layer93-coverage' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer92-response-inspect-layer93-coverage';

  elsif p_action_key='inspect-layer94-incident-state' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer92-response-inspect-layer94-incident';

  elsif p_action_key='inspect-overdue-layer92-reconciliations' then
    v_action_class := 'observe';
    if v_cause_class in (
      'layer92-reconciliation-omission',
      'layer92-reconciliation-coverage-gap'
    ) then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer92-response-inspect-overdue';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-overdue-not-relevant';
    end if;

  elsif p_action_key='inspect-layer92-reconciliation-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer92-receipt-integrity' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer92-response-inspect-layer92-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-layer92-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer87-reconciliation-chain' then
    v_action_class := 'observe';
    if v_cause_class in ('layer87-receipt-integrity','layer87-receipt-missing') then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer92-response-inspect-layer87-chain';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-layer87-chain-not-relevant';
    end if;

  elsif p_action_key='inspect-layer91-execution-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer91-execution-receipt-mismatch' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer92-response-inspect-layer91-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-layer91-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer90-policy-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer90-policy-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer92-response-inspect-layer90-policy';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-layer90-policy-not-relevant';
    end if;

  elsif p_action_key='inspect-layer89-incident-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer89-incident-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer92-response-inspect-layer89-incident';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-layer89-incident-not-relevant';
    end if;

  elsif p_action_key='inspect-layer88-coverage-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer88-coverage-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer92-response-inspect-layer88-coverage';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-layer88-coverage-not-relevant';
    end if;

  elsif p_action_key='run-independent-layer92-reconciliation' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','critical')
       and v_cause_class='layer92-reconciliation-omission' then
      v_decision := 'admit';
      v_required_control := 'layer-92-bounded-reconciler';
      v_reason := 'case-audit-layer92-response-run-bounded-reconciliation';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer92-response-reconciliation-not-relevant';
    end if;

  elsif p_action_key in (
    'rerun-layer91','rerun-layer87','rerun-layer86','rerun-layer82',
    'rerun-layer81','rerun-verification',
    'manufacture-layer92-reconciliation','rewrite-layer92-reconciliation',
    'delete-layer92-reconciliation','repair-layer92-ledger',
    'manufacture-layer91-execution-receipt','rewrite-layer91-execution-receipt',
    'manufacture-layer87-reconciliation-receipt',
    'rewrite-layer87-reconciliation-receipt',
    'repair-upstream-evidence',
    'suppress-layer94-coverage-incident',
    'delete-layer94-coverage-incident-history',
    'mutate-release-truth'
  ) then
    v_action_class := case
      when p_action_key='rerun-layer91' then 'layer91-reexecution'
      when p_action_key='rerun-layer87' then 'layer87-reexecution'
      when p_action_key='rerun-layer86' then 'layer86-reexecution'
      when p_action_key='rerun-layer82' then 'layer82-reexecution'
      when p_action_key='rerun-layer81' then 'layer81-reexecution'
      when p_action_key='rerun-verification' then 'verification-reexecution'
      when p_action_key in (
        'manufacture-layer92-reconciliation','rewrite-layer92-reconciliation',
        'delete-layer92-reconciliation','repair-layer92-ledger'
      ) then 'layer92-receipt-mutation'
      when p_action_key in (
        'manufacture-layer91-execution-receipt','rewrite-layer91-execution-receipt'
      ) then 'layer91-receipt-mutation'
      when p_action_key in (
        'manufacture-layer87-reconciliation-receipt',
        'rewrite-layer87-reconciliation-receipt'
      ) then 'layer87-receipt-mutation'
      when p_action_key='repair-upstream-evidence' then 'evidence-mutation'
      when p_action_key='mutate-release-truth' then 'authoritative-mutation'
      else 'history-mutation'
    end;
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'case-audit-layer92-response-mutation-or-rerun-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer92CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-response-decision-v1',
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
    'boundedReconciler','foundation.run_case_audit_layer91_execution_reconciliation_v1',
    'authorityExpansion',false,
    'automaticLayer92ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'layer91ReceiptRewriteAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',coalesce(v_action_class='authoritative-mutation',false),
    'mutatesIncidentHistory',coalesce(v_action_class='history-mutation',false),
    'mutatesLayer92Receipt',coalesce(v_action_class='layer92-receipt-mutation',false),
    'mutatesLayer91Receipt',coalesce(v_action_class='layer91-receipt-mutation',false),
    'mutatesLayer87Receipt',coalesce(v_action_class='layer87-receipt-mutation',false),
    'rerunsLayer91',coalesce(v_action_class='layer91-reexecution',false),
    'rerunsLayer87',coalesce(v_action_class='layer87-reexecution',false),
    'rerunsLayer86',coalesce(v_action_class='layer86-reexecution',false),
    'rerunsLayer82',coalesce(v_action_class='layer82-reexecution',false),
    'rerunsLayer81',coalesce(v_action_class='layer81-reexecution',false),
    'rerunsVerification',coalesce(v_action_class='verification-reexecution',false),
    'executesAction',false,
    'cause',v_cause
  );
end;
$layer95_evaluate$;

revoke all on function foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer95_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause := foundation.get_case_audit_layer92_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  select jsonb_agg(
    foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
      action_key,p_environment,p_as_of,p_reconciliation_grace_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-layer93-coverage'),
      (2,'inspect-layer94-incident-state'),
      (3,'inspect-overdue-layer92-reconciliations'),
      (4,'inspect-layer92-reconciliation-receipt'),
      (5,'inspect-layer87-reconciliation-chain'),
      (6,'inspect-layer91-execution-receipt'),
      (7,'inspect-layer90-policy-binding'),
      (8,'inspect-layer89-incident-binding'),
      (9,'inspect-layer88-coverage-binding'),
      (10,'run-independent-layer92-reconciliation'),
      (11,'rerun-layer91'),
      (12,'rerun-layer87'),
      (13,'rerun-layer86'),
      (14,'rerun-layer82'),
      (15,'rerun-layer81'),
      (16,'rerun-verification'),
      (17,'manufacture-layer92-reconciliation'),
      (18,'rewrite-layer92-reconciliation'),
      (19,'delete-layer92-reconciliation'),
      (20,'repair-layer92-ledger'),
      (21,'manufacture-layer91-execution-receipt'),
      (22,'rewrite-layer91-execution-receipt'),
      (23,'manufacture-layer87-reconciliation-receipt'),
      (24,'rewrite-layer87-reconciliation-receipt'),
      (25,'repair-upstream-evidence'),
      (26,'suppress-layer94-coverage-incident'),
      (27,'delete-layer94-coverage-incident-history'),
      (28,'mutate-release-truth')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationCaseAuditLayer92CoverageIncidentResponsePlan',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'coverageState',v_cause->>'coverageState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticLayer92ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'layer91ReceiptRewriteAllowed',false,
    'layer87ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'boundedReconciler','foundation.run_case_audit_layer91_execution_reconciliation_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer95_plan$;

revoke all on function foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
