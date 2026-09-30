begin;

-- Deterministic Layer-84 incident summary stub for Layer-85 policy testing.
create or replace function foundation.get_case_audit_verify_reconcile_incident_summary_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_reconciliation_grace_seconds integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $l85_incident_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l85_incident_state',true),''),
    'normal'
  );
begin
  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationIncidentSummary',
      'shine-foundation/case-audit-verification-reconciliation-incident-summary-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'state',v_state,
    'activeIncidentCount',case when v_state='critical' then 1 else 0 end,
    'watchCount',case when v_state='watching' then 1 else 0 end,
    'coverageState',
      coalesce(nullif(current_setting('foundation.test_l85_coverage_state',true),''),'normal'),
    'coverageReasonCode',
      coalesce(nullif(current_setting('foundation.test_l85_reason',true),''),'case-audit-verify-reconcile-covered'),
    'automaticReconciliation',false,
    'automaticRepair',false,
    'layer81RerunPerformed',false,
    'mutatesAuthoritativeTruth',false,
    'mutatesIncidentHistory',false
  );
end;
$l85_incident_stub$;


create or replace function foundation.get_case_audit_verify_reconcile_coverage_v1(
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
as $l85_coverage_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l85_coverage_state',true),''),
    'normal'
  );
  v_reason text := coalesce(
    nullif(current_setting('foundation.test_l85_reason',true),''),
    'case-audit-verify-reconcile-covered'
  );
  v_overdue integer := coalesce(
    nullif(current_setting('foundation.test_l85_overdue',true),'')::integer,0
  );
  v_invalid_reconciliation integer := coalesce(
    nullif(current_setting('foundation.test_l85_invalid_reconciliation',true),'')::integer,0
  );
  v_missing_proof integer := coalesce(
    nullif(current_setting('foundation.test_l85_missing_proof',true),'')::integer,0
  );
  v_receipt_mismatch integer := coalesce(
    nullif(current_setting('foundation.test_l85_receipt_mismatch',true),'')::integer,0
  );
  v_invalid_proof integer := coalesce(
    nullif(current_setting('foundation.test_l85_invalid_proof',true),'')::integer,0
  );
  v_evidence_drift integer := coalesce(
    nullif(current_setting('foundation.test_l85_evidence_drift',true),'')::integer,0
  );
  v_coverage_drift integer := coalesce(
    nullif(current_setting('foundation.test_l85_coverage_drift',true),'')::integer,0
  );
  v_problem integer;
  v_execution integer;
begin
  v_problem :=
    v_overdue+v_invalid_reconciliation+v_missing_proof+v_receipt_mismatch+
    v_invalid_proof+v_evidence_drift+v_coverage_drift;
  v_execution := case
    when v_state='idle' then 0
    else greatest(1,v_problem)
  end;

  return jsonb_build_object(
    'foundationCaseAuditVerificationReconciliationCoverage',
      'shine-foundation/case-audit-verification-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',v_state,
    'reasonCode',v_reason,
    'successfulExecutorCount',v_execution,
    'reconciliationRequiredCount',v_execution,
    'reconciliationReceiptCount',greatest(0,v_execution-v_overdue),
    'reconciledCount',case when v_state='normal' then v_execution else 0 end,
    'pendingCount',case when v_state='pending' then 1 else 0 end,
    'overdueCount',v_overdue,
    'invalidReconciliationCount',v_invalid_reconciliation,
    'missingProofCount',v_missing_proof,
    'receiptMismatchCount',v_receipt_mismatch,
    'invalidProofCount',v_invalid_proof,
    'evidenceDriftCount',v_evidence_drift,
    'coverageDriftCount',v_coverage_drift,
    'problemCount',v_problem,
    'reconciliationCoveragePercent',case
      when v_execution=0 then 100.00
      else round((100.0*greatest(0,v_execution-v_overdue)/v_execution)::numeric,2)
    end,
    'healthyReconciliationPercent',case
      when v_execution=0 or v_state='normal' then 100.00
      else 0.00
    end,
    'items','[]'::jsonb,
    'reconciliationProofIntegrityRecomputed',true,
    'verificationRerunPerformed',false,
    'layer81RerunPerformed',false,
    'mutationPerformed',false
  );
end;
$l85_coverage_stub$;


