begin;

create or replace function foundation.get_case_audit_reconcile_exec_coverage_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $l90_incident_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l90_incident_state',true),''),
    'normal'
  );
begin
  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionCoverageIncidentSummary',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-incident-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,'evaluatedAt',p_as_of,'state',v_state,
    'activeIncidentCount',case when v_state='critical' then 1 else 0 end,
    'watchCount',case when v_state='watching' then 1 else 0 end,
    'coverageState',coalesce(
      nullif(current_setting('foundation.test_l90_coverage_state',true),''),
      'normal'
    ),
    'coverageReasonCode',coalesce(
      nullif(current_setting('foundation.test_l90_reason',true),''),
      'case-audit-reconcile-exec-layer87-covered'
    ),
    'automaticLayer87Reconciliation',false,
    'automaticReconciliation',false,'automaticRepair',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutatesAuthoritativeTruth',false,'mutatesIncidentHistory',false
  );
end;
$l90_incident_stub$;


create or replace function foundation.get_case_audit_reconcile_exec_reconciliation_coverage_v1(
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
as $l90_coverage_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l90_coverage_state',true),''),
    'normal'
  );
  v_reason text := coalesce(
    nullif(current_setting('foundation.test_l90_reason',true),''),
    'case-audit-reconcile-exec-layer87-covered'
  );
  v_overdue integer := coalesce(nullif(current_setting('foundation.test_l90_overdue',true),'')::integer,0);
  v_invalid87 integer := coalesce(nullif(current_setting('foundation.test_l90_invalid87',true),'')::integer,0);
  v_missing82 integer := coalesce(nullif(current_setting('foundation.test_l90_missing82',true),'')::integer,0);
  v_invalid82 integer := coalesce(nullif(current_setting('foundation.test_l90_invalid82',true),'')::integer,0);
  v_exec_mismatch integer := coalesce(nullif(current_setting('foundation.test_l90_exec_mismatch',true),'')::integer,0);
  v_policy_drift integer := coalesce(nullif(current_setting('foundation.test_l90_policy_drift',true),'')::integer,0);
  v_incident_drift integer := coalesce(nullif(current_setting('foundation.test_l90_incident_drift',true),'')::integer,0);
  v_coverage_drift integer := coalesce(nullif(current_setting('foundation.test_l90_coverage_drift',true),'')::integer,0);
  v_problem integer;
  v_execution integer;
begin
  v_problem:=v_overdue+v_invalid87+v_missing82+v_invalid82+
    v_exec_mismatch+v_policy_drift+v_incident_drift+v_coverage_drift;
  v_execution:=case when v_state='idle' then 0 else greatest(1,v_problem) end;

  return jsonb_build_object(
    'foundationCaseAuditReconciliationExecutionReconciliationCoverage',
      'shine-foundation/case-audit-reconciliation-execution-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',v_state,'reasonCode',v_reason,
    'successfulLayer86ExecutionCount',v_execution,
    'layer87ReconciliationRequiredCount',v_execution,
    'layer87ReconciliationReceiptCount',greatest(0,v_execution-v_overdue),
    'reconciledCount',case when v_state='normal' then v_execution else 0 end,
    'pendingCount',case when v_state='pending' then 1 else 0 end,
    'overdueCount',v_overdue,
    'invalidLayer87ReconciliationCount',v_invalid87,
    'missingLayer82ReceiptCount',v_missing82,
    'invalidLayer82ReceiptCount',v_invalid82,
    'executionReceiptMismatchCount',v_exec_mismatch,
    'policyDriftCount',v_policy_drift,
    'incidentDriftCount',v_incident_drift,
    'coverageDriftCount',v_coverage_drift,
    'problemCount',v_problem,
    'layer87ReconciliationCoveragePercent',case
      when v_execution=0 then 100.00
      else round((100.0*greatest(0,v_execution-v_overdue)/v_execution)::numeric,2)
    end,
    'healthyLayer87ReconciliationPercent',case
      when v_execution=0 or v_state='normal' then 100.00 else 0.00
    end,
    'items','[]'::jsonb,
    'layer87ProofIntegrityRecomputed',true,
    'linkedLayer82SnapshotRevalidated',true,
    'layer87ReconciliationPerformed',false,
    'layer86RerunPerformed',false,'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,'verificationRerunPerformed',false,
    'mutationPerformed',false
  );
