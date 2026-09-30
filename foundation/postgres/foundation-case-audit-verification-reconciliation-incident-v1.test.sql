begin;

-- Replace the Layer-83 reader transaction-locally with deterministic snapshots.
-- The original function is restored automatically by rollback.
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
as $l84_coverage_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l84_state',true),''),
    'normal'
  );
  v_reason text := nullif(
    current_setting('foundation.test_l84_reason',true),
    ''
  );
  v_problem integer := 0;
  v_execution integer := 1;
  v_items jsonb := '[]'::jsonb;
begin
  if v_reason is null then
    v_reason := case v_state
      when 'idle' then 'case-audit-verify-reconcile-no-executions'
      when 'normal' then 'case-audit-verify-reconcile-covered'
      when 'pending' then 'case-audit-verify-reconcile-within-grace'
      when 'gap' then 'case-audit-verify-reconcile-overdue'
      else 'case-audit-verify-reconcile-receipt-invalid'
    end;
  end if;

  if v_state='idle' then
    v_execution := 0;
  end if;

  if v_state in ('gap','invalid') then
    v_problem := 1;
  end if;

  if v_execution>0 then
    v_items := jsonb_build_array(
      jsonb_build_object(
        'executorEventId','84000000-0000-4000-8000-000000000001',
        'targetExecutionEventId','84000000-0000-4000-8000-000000000002',
        'verificationIncidentEventId','84000000-0000-4000-8000-000000000003',
        'executionRequestedAt','2026-09-30T00:00:00Z',
        'executionAgeSeconds',
          greatest(0,floor(extract(epoch from (
            p_as_of-'2026-09-30T00:00:00Z'::timestamptz
          )))::integer),
        'coverageState',case
          when v_state='gap' then 'overdue'
          when v_state='invalid' then 'invalid-reconciliation'
          when v_state='pending' then 'pending'
          else 'reconciled'
        end,
        'reasonCode',v_reason,
        'reconciliationId',case
          when v_state in ('normal','invalid')
            then '84000000-0000-4000-8000-000000000004'
          else null
        end,
        'reconciliationState',case
          when v_state in ('normal','invalid') then 'reconciled'
          else null
        end,
        'verificationId',case
          when v_state in ('normal','invalid')
            then '84000000-0000-4000-8000-000000000005'
          else null
        end,
        'verificationState',case
          when v_state in ('normal','invalid') then 'verified'
          else null
        end,
        'reconciliationProofIntegrityValid',case
          when v_state='invalid' then false
          when v_state='normal' then true
          else null
        end
      )
    );
  end if;

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
    'reconciliationReceiptCount',case
      when v_state in ('normal','invalid') then v_execution
      else 0
    end,
    'reconciledCount',case when v_state='normal' then 1 else 0 end,
    'pendingCount',case when v_state='pending' then 1 else 0 end,
    'overdueCount',case when v_state='gap' then 1 else 0 end,
    'invalidReconciliationCount',case when v_state='invalid' then 1 else 0 end,
    'missingProofCount',0,
    'receiptMismatchCount',0,
    'invalidProofCount',0,
    'evidenceDriftCount',0,
    'coverageDriftCount',0,
    'problemCount',v_problem,
    'reconciliationCoveragePercent',case
      when v_execution=0 then 100.00
      when v_state in ('normal','invalid') then 100.00
      else 0.00
    end,
    'healthyReconciliationPercent',case
      when v_execution=0 then 100.00
      when v_state='normal' then 100.00
      else 0.00
    end,
    'items',v_items,
    'onlySuccessfulLayer81ExecutionsRequireReconciliation',true,
    'reconciliationProofIntegrityRecomputed',true,
    'verificationRerunPerformed',false,
    'layer81RerunPerformed',false,
    'evidenceMutationPerformed',false,
    'verificationProofRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$l84_coverage_stub$;


do $l84_fingerprint_stability$
declare
  t timestamptz := now();
  a jsonb;
  b jsonb;
  fa text;
  fb text;
begin
  perform set_config('foundation.test_l84_state','gap',true);
  perform set_config(
    'foundation.test_l84_reason','case-audit-verify-reconcile-overdue',true
  );

  a:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t,300,100
  );
  b:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t+interval '120 seconds',300,100
  );

  fa:=foundation.case_audit_verify_reconcile_incident_fingerprint_v1(a);
  fb:=foundation.case_audit_verify_reconcile_incident_fingerprint_v1(b);

  if fa<>fb then
    raise exception 'Layer 84 fingerprint changed on time/age noise';
  end if;
end;
$l84_fingerprint_stability$;


do $l84_lifecycle$
declare
  t timestamptz := now();
  s jsonb;
  r jsonb;
  event_count integer;
