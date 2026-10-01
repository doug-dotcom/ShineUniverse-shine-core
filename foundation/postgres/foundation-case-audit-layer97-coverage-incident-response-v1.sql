-- Foundation Layer 100: governed response policy for Layer-99 incidents.
-- Persistent Layer-98 coverage trouble may justify read-only diagnosis or, only
-- for a pure Layer-97 reconciliation omission, admission of one bounded Layer-97
-- reconciliation. This layer never executes that action and never permits repair,
-- receipt mutation, upstream reruns, incident suppression, or release-truth mutation.

create or replace function foundation.get_case_audit_layer97_coverage_incident_cause_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer100_cause$
declare
  v_incident jsonb;
  v_coverage jsonb;
  v_incident_state text;
  v_coverage_state text;
  v_reason text;
  v_overdue integer := 0;
  v_invalid97 integer := 0;
  v_missing92 integer := 0;
  v_invalid92 integer := 0;
  v_exec_mismatch integer := 0;
  v_policy_drift integer := 0;
  v_incident_drift integer := 0;
  v_coverage_drift integer := 0;
  v_cause text;
  v_domain text;
  v_next text;
begin
  v_incident := foundation.get_case_audit_layer97_coverage_incident_summary_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  v_coverage := foundation.get_case_audit_layer97_reconciliation_coverage_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds,100
  );

  v_incident_state := coalesce(v_incident->>'state','normal');
  v_coverage_state := coalesce(v_coverage->>'state','invalid');
  v_reason := coalesce(
    nullif(v_coverage->>'reasonCode',''),
    'case-audit-layer97-response-cause-unknown'
  );

  v_overdue := coalesce((v_coverage->>'overdueCount')::integer,0);
  v_invalid97 :=
    coalesce((v_coverage->>'invalidLayer97ReconciliationCount')::integer,0);
  v_missing92 :=
    coalesce((v_coverage->>'missingLayer92ReceiptCount')::integer,0);
  v_invalid92 :=
    coalesce((v_coverage->>'invalidLayer92ReceiptCount')::integer,0);
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

  elsif v_invalid97>0 or v_coverage_state='invalid' then
    v_cause := 'layer97-receipt-integrity';
    v_domain := 'layer-97-reconciliation-receipt';
    v_next := 'inspect-layer97-reconciliation-receipt';

  elsif v_invalid92>0 then
    v_cause := 'layer92-receipt-integrity';
    v_domain := 'layer-92-reconciliation-receipt';
    v_next := 'inspect-layer92-reconciliation-receipt';

  elsif v_exec_mismatch>0 then
    v_cause := 'layer96-execution-receipt-mismatch';
    v_domain := 'layer-96-execution-receipt';
    v_next := 'inspect-layer96-execution-receipt';

  elsif v_policy_drift>0 then
    v_cause := 'layer95-policy-drift';
    v_domain := 'layer-95-response-policy-binding';
    v_next := 'inspect-layer95-policy-binding';

  elsif v_incident_drift>0 then
    v_cause := 'layer94-incident-binding-drift';
    v_domain := 'layer-94-coverage-incident-binding';
    v_next := 'inspect-layer94-incident-binding';

  elsif v_coverage_drift>0 then
    v_cause := 'layer93-coverage-binding-drift';
    v_domain := 'layer-93-reconciliation-coverage-binding';
    v_next := 'inspect-layer93-coverage-binding';

  elsif v_missing92>0 then
    v_cause := 'layer92-receipt-missing';
    v_domain := 'layer-92-reconciliation-chain';
    v_next := 'inspect-layer92-reconciliation-receipt';

  elsif v_overdue>0 then
    v_cause := 'layer97-reconciliation-omission';
    v_domain := 'layer-97-reconciliation-coverage';
    v_next := 'run-independent-layer97-reconciliation';

  elsif v_coverage_state='gap' then
    v_cause := 'layer97-reconciliation-coverage-gap';
    v_domain := 'layer-98-reconciliation-coverage';
    v_next := 'inspect-layer98-coverage';

  else
    v_cause := 'unknown';
    v_domain := 'layer-98-reconciliation-coverage';
    v_next := 'inspect-layer98-coverage';
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer97CoverageIncidentCause',
      'shine-foundation/case-audit-layer97-reconciliation-coverage-incident-cause-v1',
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
    'invalidLayer97ReconciliationCount',v_invalid97,
    'missingLayer92ReceiptCount',v_missing92,
    'invalidLayer92ReceiptCount',v_invalid92,
    'executionReceiptMismatchCount',v_exec_mismatch,
    'policyDriftCount',v_policy_drift,
    'incidentDriftCount',v_incident_drift,
    'coverageDriftCount',v_coverage_drift,
    'incidentSummary',v_incident,
    'coverage',v_coverage,
    'authorityExpansion',false,
    'automaticLayer97ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer97ReceiptRewriteAllowed',false,
    'layer96ReceiptRewriteAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
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
$layer100_cause$;