end;
$l90_coverage_stub$;


do $l90_normal$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l90_incident_state','normal',true);
  perform set_config('foundation.test_l90_coverage_state','idle',true);
  perform set_config('foundation.test_l90_reason','case-audit-reconcile-exec-layer87-no-executions',true);

  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'none' or c->>'nextEvidenceAction'<>'none'
     or c->>'automaticLayer87ReconciliationAllowed'<>'false'
     or c->>'automaticRepairAllowed'<>'false'
     or c->>'layer86RerunAllowed'<>'false' then
    raise exception 'Layer 90 normal cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
    'inspect-layer88-coverage','production',now(),300
  );
  if d->>'decision'<>'admit' or d->>'requiredControl'<>'read-only'
     or d->>'executesAction'<>'false' then
    raise exception 'Layer 90 coverage inspection invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
    'run-independent-layer87-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 90 healthy execution policy invalid: %',d;
  end if;
end;
$l90_normal$;


do $l90_omission$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l90_incident_state','critical',true);
  perform set_config('foundation.test_l90_coverage_state','gap',true);
  perform set_config('foundation.test_l90_reason','case-audit-reconcile-exec-layer87-overdue',true);
  perform set_config('foundation.test_l90_overdue','1',true);
  perform set_config('foundation.test_l90_invalid87','0',true);
  perform set_config('foundation.test_l90_missing82','0',true);
  perform set_config('foundation.test_l90_invalid82','0',true);
  perform set_config('foundation.test_l90_exec_mismatch','0',true);
  perform set_config('foundation.test_l90_policy_drift','0',true);
  perform set_config('foundation.test_l90_incident_drift','0',true);
  perform set_config('foundation.test_l90_coverage_drift','0',true);

  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer87-reconciliation-omission'
     or c->>'nextEvidenceAction'<>'run-independent-layer87-reconciliation' then
    raise exception 'Layer 90 omission cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
    'run-independent-layer87-reconciliation','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'layer-87-bounded-reconciler'
     or d->>'automaticLayer87ReconciliationAllowed'<>'false'
     or d->>'executesAction'<>'false' then
    raise exception 'Layer 90 bounded Layer-87 admission invalid: %',d;
  end if;
end;
$l90_omission$;


do $l90_integrity_precedence$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l90_invalid87','1',true);
  perform set_config('foundation.test_l90_overdue','1',true);
  perform set_config('foundation.test_l90_reason','case-audit-reconcile-exec-layer87-receipt-invalid',true);

  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer87-receipt-integrity'
     or c->>'nextEvidenceAction'<>'inspect-layer87-reconciliation-receipt' then
    raise exception 'Layer 90 Layer-87 integrity precedence invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
    'run-independent-layer87-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 90 must not reconcile around bad Layer-87 receipt: %',d;
  end if;
end;
$l90_integrity_precedence$;


do $l90_deeper_causes$
declare c jsonb; d jsonb;
begin
  perform set_config('foundation.test_l90_invalid87','0',true);
  perform set_config('foundation.test_l90_overdue','0',true);

  perform set_config('foundation.test_l90_invalid82','1',true);
  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer82-receipt-integrity' then raise exception 'Layer 90 invalid82 cause: %',c; end if;
  d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1('inspect-layer82-reconciliation-chain','production',now(),300);
  if d->>'decision'<>'admit' then raise exception 'Layer 90 invalid82 inspect: %',d; end if;

  perform set_config('foundation.test_l90_invalid82','0',true);
  perform set_config('foundation.test_l90_exec_mismatch','1',true);
  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer86-execution-receipt-mismatch' then raise exception 'Layer 90 exec mismatch cause: %',c; end if;

  perform set_config('foundation.test_l90_exec_mismatch','0',true);
  perform set_config('foundation.test_l90_policy_drift','1',true);
  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer85-policy-drift' then raise exception 'Layer 90 policy drift cause: %',c; end if;

  perform set_config('foundation.test_l90_policy_drift','0',true);
  perform set_config('foundation.test_l90_incident_drift','1',true);
  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer84-incident-binding-drift' then raise exception 'Layer 90 incident drift cause: %',c; end if;

  perform set_config('foundation.test_l90_incident_drift','0',true);
  perform set_config('foundation.test_l90_coverage_drift','1',true);
  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer83-coverage-binding-drift' then raise exception 'Layer 90 coverage drift cause: %',c; end if;

  perform set_config('foundation.test_l90_coverage_drift','0',true);
  perform set_config('foundation.test_l90_missing82','1',true);
  c:=foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1('production',now(),300);
  if c->>'causeClass'<>'layer82-receipt-missing' then raise exception 'Layer 90 missing82 cause: %',c; end if;
  d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
    'run-independent-layer87-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then raise exception 'Layer 90 must not rerun Layer87 for missing Layer82 truth: %',d; end if;