do $l85_normal$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_incident_state','normal',true);
  perform set_config('foundation.test_l85_coverage_state','idle',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-reconcile-no-executions',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );

  if c->>'causeClass'<>'none'
     or c->>'nextEvidenceAction'<>'none'
     or c->>'authorityExpansion'<>'false'
     or c->>'automaticReconciliationAllowed'<>'false'
     or c->>'automaticVerificationAllowed'<>'false'
     or c->>'automaticRepairAllowed'<>'false'
     or c->>'reconciliationReceiptRewriteAllowed'<>'false'
     or c->>'verificationProofRewriteAllowed'<>'false'
     or c->>'historyRewriteAllowed'<>'false'
     or c->>'layer81RerunAllowed'<>'false'
     or c->>'verificationRerunAllowed'<>'false' then
    raise exception 'Layer 85 normal cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'inspect-reconciliation-coverage','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only'
     or d->>'executesAction'<>'false' then
    raise exception 'Layer 85 coverage inspection invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'run-independent-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable'
     or d->>'requiredControl'<>'none' then
    raise exception 'Layer 85 healthy reconciliation policy invalid: %',d;
  end if;
end;
$l85_normal$;


do $l85_omission$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_incident_state','critical',true);
  perform set_config('foundation.test_l85_coverage_state','gap',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-reconcile-overdue',true);
  perform set_config('foundation.test_l85_overdue','1',true);
  perform set_config('foundation.test_l85_invalid_reconciliation','0',true);
  perform set_config('foundation.test_l85_missing_proof','0',true);
  perform set_config('foundation.test_l85_receipt_mismatch','0',true);
  perform set_config('foundation.test_l85_invalid_proof','0',true);
  perform set_config('foundation.test_l85_evidence_drift','0',true);
  perform set_config('foundation.test_l85_coverage_drift','0',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'reconciliation-omission'
     or c->>'sourceDomain'<>'layer-82-reconciliation-coverage'
     or c->>'nextEvidenceAction'<>'run-independent-reconciliation'
     or c->>'overdueCount'<>'1' then
    raise exception 'Layer 85 reconciliation omission cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'run-independent-reconciliation','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'layer-82-bounded-reconciler'
     or d->>'actionClass'<>'evidence'
     or d->>'automaticReconciliationAllowed'<>'false'
     or d->>'executesAction'<>'false'
     or d->>'rerunsLayer81'<>'false'
     or d->>'rerunsVerification'<>'false' then
    raise exception 'Layer 85 bounded reconciler admission invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'inspect-overdue-reconciliations','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only' then
    raise exception 'Layer 85 overdue inspection invalid: %',d;
  end if;
end;
$l85_omission$;


do $l85_invalid_reconciliation$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_incident_state','critical',true);
  perform set_config('foundation.test_l85_coverage_state','invalid',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-reconcile-receipt-invalid',true);
  perform set_config('foundation.test_l85_overdue','1',true);
  perform set_config('foundation.test_l85_invalid_reconciliation','1',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'reconciliation-receipt-integrity'
     or c->>'nextEvidenceAction'<>'inspect-reconciliation-receipt'
     or c->>'invalidReconciliationCount'<>'1' then
    raise exception 'Layer 85 invalid reconciliation cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'inspect-reconciliation-receipt','production',now(),300
  );
  if d->>'decision'<>'admit'
     or d->>'requiredControl'<>'read-only' then
    raise exception 'Layer 85 receipt inspection invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'run-independent-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 85 must not reconcile around invalid receipt: %',d;
  end if;
end;
$l85_invalid_reconciliation$;


do $l85_invalid_proof$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_coverage_state','gap',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-exec-reconcile-proof-invalid',true);
  perform set_config('foundation.test_l85_overdue','1',true);
  perform set_config('foundation.test_l85_invalid_reconciliation','0',true);
  perform set_config('foundation.test_l85_invalid_proof','1',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'verification-proof-integrity'
     or c->>'nextEvidenceAction'<>'inspect-verification-chain' then
    raise exception 'Layer 85 invalid verification proof cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'inspect-verification-chain','production',now(),300
  );
  if d->>'decision'<>'admit' then
    raise exception 'Layer 85 verification-chain inspection invalid: %',d;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'run-independent-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 85 integrity failure must dominate omission: %',d;
  end if;
end;
$l85_invalid_proof$;


do $l85_receipt_mismatch$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_overdue','0',true);
  perform set_config('foundation.test_l85_invalid_proof','0',true);
  perform set_config('foundation.test_l85_receipt_mismatch','1',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-exec-reconcile-receipt-mismatch',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'executor-receipt-mismatch'
     or c->>'nextEvidenceAction'<>'inspect-executor-receipt' then
    raise exception 'Layer 85 executor receipt mismatch cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'inspect-executor-receipt','production',now(),300
  );
  if d->>'decision'<>'admit' then
    raise exception 'Layer 85 executor receipt inspection invalid: %',d;
  end if;
end;
$l85_receipt_mismatch$;


do $l85_missing_proof$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_receipt_mismatch','0',true);
  perform set_config('foundation.test_l85_missing_proof','1',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-exec-reconcile-proof-missing',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'verification-proof-missing'
     or c->>'nextEvidenceAction'<>'inspect-verification-chain' then
    raise exception 'Layer 85 missing proof cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'run-independent-reconciliation','production',now(),300
  );
  if d->>'decision'<>'not-applicable' then
    raise exception 'Layer 85 must not re-reconcile immutable missing-proof receipt: %',d;
  end if;
end;
$l85_missing_proof$;


do $l85_evidence_drift$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_missing_proof','0',true);
  perform set_config('foundation.test_l85_evidence_drift','1',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-exec-reconcile-evidence-drift',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'durable-evidence-drift'
     or c->>'nextEvidenceAction'<>'inspect-durable-evidence-chain' then
    raise exception 'Layer 85 evidence drift cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'inspect-durable-evidence-chain','production',now(),300
  );
  if d->>'decision'<>'admit' then
    raise exception 'Layer 85 durable evidence inspection invalid: %',d;
  end if;
end;
$l85_evidence_drift$;


do $l85_coverage_drift$
declare
  c jsonb;
  d jsonb;
begin
  perform set_config('foundation.test_l85_evidence_drift','0',true);
  perform set_config('foundation.test_l85_coverage_drift','1',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-exec-reconcile-coverage-drift',true);

  c:=foundation.get_case_audit_verify_reconcile_incident_cause_v1(
    'production',now(),300
  );
  if c->>'causeClass'<>'verification-coverage-drift'
     or c->>'nextEvidenceAction'<>'inspect-verification-coverage' then
    raise exception 'Layer 85 verification coverage drift cause invalid: %',c;
  end if;

  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'inspect-verification-coverage','production',now(),300
  );
  if d->>'decision'<>'admit' then
    raise exception 'Layer 85 verification coverage inspection invalid: %',d;
  end if;
end;
$l85_coverage_drift$;


do $l85_prohibited$
declare
  action_key text;
  d jsonb;
begin
  foreach action_key in array array[
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
  ]
  loop
    d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
      action_key,'production',now(),300
    );

    if d->>'decision'<>'deny'
       or d->>'requiredControl'<>'prohibited'
       or d->>'executesAction'<>'false'
       or d->>'authorityExpansion'<>'false'
       or d->>'automaticReconciliationAllowed'<>'false'
       or d->>'automaticVerificationAllowed'<>'false'
       or d->>'automaticRepairAllowed'<>'false'
       or d->>'reconciliationReceiptRewriteAllowed'<>'false'
       or d->>'verificationProofRewriteAllowed'<>'false'
       or d->>'historyRewriteAllowed'<>'false'
       or d->>'layer81RerunAllowed'<>'false'
       or d->>'verificationRerunAllowed'<>'false' then
      raise exception 'Layer 85 prohibited action escaped policy: %',d;
    end if;
  end loop;
end;
$l85_prohibited$;


do $l85_plan$
declare
  p jsonb;
begin
  perform set_config('foundation.test_l85_incident_state','watching',true);
  perform set_config('foundation.test_l85_coverage_state','gap',true);
  perform set_config('foundation.test_l85_reason','case-audit-verify-reconcile-overdue',true);
  perform set_config('foundation.test_l85_overdue','1',true);
  perform set_config('foundation.test_l85_invalid_reconciliation','0',true);
  perform set_config('foundation.test_l85_missing_proof','0',true);
  perform set_config('foundation.test_l85_receipt_mismatch','0',true);
  perform set_config('foundation.test_l85_invalid_proof','0',true);
  perform set_config('foundation.test_l85_evidence_drift','0',true);
  perform set_config('foundation.test_l85_coverage_drift','0',true);

  p:=foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(
    'production',now(),300
  );

  if p->>'causeClass'<>'reconciliation-omission'
     or p->>'nextEvidenceAction'<>'run-independent-reconciliation'
     or p->>'authorityExpansion'<>'false'
     or p->>'automaticReconciliationAllowed'<>'false'
     or p->>'automaticVerificationAllowed'<>'false'
     or p->>'automaticRepairAllowed'<>'false'
     or jsonb_array_length(p->'actions')<>21
     or not exists(
       select 1
       from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='run-independent-reconciliation'
         and a->>'decision'='admit'
         and a->>'requiredControl'='layer-82-bounded-reconciler'
     )
     or not exists(
       select 1
       from jsonb_array_elements(p->'actions') a
       where a->>'actionKey'='rerun-layer81'
         and a->>'decision'='deny'
     ) then
    raise exception 'Layer 85 response plan invalid: %',p;
  end if;
end;
$l85_plan$;


do $l85_unknown_action$
declare
  d jsonb;
begin
  d:=foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(
    'unknown-action','production',now(),300
  );

  if d->>'decision'<>'deny'
     or d->>'requiredControl'<>'prohibited'
     or d->>'actionClass' is not null then
    raise exception 'Layer 85 unknown action must fail closed: %',d;
  end if;
end;
$l85_unknown_action$;


do $l85_privileges$
begin
  if not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_reconcile_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_has_role(
       'foundation_gateway','foundation_runtime','MEMBER'
     )
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(
         coalesce(p.proacl,acldefault('f',p.proowner))
       ) a
       join pg_roles r on r.oid=a.grantee
       where n.nspname='foundation'
         and p.proname in (
           'get_case_audit_verify_reconcile_incident_cause_v1',
           'evaluate_case_audit_verify_reconcile_incident_response_v1',
           'get_case_audit_verify_reconcile_incident_response_plan_v1'
         )
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_verify_reconcile_incident_response_plan_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.evaluate_case_audit_verify_reconcile_incident_response_v1(text,text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_verify_reconcile_incident_cause_v1(text,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 85 privilege boundary invalid';
  end if;
end;
$l85_privileges$;

rollback;
