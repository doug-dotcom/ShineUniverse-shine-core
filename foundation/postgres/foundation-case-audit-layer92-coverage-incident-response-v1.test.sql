begin;

create or replace function foundation.get_case_audit_layer92_coverage_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $l95_incident_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l95_incident_state',true),''),
    'normal'
  );
begin
  return jsonb_build_object(
    'foundationCaseAuditLayer92CoverageIncidentSummary',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-incident-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'activeIncidentCount',case when v_state='critical' then 1 else 0 end,
    'watchCount',case when v_state='watching' then 1 else 0 end,
    'coverageState',coalesce(
      nullif(current_setting('foundation.test_l95_coverage_state',true),''),
      'idle'
    ),
    'coverageReasonCode',coalesce(
      nullif(current_setting('foundation.test_l95_reason',true),''),
      'case-audit-layer92-no-executions'
    ),
    'successfulLayer91ExecutionCount',1,
    'layer92ReconciliationReceiptCount',0,
    'problemCount',1,
    'layer92ReconciliationCoveragePercent',0,
    'healthyLayer92ReconciliationPercent',0,
    'currentEvent',null,
    'recommendedAction','none',
    'automaticLayer92Reconciliation',false,
    'automaticReconciliation',false,
    'automaticRepair',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$l95_incident_stub$;


create or replace function foundation.get_case_audit_layer92_reconciliation_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $l95_coverage_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l95_coverage_state',true),''),
    'idle'
  );
  v_reason text := coalesce(
    nullif(current_setting('foundation.test_l95_reason',true),''),
    'case-audit-layer92-no-executions'
  );
  v_overdue integer := coalesce(
    nullif(current_setting('foundation.test_l95_overdue',true),'')::integer,0
  );
  v_invalid92 integer := coalesce(
    nullif(current_setting('foundation.test_l95_invalid92',true),'')::integer,0
  );
  v_missing87 integer := coalesce(
    nullif(current_setting('foundation.test_l95_missing87',true),'')::integer,0
  );
  v_invalid87 integer := coalesce(
    nullif(current_setting('foundation.test_l95_invalid87',true),'')::integer,0
  );
  v_exec_mismatch integer := coalesce(
    nullif(current_setting('foundation.test_l95_exec_mismatch',true),'')::integer,0
  );
  v_policy_drift integer := coalesce(
    nullif(current_setting('foundation.test_l95_policy_drift',true),'')::integer,0
  );
  v_incident_drift integer := coalesce(
    nullif(current_setting('foundation.test_l95_incident_drift',true),'')::integer,0
  );
  v_coverage_drift integer := coalesce(
    nullif(current_setting('foundation.test_l95_coverage_drift',true),'')::integer,0
  );
begin
  return jsonb_build_object(
    'foundationCaseAuditLayer92ReconciliationCoverage',
      'shine-foundation/case-audit-layer92-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',v_state,
    'reasonCode',v_reason,
    'successfulLayer91ExecutionCount',
      case when v_state='idle' then 0 else 1 end,
    'layer92ReconciliationRequiredCount',
      case when v_state='idle' then 0 else 1 end,
    'layer92ReconciliationReceiptCount',
      case when v_overdue>0 then 0 else greatest(
        v_invalid92,v_missing87,v_invalid87,v_exec_mismatch,
        v_policy_drift,v_incident_drift,v_coverage_drift,
        case when v_state='normal' then 1 else 0 end
      ) end,
    'reconciledCount',case when v_state='normal' then 1 else 0 end,
    'pendingCount',case when v_state='pending' then 1 else 0 end,
    'overdueCount',v_overdue,
    'invalidLayer92ReconciliationCount',v_invalid92,
    'missingLayer87ReceiptCount',v_missing87,
    'invalidLayer87ReceiptCount',v_invalid87,
    'executionReceiptMismatchCount',v_exec_mismatch,
    'policyDriftCount',v_policy_drift,
    'incidentDriftCount',v_incident_drift,
    'coverageDriftCount',v_coverage_drift,
    'problemCount',
      v_overdue+v_invalid92+v_missing87+v_invalid87+
      v_exec_mismatch+v_policy_drift+v_incident_drift+v_coverage_drift,
    'layer92ReconciliationCoveragePercent',
      case when v_state='idle' then 100 when v_overdue>0 then 0 else 100 end,
    'healthyLayer92ReconciliationPercent',
      case when v_state in ('idle','normal') then 100 else 0 end,
    'items','[]'::jsonb,
    'layer92ProofIntegrityRecomputed',true,
    'linkedLayer87SnapshotRevalidated',true,
    'layer92ReconciliationPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'mutationPerformed',false
  );