end;
$l90_deeper_causes$;


do $l90_prohibited$
declare action_key text; d jsonb;
begin
  foreach action_key in array array[
    'rerun-layer86','rerun-layer82','rerun-layer81','rerun-verification',
    'manufacture-layer87-reconciliation','rewrite-layer87-reconciliation',
    'delete-layer87-reconciliation','repair-layer87-ledger',
    'manufacture-layer86-execution-receipt','rewrite-layer86-execution-receipt',
    'manufacture-layer82-reconciliation-receipt',
    'rewrite-layer82-reconciliation-receipt',
    'repair-upstream-evidence','suppress-layer89-coverage-incident',
    'delete-layer89-coverage-incident-history','mutate-release-truth'
  ]
  loop
    d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
      action_key,'production',now(),300
    );
    if d->>'decision'<>'deny' or d->>'requiredControl'<>'prohibited'
       or d->>'executesAction'<>'false'
       or d->>'authorityExpansion'<>'false'
       or d->>'automaticLayer87ReconciliationAllowed'<>'false'
       or d->>'automaticRepairAllowed'<>'false'
       or d->>'layer87ReceiptRewriteAllowed'<>'false'
       or d->>'layer86ReceiptRewriteAllowed'<>'false'
       or d->>'layer82ReceiptRewriteAllowed'<>'false'
       or d->>'historyRewriteAllowed'<>'false'
       or d->>'layer86RerunAllowed'<>'false'
       or d->>'layer82RerunAllowed'<>'false'
       or d->>'layer81RerunAllowed'<>'false'
       or d->>'verificationRerunAllowed'<>'false' then
      raise exception 'Layer 90 prohibited action escaped: %',d;
    end if;
  end loop;
end;
$l90_prohibited$;


do $l90_plan$
declare p jsonb;
begin
  perform set_config('foundation.test_l90_incident_state','watching',true);
  perform set_config('foundation.test_l90_coverage_state','gap',true);
  perform set_config('foundation.test_l90_reason','case-audit-reconcile-exec-layer87-overdue',true);
  perform set_config('foundation.test_l90_missing82','0',true);
  perform set_config('foundation.test_l90_overdue','1',true);

  p:=foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(
    'production',now(),300
  );

  if p->>'causeClass'<>'layer87-reconciliation-omission'
     or p->>'nextEvidenceAction'<>'run-independent-layer87-reconciliation'
     or p->>'authorityExpansion'<>'false'
     or p->>'automaticLayer87ReconciliationAllowed'<>'false'
     or jsonb_array_length(p->'actions')<>26
     or not exists(
       select 1 from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='run-independent-layer87-reconciliation'
         and a->>'decision'='admit'
         and a->>'requiredControl'='layer-87-bounded-reconciler'
     )
     or not exists(
       select 1 from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='rerun-layer86' and a->>'decision'='deny'
     ) then
    raise exception 'Layer 90 response plan invalid: %',p;
  end if;
end;
$l90_plan$;


do $l90_unknown$
declare d jsonb;
begin
  d:=foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(
    'unknown-action','production',now(),300
  );
  if d->>'decision'<>'deny' or d->>'requiredControl'<>'prohibited'
     or d->>'actionClass' is not null then
    raise exception 'Layer 90 unknown action did not fail closed: %',d;
  end if;
end;
$l90_unknown$;


do $l90_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(text,timestamptz,integer)',
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
           'get_case_audit_reconcile_exec_coverage_incident_cause_v1',
           'evaluate_case_audit_reconcile_exec_coverage_incident_response_v1',
           'get_case_audit_reconcile_exec_coverage_incident_response_plan_v1'
         )
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_reconcile_exec_coverage_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.evaluate_case_audit_reconcile_exec_coverage_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_reconcile_exec_coverage_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 90 privilege boundary invalid';
  end if;
end;
$l90_privileges$;

rollback;