begin
  perform set_config(
    'foundation.test_l84_state','gap',true
  );
  perform set_config(
    'foundation.test_l84_reason',
    'case-audit-verify-reconcile-overdue',
    true
  );

  s:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t,300,100
  );
  r:=foundation.transition_case_audit_verify_reconcile_incident_v1(
    'production',s,t,300
  );

  if r->>'eventType'<>'detected'
     or r->>'sourceState'<>'gap'
     or r->>'severity'<>'critical'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'1'
     or r->>'automaticReconciliation'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'layer81RerunPerformed'<>'false' then
    raise exception 'Layer 84 first GAP sample invalid: %',r;
  end if;

  s:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t+interval '301 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_reconcile_incident_v1(
    'production',s,t+interval '301 seconds',300
  );

  if r->>'eventType'<>'opened'
     or r->>'activeIncidentCount'<>'1'
     or r->>'watchCount'<>'0'
     or (r->>'persistenceSeconds')::integer<300 then
    raise exception 'Layer 84 persistent GAP did not open: %',r;
  end if;

  select count(*) into event_count
  from foundation.case_audit_verify_reconcile_incident_events;

  s:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t+interval '360 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_reconcile_incident_v1(
    'production',s,t+interval '360 seconds',300
  );

  if r->>'eventCreated'<>'false' then
    raise exception 'Layer 84 unchanged open evidence appended noise: %',r;
  end if;

  if (select count(*) from foundation.case_audit_verify_reconcile_incident_events)
       <> event_count then
    raise exception 'Layer 84 unchanged open event count changed';
  end if;

  perform set_config(
    'foundation.test_l84_reason',
    'case-audit-verify-exec-reconcile-evidence-drift',
    true
  );

  s:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t+interval '361 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_reconcile_incident_v1(
    'production',s,t+interval '361 seconds',300
  );

  if r->>'eventType'<>'changed'
     or r->>'reasonCode'<>
        'case-audit-verify-exec-reconcile-evidence-drift'
     or r->>'activeIncidentCount'<>'1' then
    raise exception 'Layer 84 material evidence change invalid: %',r;
  end if;

  perform set_config(
    'foundation.test_l84_state','pending',true
  );
  perform set_config(
    'foundation.test_l84_reason',
    'case-audit-verify-reconcile-within-grace',
    true
  );

  s:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t+interval '362 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_reconcile_incident_v1(
    'production',s,t+interval '362 seconds',300
  );

  if r->>'eventType'<>'recovered'
     or r->>'sourceState'<>'pending'
     or r->>'severity'<>'info'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0' then
    raise exception 'Layer 84 pending coverage did not recover incident: %',r;
  end if;

  perform set_config(
    'foundation.test_l84_state','invalid',true
  );
  perform set_config(
    'foundation.test_l84_reason',
    'case-audit-verify-reconcile-receipt-invalid',
    true
  );

  s:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t+interval '363 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_reconcile_incident_v1(
    'production',s,t+interval '363 seconds',300
  );

  if r->>'eventType'<>'detected'
     or r->>'sourceState'<>'invalid'
     or r->>'severity'<>'critical'
     or r->>'watchCount'<>'1' then
    raise exception 'Layer 84 INVALID watch invalid: %',r;
  end if;

  perform set_config(
    'foundation.test_l84_state','normal',true
  );
  perform set_config(
    'foundation.test_l84_reason',
    'case-audit-verify-reconcile-covered',
    true
  );

  s:=foundation.get_case_audit_verify_reconcile_coverage_v1(
    'production',t+interval '364 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_reconcile_incident_v1(
    'production',s,t+interval '364 seconds',300
  );

  if r->>'eventType'<>'recovered'
     or r->>'sourceState'<>'normal'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0' then
    raise exception 'Layer 84 INVALID watch recovery invalid: %',r;
  end if;
end;
$l84_lifecycle$;


set local role service_role;

do $l84_sentinel$
declare
  r jsonb;
begin
  perform set_config(
    'foundation.test_l84_state','normal',true
  );
  perform set_config(
    'foundation.test_l84_reason',
    'case-audit-verify-reconcile-covered',
    true
  );

  r:=foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(
    'staging',now(),300,300
  );

  if r->>'coverageState'<>'normal'
     or r#>>'{incidentTransition,eventCreated}'<>'false'
     or r->>'automaticReconciliation'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'layer81RerunPerformed'<>'false' then
    raise exception 'Layer 84 sentinel invalid: %',r;
  end if;
end;
$l84_sentinel$;

reset role;


do $l84_summary$
declare
  r jsonb;
begin
  perform set_config(
    'foundation.test_l84_state','normal',true
  );
  perform set_config(
    'foundation.test_l84_reason',
    'case-audit-verify-reconcile-covered',
    true
  );

  r:=foundation.get_case_audit_verify_reconcile_incident_summary_v1(
    'production',now(),300
  );

  if r->>'state'<>'normal'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0'
     or r->>'coverageState'<>'normal'
     or r->>'recommendedAction'<>'none'
     or r->>'automaticReconciliation'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'layer81RerunPerformed'<>'false' then
    raise exception 'Layer 84 summary invalid: %',r;
  end if;
end;
$l84_summary$;


do $l84_privileges$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_verify_reconcile_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_verify_reconcile_incident_events',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_reconcile_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_reconcile_incident_summary_v1(text,timestamptz,integer)',
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
         and p.proname='get_case_audit_verify_reconcile_incident_summary_v1'
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_reconcile_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_verify_reconcile_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_verify_reconcile_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_verify_reconcile_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'foundation.transition_case_audit_verify_reconcile_incident_v1(text,jsonb,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 84 privilege boundary invalid';
  end if;
end;
$l84_privileges$;


do $l84_append_only$
declare
  id uuid;
begin
  select event_id into id
  from foundation.case_audit_verify_reconcile_incident_events
  limit 1;

  begin
    update foundation.case_audit_verify_reconcile_incident_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 84 incident history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l84_append_only$;

rollback;