revoke all on function foundation.get_case_audit_layer97_coverage_incident_cause_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer97_coverage_incident_cause_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.evaluate_case_audit_layer97_coverage_incident_response_v1(
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
as $layer100_evaluate$
declare
  v_cause jsonb;
  v_incident_state text;
  v_cause_class text;
  v_action_class text;
  v_decision text := 'deny';
  v_required_control text := 'prohibited';
  v_reason text := 'case-audit-layer97-response-action-not-registered';
begin
  if p_action_key is null
     or p_action_key !~ '^[a-z0-9][a-z0-9._:-]*$' then
    raise exception 'case-audit-layer97-response-action-invalid';
  end if;

  v_cause := foundation.get_case_audit_layer97_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );
  v_incident_state := coalesce(v_cause->>'incidentState','normal');
  v_cause_class := coalesce(v_cause->>'causeClass','unknown');

  if p_action_key='inspect-layer98-coverage' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer97-response-inspect-layer98-coverage';

  elsif p_action_key='inspect-layer99-incident-state' then
    v_action_class := 'observe';
    v_decision := 'admit';
    v_required_control := 'read-only';
    v_reason := 'case-audit-layer97-response-inspect-layer99-incident';

  elsif p_action_key='inspect-overdue-layer97-reconciliations' then
    v_action_class := 'observe';
    if v_cause_class in (
      'layer97-reconciliation-omission',
      'layer97-reconciliation-coverage-gap'
    ) then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer97-response-inspect-overdue';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-overdue-not-relevant';
    end if;

  elsif p_action_key='inspect-layer97-reconciliation-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer97-receipt-integrity' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer97-response-inspect-layer97-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-layer97-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer92-reconciliation-receipt' then
    v_action_class := 'observe';
    if v_cause_class in ('layer92-receipt-integrity','layer92-receipt-missing') then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer97-response-inspect-layer92-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-layer92-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer96-execution-receipt' then
    v_action_class := 'observe';
    if v_cause_class='layer96-execution-receipt-mismatch' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer97-response-inspect-layer96-receipt';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-layer96-receipt-not-relevant';
    end if;

  elsif p_action_key='inspect-layer95-policy-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer95-policy-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer97-response-inspect-layer95-policy';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-layer95-policy-not-relevant';
    end if;

  elsif p_action_key='inspect-layer94-incident-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer94-incident-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer97-response-inspect-layer94-incident';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-layer94-incident-not-relevant';
    end if;

  elsif p_action_key='inspect-layer93-coverage-binding' then
    v_action_class := 'observe';
    if v_cause_class='layer93-coverage-binding-drift' then
      v_decision := 'admit';
      v_required_control := 'read-only';
      v_reason := 'case-audit-layer97-response-inspect-layer93-coverage';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-layer93-coverage-not-relevant';
    end if;

  elsif p_action_key='run-independent-layer97-reconciliation' then
    v_action_class := 'evidence';
    if v_incident_state in ('watching','critical')
       and v_cause_class='layer97-reconciliation-omission' then
      v_decision := 'admit';
      v_required_control := 'layer-97-bounded-reconciler';
      v_reason := 'case-audit-layer97-response-run-bounded-reconciliation';
    else
      v_decision := 'not-applicable';
      v_required_control := 'none';
      v_reason := 'case-audit-layer97-response-reconciliation-not-relevant';
    end if;

  elsif p_action_key in (
    'rerun-layer96','rerun-layer92','rerun-layer91','rerun-layer87',
    'rerun-layer86','rerun-layer82','rerun-layer81','rerun-verification',
    'manufacture-layer97-reconciliation','rewrite-layer97-reconciliation',
    'delete-layer97-reconciliation','repair-layer97-ledger',
    'manufacture-layer96-execution-receipt','rewrite-layer96-execution-receipt',
    'manufacture-layer92-reconciliation-receipt',
    'rewrite-layer92-reconciliation-receipt',
    'repair-upstream-evidence',
    'suppress-layer99-coverage-incident',
    'delete-layer99-coverage-incident-history',
    'mutate-release-truth'
  ) then
    v_action_class := case
      when p_action_key='rerun-layer96' then 'layer96-reexecution'
      when p_action_key='rerun-layer92' then 'layer92-reexecution'
      when p_action_key='rerun-layer91' then 'layer91-reexecution'
      when p_action_key='rerun-layer87' then 'layer87-reexecution'
      when p_action_key='rerun-layer86' then 'layer86-reexecution'
      when p_action_key='rerun-layer82' then 'layer82-reexecution'
      when p_action_key='rerun-layer81' then 'layer81-reexecution'
      when p_action_key='rerun-verification' then 'verification-reexecution'
      when p_action_key in (
        'manufacture-layer97-reconciliation','rewrite-layer97-reconciliation',
        'delete-layer97-reconciliation','repair-layer97-ledger'
      ) then 'layer97-receipt-mutation'
      when p_action_key in (
        'manufacture-layer96-execution-receipt','rewrite-layer96-execution-receipt'
      ) then 'layer96-receipt-mutation'
      when p_action_key in (
        'manufacture-layer92-reconciliation-receipt',
        'rewrite-layer92-reconciliation-receipt'
      ) then 'layer92-receipt-mutation'
      when p_action_key='repair-upstream-evidence' then 'evidence-mutation'
      when p_action_key='mutate-release-truth' then 'authoritative-mutation'
      else 'history-mutation'
    end;
    v_decision := 'deny';
    v_required_control := 'prohibited';
    v_reason := 'case-audit-layer97-response-mutation-or-rerun-prohibited';

  else
    v_action_class := null;
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer97CoverageIncidentResponseDecision',
      'shine-foundation/case-audit-layer97-reconciliation-coverage-incident-response-decision-v1',
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
    'boundedReconciler','foundation.run_case_audit_layer96_execution_reconciliation_v1',
    'authorityExpansion',false,
    'automaticLayer97ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer97ReceiptRewriteAllowed',false,
    'layer96ReceiptRewriteAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
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
    'mutatesLayer97Receipt',coalesce(v_action_class='layer97-receipt-mutation',false),
    'mutatesLayer96Receipt',coalesce(v_action_class='layer96-receipt-mutation',false),
    'mutatesLayer92Receipt',coalesce(v_action_class='layer92-receipt-mutation',false),
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
$layer100_evaluate$;