end;
$l95_coverage_stub$;


do $l95_normal$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l95_incident_state','normal',true);
  perform set_config('foundation.test_l95_coverage_state','idle',true);
  perform set_config('foundation.test_l95_reason','case-audit-layer92-no-executions',true);

  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'none'
     or c->>'nextEvidenceAction'<>'none'
     or c->>'automaticLayer92ReconciliationAllowed'<>'false'
     or c->>'automaticRepairAllowed'<>'false'
     or c->>'layer91RerunAllowed'<>'false'
     or c->>'layer87RerunAllowed'<>'false' then
    raise exception 'Layer 95 normal cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
    'inspect-layer93-coverage','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only'
     or d->>'executesAction'<>'false' then
    raise exception 'Layer 95 coverage inspection invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
    'run-independent-layer92-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 95 healthy execution policy invalid: %',d;
  end if;
end;
$l95_normal$;


do $l95_omission$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l95_incident_state','critical',true);
  perform set_config('foundation.test_l95_coverage_state','gap',true);
  perform set_config('foundation.test_l95_reason','case-audit-layer92-overdue',true);
  perform set_config('foundation.test_l95_overdue','1',true);
  perform set_config('foundation.test_l95_invalid92','0',true);
  perform set_config('foundation.test_l95_missing87','0',true);
  perform set_config('foundation.test_l95_invalid87','0',true);
  perform set_config('foundation.test_l95_exec_mismatch','0',true);
  perform set_config('foundation.test_l95_policy_drift','0',true);
  perform set_config('foundation.test_l95_incident_drift','0',true);
  perform set_config('foundation.test_l95_coverage_drift','0',true);

  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'layer92-reconciliation-omission'
     or c->>'nextEvidenceAction'<>'run-independent-layer92-reconciliation' then
    raise exception 'Layer 95 omission cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
    'run-independent-layer92-reconciliation','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'layer-92-bounded-reconciler'
     or d->>'boundedReconciler'
        <>'foundation.run_case_audit_layer91_execution_reconciliation_v1'
     or d->>'automaticLayer92ReconciliationAllowed'<>'false'
     or d->>'executesAction'<>'false' then
    raise exception 'Layer 95 bounded Layer-92 admission invalid: %',d;
  end if;
end;
$l95_omission$;


do $l95_integrity_precedence$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l95_invalid92','1',true);
  perform set_config('foundation.test_l95_overdue','1',true);
  perform set_config('foundation.test_l95_reason','case-audit-layer92-receipt-invalid',true);

  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'layer92-receipt-integrity'
     or c->>'nextEvidenceAction'<>'inspect-layer92-reconciliation-receipt' then
    raise exception 'Layer 95 Layer-92 integrity precedence invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
    'run-independent-layer92-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 95 must not reconcile around bad Layer-92 receipt: %',d;
  end if;
end;
$l95_integrity_precedence$;


do $l95_deeper_causes$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l95_invalid92','0',true);
  perform set_config('foundation.test_l95_overdue','0',true);

  perform set_config('foundation.test_l95_invalid87','1',true);
  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer87-receipt-integrity' then
    raise exception 'Layer 95 invalid87 cause: %',c;
  end if;
  d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
    'inspect-layer87-reconciliation-chain','production',now(),300
  );
  if d->>'decision'<>'admit' then
    raise exception 'Layer 95 invalid87 inspect: %',d;
  end if;

  perform set_config('foundation.test_l95_invalid87','0',true);
  perform set_config('foundation.test_l95_exec_mismatch','1',true);
  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer91-execution-receipt-mismatch' then
    raise exception 'Layer 95 exec mismatch cause: %',c;
  end if;

  perform set_config('foundation.test_l95_exec_mismatch','0',true);
  perform set_config('foundation.test_l95_policy_drift','1',true);
  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer90-policy-drift' then
    raise exception 'Layer 95 policy drift cause: %',c;
  end if;

  perform set_config('foundation.test_l95_policy_drift','0',true);
  perform set_config('foundation.test_l95_incident_drift','1',true);
  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer89-incident-binding-drift' then
    raise exception 'Layer 95 incident drift cause: %',c;
  end if;

  perform set_config('foundation.test_l95_incident_drift','0',true);
  perform set_config('foundation.test_l95_coverage_drift','1',true);
  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer88-coverage-binding-drift' then
    raise exception 'Layer 95 coverage drift cause: %',c;
  end if;

  perform set_config('foundation.test_l95_coverage_drift','0',true);
  perform set_config('foundation.test_l95_missing87','1',true);
  c:=foundation.get_case_audit_layer92_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer87-receipt-missing' then
    raise exception 'Layer 95 missing87 cause: %',c;
  end if;
  d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
    'run-independent-layer92-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 95 must not create Layer92 around missing Layer87 truth: %',d;
  end if;
