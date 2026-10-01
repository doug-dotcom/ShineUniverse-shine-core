-- Foundation Layer 105: governed response policy for Layer-104 incidents.
-- Persistent Layer-103 coverage trouble may justify read-only diagnosis or, only
-- for a pure Layer-102 reconciliation omission, admission of one bounded Layer-102
-- reconciliation. This layer never executes that action and never permits repair,
-- receipt mutation, upstream reruns, incident suppression, or release-truth mutation.

create or replace function foundation.get_case_audit_layer102_coverage_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer105_cause$
declare
  v_incident jsonb;
  v_coverage jsonb;
  v_incident_state text;
  v_coverage_state text;
  v_reason text;
  v_overdue integer := 0;
  v_invalid102 integer := 0;
  v_missing97 integer := 0;
  v_invalid97 integer := 0;
  v_exec_mismatch integer := 0;
  v_policy_drift integer := 0;
  v_incident_drift integer := 0;
  v_coverage_drift integer := 0;
  v_cause text;
  v_domain text;
  v_next text;
begin
  v_incident := foundation.get_case_audit_layer102_coverage_incident_summary_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage := foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds,100
  );

  v_incident_state := coalesce(v_incident->>'state','normal');
  v_coverage_state := coalesce(v_coverage->>'state','invalid');
  v_reason := coalesce(
    nullif(v_coverage->>'reasonCode',''),
    'case-audit-layer102-response-cause-unknown'
  );

  v_overdue := coalesce((v_coverage->>'overdueCount')::integer,0);
  v_invalid102 :=
    coalesce((v_coverage->>'invalidLayer102ReconciliationCount')::integer,0);
  v_missing97 :=
    coalesce((v_coverage->>'missingLayer97ReceiptCount')::integer,0);
  v_invalid97 :=
    coalesce((v_coverage->>'invalidLayer97ReceiptCount')::integer,0);
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

  elsif v_invalid102>0 or v_coverage_state='invalid' then
    v_cause := 'layer102-receipt-integrity';
    v_domain := 'layer-102-reconciliation-receipt';
    v_next := 'inspect-layer102-reconciliation-receipt';

  elsif v_invalid97>0 then
    v_cause := 'layer97-receipt-integrity';
    v_domain := 'layer-97-reconciliation-receipt';
    v_next := 'inspect-layer97-reconciliation-receipt';

  elsif v_exec_mismatch>0 then
    v_cause := 'layer101-execution-receipt-mismatch';
    v_domain := 'layer-101-execution-receipt';
    v_next := 'inspect-layer101-execution-receipt';

  elsif v_policy_drift>0 then
    v_cause := 'layer100-policy-drift';
    v_domain := 'layer-100-response-policy-binding';
    v_next := 'inspect-layer100-policy-binding';

  elsif v_incident_drift>0 then
    v_cause := 'layer99-incident-binding-drift';
    v_domain := 'layer-99-coverage-incident-binding';
    v_next := 'inspect-layer99-incident-binding';

  elsif v_coverage_drift>0 then
    v_cause := 'layer98-coverage-binding-drift';
    v_domain := 'layer-98-reconciliation-coverage-binding';
    v_next := 'inspect-layer98-coverage-binding';

  elsif v_missing97>0 then
    v_cause := 'layer97-receipt-missing';
    v_domain := 'layer-97-reconciliation-chain';
    v_next := 'inspect-layer97-reconciliation-receipt';

  elsif v_overdue>0 then
    v_cause := 'layer102-reconciliation-omission';
    v_domain := 'layer-102-reconciliation-coverage';
    v_next := 'run-independent-layer102-reconciliation';

  elsif v_coverage_state='gap' then
    v_cause := 'layer102-reconciliation-coverage-gap';
    v_domain := 'layer-103-reconciliation-coverage';
    v_next := 'inspect-layer103-coverage';

  else
    v_cause := 'unknown';
    v_domain := 'layer-103-reconciliation-coverage';
    v_next := 'inspect-layer103-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer102CoverageIncidentCause',
      'shine-foundation/case-audit-layer102-reconciliation-coverage-incident-cause-v1',
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
    'invalidLayer102ReconciliationCount',v_invalid102,
    'missingLayer97ReceiptCount',v_missing97,
    'invalidLayer97ReceiptCount',v_invalid97,
    'executionReceiptMismatchCount',v_exec_mismatch,
    'policyDriftCount',v_policy_drift,
    'incidentDriftCount',v_incident_drift,
    'coverageDriftCount',v_coverage_drift,
    'incidentSummary',v_incident,
    'coverage',v_coverage,
    'authorityExpansion',false,
    'automaticLayer102ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer102ReceiptRewriteAllowed',false,
    'layer101ReceiptRewriteAllowed',false,
    'layer97ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer101RerunAllowed',false,
    'layer97RerunAllowed',false,
    'layer96RerunAllowed',false,
    'layer92RerunAllowed',false,
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
$layer105_cause$;