revoke all on function foundation.evaluate_case_audit_layer97_coverage_incident_response_v1(
  text,text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.evaluate_case_audit_layer97_coverage_incident_response_v1(
  text,text,timestamptz,integer
) to foundation_runtime,service_role;


create or replace function foundation.get_case_audit_layer97_coverage_incident_response_plan_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $layer100_plan$
declare
  v_cause jsonb;
  v_actions jsonb;
begin
  v_cause := foundation.get_case_audit_layer97_coverage_incident_cause_v1(
    p_environment,p_as_of,p_reconciliation_grace_seconds
  );

  select jsonb_agg(
    foundation.evaluate_case_audit_layer97_coverage_incident_response_v1(
      action_key,p_environment,p_as_of,p_reconciliation_grace_seconds
    )
    order by ordinal
  )
  into v_actions
  from (
    values
      (1,'inspect-layer98-coverage'),
      (2,'inspect-layer99-incident-state'),
      (3,'inspect-overdue-layer97-reconciliations'),
      (4,'inspect-layer97-reconciliation-receipt'),
      (5,'inspect-layer92-reconciliation-receipt'),
      (6,'inspect-layer96-execution-receipt'),
      (7,'inspect-layer95-policy-binding'),
      (8,'inspect-layer94-incident-binding'),
      (9,'inspect-layer93-coverage-binding'),
      (10,'run-independent-layer97-reconciliation'),
      (11,'rerun-layer96'),
      (12,'rerun-layer92'),
      (13,'rerun-layer91'),
      (14,'rerun-layer87'),
      (15,'rerun-layer86'),
      (16,'rerun-layer82'),
      (17,'rerun-layer81'),
      (18,'rerun-verification'),
      (19,'manufacture-layer97-reconciliation'),
      (20,'rewrite-layer97-reconciliation'),
      (21,'delete-layer97-reconciliation'),
      (22,'repair-layer97-ledger'),
      (23,'manufacture-layer96-execution-receipt'),
      (24,'rewrite-layer96-execution-receipt'),
      (25,'manufacture-layer92-reconciliation-receipt'),
      (26,'rewrite-layer92-reconciliation-receipt'),
      (27,'repair-upstream-evidence'),
      (28,'suppress-layer99-coverage-incident'),
      (29,'delete-layer99-coverage-incident-history'),
      (30,'mutate-release-truth')
  ) a(ordinal,action_key);

  return jsonb_build_object(
    'foundationCaseAuditLayer97CoverageIncidentResponsePlan',
      'shine-foundation/case-audit-layer97-reconciliation-coverage-incident-response-plan-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'incidentState',v_cause->>'incidentState',
    'coverageState',v_cause->>'coverageState',
    'causeClass',v_cause->>'causeClass',
    'sourceDomain',v_cause->>'sourceDomain',
    'nextEvidenceAction',v_cause->>'nextEvidenceAction',
    'authorityExpansion',false,
    'automaticLayer97ReconciliationAllowed',false,
    'automaticReconciliationAllowed',false,
    'automaticRepairAllowed',false,
    'layer97ReceiptRewriteAllowed',false,
    'layer96ReceiptRewriteAllowed',false,
    'layer92ReceiptRewriteAllowed',false,
    'historyRewriteAllowed',false,
    'layer96RerunAllowed',false,
    'layer92RerunAllowed',false,
    'layer91RerunAllowed',false,
    'layer87RerunAllowed',false,
    'layer86RerunAllowed',false,
    'layer82RerunAllowed',false,
    'layer81RerunAllowed',false,
    'verificationRerunAllowed',false,
    'boundedReconciler','foundation.run_case_audit_layer96_execution_reconciliation_v1',
    'cause',v_cause,
    'actions',coalesce(v_actions,'[]'::jsonb)
  );
end;
$layer100_plan$;

revoke all on function foundation.get_case_audit_layer97_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) from public,anon,authenticated,foundation_gateway,shine_core_control_plane,
       shine_defence_runtime;
grant execute on function foundation.get_case_audit_layer97_coverage_incident_response_plan_v1(
  text,timestamptz,integer
) to foundation_runtime,service_role;