end;
$l95_deeper_causes$;


do $l95_prohibited$
declare action_key text; d jsonb;
begin
  foreach action_key in array array[
    'rerun-layer91','rerun-layer87','rerun-layer86','rerun-layer82',
    'rerun-layer81','rerun-verification',
    'manufacture-layer92-reconciliation','rewrite-layer92-reconciliation',
    'delete-layer92-reconciliation','repair-layer92-ledger',
    'manufacture-layer91-execution-receipt','rewrite-layer91-execution-receipt',
    'manufacture-layer87-reconciliation-receipt',
    'rewrite-layer87-reconciliation-receipt',
    'repair-upstream-evidence','suppress-layer94-coverage-incident',
    'delete-layer94-coverage-incident-history','mutate-release-truth'
  ]
  loop
    d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
      action_key,'production',now(),300
    );
    if d->>'decision'<>'deny'
       or d->>'requiredControl'<>'prohibited'
       or d->>'executesAction'<>'false'
       or d->>'authorityExpansion'<>'false'
       or d->>'automaticLayer92ReconciliationAllowed'<>'false'
       or d->>'automaticRepairAllowed'<>'false'
       or d->>'layer92ReceiptRewriteAllowed'<>'false'
       or d->>'layer91ReceiptRewriteAllowed'<>'false'
       or d->>'layer87ReceiptRewriteAllowed'<>'false'
       or d->>'historyRewriteAllowed'<>'false'
       or d->>'layer91RerunAllowed'<>'false'
       or d->>'layer87RerunAllowed'<>'false'
       or d->>'layer86RerunAllowed'<>'false'
       or d->>'layer82RerunAllowed'<>'false'
       or d->>'layer81RerunAllowed'<>'false'
       or d->>'verificationRerunAllowed'<>'false' then
      raise exception 'Layer 95 prohibited action escaped: %',d;
    end if;
  end loop;
end;
$l95_prohibited$;


do $l95_plan$
declare p jsonb;
begin
  perform set_config('foundation.test_l95_incident_state','watching',true);
  perform set_config('foundation.test_l95_coverage_state','gap',true);
  perform set_config('foundation.test_l95_reason','case-audit-layer92-overdue',true);
  perform set_config('foundation.test_l95_missing87','0',true);
  perform set_config('foundation.test_l95_overdue','1',true);

  p:=foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(
    'production',now(),300
  );

  if p->>'causeClass'<>'layer92-reconciliation-omission'
     or p->>'nextEvidenceAction'<>'run-independent-layer92-reconciliation'
     or p->>'authorityExpansion'<>'false'
     or p->>'automaticLayer92ReconciliationAllowed'<>'false'
     or jsonb_array_length(p->'actions')<>28
     or not exists(
       select 1 from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='run-independent-layer92-reconciliation'
         and a->>'decision'='admit'
         and a->>'requiredControl'='layer-92-bounded-reconciler'
     )
     or not exists(
       select 1 from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='rerun-layer91' and a->>'decision'='deny'
     ) then
    raise exception 'Layer 95 response plan invalid: %',p;
  end if;
end;
$l95_plan$;


do $l95_unknown$
declare d jsonb;
begin
  d:=foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(
    'unknown-action','production',now(),300
  );
  if d->>'decision'<>'deny'
     or d->>'requiredControl'<>'prohibited'
     or d->>'actionClass' is not null then
    raise exception 'Layer 95 unknown action did not fail closed: %',d;
  end if;
end;
$l95_unknown$;


do $l95_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer92_coverage_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER')
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       join pg_roles r on r.oid=a.grantee
       where n.nspname='foundation'
         and p.proname in (
           'get_case_audit_layer92_coverage_incident_cause_v1',
           'evaluate_case_audit_layer92_coverage_incident_response_v1',
           'get_case_audit_layer92_coverage_incident_response_plan_v1'
         )
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_layer92_coverage_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.evaluate_case_audit_layer92_coverage_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_layer92_coverage_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 95 privilege boundary invalid';
  end if;
end;
$l95_privileges$;

rollback;