revoke all on function foundation.get_case_audit_layer102_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer102_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer102_coverage_incident_response_v1(
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
as $layer105_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'case-audit-layer102-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer102-response-action-invalid';
  end if;

  v_cause := foundation.get_case_audit_layer102_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );
  v_incident_state := coalesce(v_cause->>'incidentState','normal');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-layer103-coverage' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer102-response-inspect-layer103-coverage';

  elsif p_action_key='inspect-layer104-incident-state' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer102-response-inspect-layer104-incident';

  elsif p_action_key='inspect-overdue-layer102-reconciliations' then
    v_action_class := 'observe';
    if v_cause_class in (
      'layer102-reconciliation-omission',
      'layer102-reconciliation-coverage-gap'
    ) then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer102-response-inspect-overdue';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-overdue-not-relevant';
    end if;

  elsif p_action_key='inspect-layer102-reconciliation-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer102-receipt-integrity' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer102-response-inspect-layer102-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-layer102-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer97-reconciliation-receipt' then
    v_action_class := 'observe';
    if v_cause_class in ('layer97-receipt-integrity','layer97-receipt-missing') then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer102-response-inspect-layer97-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-layer97-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer101-execution-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer101-execution-receipt-mismatch' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer102-response-inspect-layer101-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-layer101-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer100-policy-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer100-policy-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer102-response-inspect-layer100-policy';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-layer100-policy-not-relevant';
    end if;

  elsif p_action_key='inspect-layer99-incident-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer99-incident-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer102-response-inspect-layer99-incident';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-layer99-incident-not-relevant';
    end if;

  elsif p_action_key='inspect-layer98-coverage-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer98-coverage-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer102-response-inspect-layer98-coverage';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-layer98-coverage-not-relevant';
    end if;

  elsif p_action_key='run-independent-layer102-reconciliation' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','critical')
       and v_cause_class='layer102-reconciliation-omission' then
      v_decision := 'admit';
      v_required_control := 'layer-102-bounded-reconciler';
      v_reason := 'case-audit-layer102-response-run-bounded-reconciliation';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer102-response-reconciliation-not-relevant';
    end if;

  elsif p_action_key in (
    'rerun-layer101','rerun-layer97','rerun-layer96','rerun-layer92','rerun-layer91','rerun-layer87',
    'rerun-layer86','rerun-layer82','rerun-layer81','rerun-verification',
    'manufacture-layer102-reconciliation','rewrite-layer102-reconciliation',
    'delete-layer102-reconciliation','repair-layer102-ledger',
    'manufacture-layer101-execution-receipt','rewrite-layer101-execution-receipt',
    'manufacture-layer97-reconciliation-receipt',
    'rewrite-layer97-reconciliation-receipt',
    'repair-upstream-evidence',
    'suppress-layer104-coverage-incident',
    'delete-layer104-coverage-incident-history',
    'mutate-release-truth'
  ) then
    v_action_class := case
      when p_action_key='rerun-layer101' then 'layer101-reexecution'
      when p_action_key='rerun-layer97' then 'layer97-reexecution'
      when p_action_key='rerun-layer96' then 'layer96-reexecution'
      when p_action_key='rerun-layer92' then 'layer92-reexecution'
      when p_action_key='rerun-layer91' then 'layer91-reexecution'
      when p_action_key='rerun-layer87' then 'layer87-reexecution'
      when p_action_key='rerun-layer86' then 'layer86-reexecution'
      when p_action_key='rerun-layer82' then 'layer82-reexecution'
      when p_action_key='rerun-layer81' then 'layer81-reexecution'
      when p_action_key='rerun-verification' then 'verification-reexecution'
      when p_action_key in (
        'manufacture-layer102-reconciliation','rewrite-layer102-reconciliation',
        'delete-layer102-reconciliation','repair-layer102-ledger'
      ) then 'layer102-receipt-mutation'
      when p_action_key in (
        'manufacture-layer101-execution-receipt','rewrite-layer101-execution-receipt'
      ) then 'layer101-receipt-mutation'
      when p_action_key in (
        'manufacture-layer97-reconciliation-receipt',
        'rewrite-layer97-reconciliation-receipt'
      ) then 'layer97-receipt-mutation'
      when p_action_key='repair-upstream-evidence' then 'evidence-mutation'
      when p_action_key='mutate-release-truth' then 'authoritative-mutation'
      else 'history-mutation'
    end;
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'case-audit-layer102-response-mutation-or-rerun-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer102CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer102-reconciliation-coverage-incident-response-decision-v1',
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
    'boundedReconciler','foundation.run_case_audit_layer101_execution_reconciliation_v1',
    'authorityExpansion',false,
    'automaticLayer102ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer102ReceiptRewriteAllowed',false,
    'layer101ReceiptRewriteAllowed',false,
    'layer97ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer101RerunAllowed',false,
    'layer97RerunAllowed',false,
    'layer96RerunAllowed',false,
    'layer92RerunAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'mutatesAuthoritativeTruth',coalesce(v_action_class='authoritative-mutation',false),
    'mutatesIncidentHistory',coalesce(v_action_class='history-mutation',false),
    'mutatesLayer102Receipt',coalesce(v_action_class='layer102-receipt-mutation',false),
    'mutatesLayer101Receipt',coalesce(v_action_class='layer101-receipt-mutation',false),
    'mutatesLayer97Receipt',coalesce(v_action_class='layer97-receipt-mutation',false),
    'rerunsLayer101',coalesce(v_action_class='layer101-reexecution',false),
    'rerunsLayer97',coalesce(v_action_class='layer97-reexecution',false),
    'rerunsLayer96',coalesce(v_action_class='layer96-reexecution',false),
    'rerunsLayer92',coalesce(v_action_class='layer92-reexecution',false),
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
$layer105_evaluate$;

revoke all on function foundation.evaluate_case_audit_layer102_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer102_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_case_audit_layer102_coverage_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer105_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause := foundation.get_case_audit_layer102_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  select jsonb_agg(
    foundation.evaluate_case_audit_layer102_coverage_incident_response_v1(
      action_key,p_environment,p_as_of,p_reconciliation_grace_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-layer103-coverage'),
      (2,'inspect-layer104-incident-state'),
      (3,'inspect-overdue-layer102-reconciliations'),
      (4,'inspect-layer102-reconciliation-receipt'),
      (5,'inspect-layer97-reconciliation-receipt'),
      (6,'inspect-layer101-execution-receipt'),
      (7,'inspect-layer100-policy-binding'),
      (8,'inspect-layer99-incident-binding'),
      (9,'inspect-layer98-coverage-binding'),
      (10,'run-independent-layer102-reconciliation'),
      (11,'rerun-layer101'),
      (12,'rerun-layer97'),
      (13,'rerun-layer96'),
      (14,'rerun-layer92'),
      (15,'rerun-layer91'),
      (16,'rerun-layer87'),
      (17,'rerun-layer86'),
      (18,'rerun-layer82'),
      (19,'rerun-layer81'),
      (20,'rerun-verification'),
      (21,'manufacture-layer102-reconciliation'),
      (22,'rewrite-layer102-reconciliation'),
      (23,'delete-layer102-reconciliation'),
      (24,'repair-layer102-ledger'),
      (25,'manufacture-layer101-execution-receipt'),
      (26,'rewrite-layer101-execution-receipt'),
      (27,'manufacture-layer97-reconciliation-receipt'),
      (28,'rewrite-layer97-reconciliation-receipt'),
      (29,'repair-upstream-evidence'),
      (30,'suppress-layer104-coverage-incident'),
      (31,'delete-layer104-coverage-incident-history'),
      (32,'mutate-release-truth')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationCaseAuditLayer102CoverageIncidentResponsePlan',
      'shine-foundation/case-audit-layer102-reconciliation-coverage-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'coverageState',v_cause->>'coverageState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticLayer102ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer102ReceiptRewriteAllowed',false,
    'layer101ReceiptRewriteAllowed',false,
    'layer97ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer101RerunAllowed',false,
    'layer97RerunAllowed',false,
    'layer96RerunAllowed',false,
    'layer92RerunAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'boundedReconciler','foundation.run_case_audit_layer101_execution_reconciliation_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer105_plan$;

revoke all on function foundation.get_case_audit_layer102_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer102_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
