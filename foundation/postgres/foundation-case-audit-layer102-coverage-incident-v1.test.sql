begin;

-- Replace the Layer-98 reader transaction-locally with deterministic snapshots.
create or replace function foundation.get_case_audit_layer102_reconciliation_coverage_v1(
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
as $l104_coverage_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l104_state',true),''),
    'normal'
  );
  v_reason text := nullif(
    current_setting('foundation.test_l104_reason',true),
    ''
  );
  v_problem integer := 0;
  v_execution integer := 1;
  v_receipt integer := 0;
  v_reconciled integer := 0;
  v_pending integer := 0;
  v_overdue integer := 0;
  v_invalid97 integer := 0;
  v_missing92 integer := 0;
  v_exec_mismatch integer := 0;
  v_coverage_state text := 'reconciled';
  v_items jsonb := '[]'::jsonb;
begin
  if v_reason is null then
    v_reason := case v_state
      when 'idle' then 'case-audit-layer102-no-executions'
      when 'normal' then 'case-audit-layer102-covered'
      when 'pending' then 'case-audit-layer102-within-grace'
      when 'gap' then 'case-audit-layer102-overdue'
      else 'case-audit-layer102-receipt-invalid'
    end;
  end if;

  if v_state='idle' then
    v_execution := 0;
  elsif v_state='normal' then
    v_receipt := 1;
    v_reconciled := 1;
    v_coverage_state := 'reconciled';
  elsif v_state='pending' then
    v_pending := 1;
    v_coverage_state := 'pending';
  elsif v_state='invalid' then
    v_receipt := 1;
    v_invalid97 := 1;
    v_problem := 1;
    v_coverage_state := 'invalid-reconciliation';
  elsif v_state='gap' then
    v_problem := 1;
    if v_reason='case-audit-layer96-receipt-mismatch' then
      v_receipt := 1;
      v_exec_mismatch := 1;
      v_coverage_state := 'execution-receipt-mismatch';
    elsif v_reason='case-audit-layer96-layer92-receipt-missing' then
      v_receipt := 1;
      v_missing92 := 1;
      v_coverage_state := 'missing-layer92-receipt';
    else
      v_overdue := 1;
      v_coverage_state := 'overdue';
    end if;
  end if;

  if v_execution>0 then
    v_items := jsonb_build_array(
      jsonb_build_object(
        'layer101EventId','10400000-0000-4000-8000-000000000001',
        'targetLayer96EventId','10400000-0000-4000-8000-000000000002',
        'coverageIncidentEventId','10400000-0000-4000-8000-000000000003',
        'executionRequestedAt','2026-10-01T00:00:00Z',
        'executionAgeSeconds',
          greatest(0,floor(extract(epoch from (
            p_as_of-'2026-10-01T00:00:00Z'::timestamptz
          )))::integer),
        'coverageState',v_coverage_state,
        'reasonCode',v_reason,
        'layer102ReconciliationId',case
          when v_receipt=1 then '10400000-0000-4000-8000-000000000004'
          else null
        end,
        'layer102ReconciliationState',case
          when v_state='normal' then 'reconciled'
          when v_invalid97=1 then 'reconciled'
          when v_missing92=1 then 'missing-layer92-receipt'
          when v_exec_mismatch=1 then 'execution-receipt-mismatch'
          else null
        end,
        'layer97ReconciliationId',case
          when v_state='normal' or v_invalid97=1 or v_exec_mismatch=1
            then '10400000-0000-4000-8000-000000000005'
          else null
        end,
        'layer97ReconciliationState',case
          when v_state='normal' or v_invalid97=1 or v_exec_mismatch=1
            then 'missing-layer87-receipt'
          else null
        end,
        'layer102ProofIntegrityValid',case
          when v_invalid97=1 then false
          when v_receipt=1 then true
          else null
        end
      )
    );
  end if;

  return jsonb_build_object(
    'foundationCaseAuditLayer102ReconciliationCoverage',
      'shine-foundation/case-audit-layer102-reconciliation-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'reconciliationGraceSeconds',p_reconciliation_grace_seconds,
    'state',v_state,
    'reasonCode',v_reason,
    'successfulLayer101ExecutionCount',v_execution,
    'layer102ReconciliationRequiredCount',v_execution,
    'layer102ReconciliationReceiptCount',v_receipt,
    'reconciledCount',v_reconciled,
    'pendingCount',v_pending,
    'overdueCount',v_overdue,
    'invalidLayer102ReconciliationCount',v_invalid97,
    'missingLayer97ReceiptCount',v_missing92,
    'invalidLayer97ReceiptCount',0,
    'executionReceiptMismatchCount',v_exec_mismatch,
    'policyDriftCount',0,
    'incidentDriftCount',0,
    'coverageDriftCount',0,
    'problemCount',v_problem,
    'layer102ReconciliationCoveragePercent',case
      when v_execution=0 then 100.00
      else round((100.0*v_receipt/v_execution)::numeric,2)
    end,
    'healthyLayer102ReconciliationPercent',case
      when v_execution=0 then 100.00
      else round((100.0*v_reconciled/v_execution)::numeric,2)
    end,
    'visibleCount',jsonb_array_length(v_items),
    'hasMore',false,
    'items',v_items,
    'onlySuccessfulLayer96ExecutionsRequireLayer97Reconciliation',true,
    'layer102ProofIntegrityRecomputed',true,
    'linkedLayer97SnapshotRevalidated',true,
    'layer102ReconciliationPerformed',false,
    'layer101RerunPerformed',false,
    'layer97RerunPerformed',false,
    'layer96RerunPerformed',false,
    'layer92RerunPerformed',false,
    'layer91RerunPerformed',false,
    'layer87RerunPerformed',false,
    'layer86RerunPerformed',false,
    'layer82RerunPerformed',false,
    'layer81RerunPerformed',false,
    'verificationRerunPerformed',false,
    'evidenceMutationPerformed',false,
    'layer97ReceiptRewritePerformed',false,
    'layer92ReceiptRewritePerformed',false,
    'layer91ReceiptRewritePerformed',false,
    'layer87ReceiptRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$l104_coverage_stub$;


do $l104_fingerprint_stability$
declare
  t timestamptz := now();
  a jsonb;
  b jsonb;
begin
  perform set_config('foundation.test_l104_state','gap',true);
  perform set_config('foundation.test_l104_reason','case-audit-layer102-overdue',true);

  a:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t,300,100
  );
  b:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t+interval '120 seconds',300,100
  );

  if foundation.case_audit_layer102_coverage_incident_fingerprint_v1(a)
     <> foundation.case_audit_layer102_coverage_incident_fingerprint_v1(b) then
    raise exception 'Layer 104 fingerprint changed on clock noise';
  end if;
end;
$l104_fingerprint_stability$;


do $l104_lifecycle$
declare
  t timestamptz := now();
  s jsonb;
  r jsonb;
  event_count integer;
begin
  perform set_config('foundation.test_l104_state','gap',true);
  perform set_config('foundation.test_l104_reason','case-audit-layer102-overdue',true);

  s:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t,300,100
  );
  r:=foundation.transition_case_audit_layer102_coverage_incident_v1(
    'production',s,t,300
  );

  if r->>'eventType'<>'detected'
     or r->>'sourceState'<>'gap'
     or r->>'severity'<>'critical'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'1'
     or r->>'automaticLayer102Reconciliation'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'layer96RerunPerformed'<>'false'
     or r->>'layer92RerunPerformed'<>'false' then
    raise exception 'Layer 104 first GAP sample invalid: %',r;
  end if;

  s:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t+interval '301 seconds',300,100
  );
  r:=foundation.transition_case_audit_layer102_coverage_incident_v1(
    'production',s,t+interval '301 seconds',300
  );

  if r->>'eventType'<>'opened'
     or r->>'activeIncidentCount'<>'1'
     or r->>'watchCount'<>'0'
     or (r->>'persistenceSeconds')::integer<300 then
    raise exception 'Layer 104 persistent GAP did not open: %',r;
  end if;

  select count(*) into event_count
  from foundation.case_audit_layer102_coverage_incident_events;

  s:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t+interval '360 seconds',300,100
  );
  r:=foundation.transition_case_audit_layer102_coverage_incident_v1(
    'production',s,t+interval '360 seconds',300
  );

  if r->>'eventCreated'<>'false'
     or (select count(*) from foundation.case_audit_layer102_coverage_incident_events)
        <>event_count then
    raise exception 'Layer 104 unchanged open evidence appended noise: %',r;
  end if;

  perform set_config(
    'foundation.test_l104_reason',
    'case-audit-layer96-receipt-mismatch',
    true
  );

  s:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t+interval '361 seconds',300,100
  );
  r:=foundation.transition_case_audit_layer102_coverage_incident_v1(
    'production',s,t+interval '361 seconds',300
  );

  if r->>'eventType'<>'changed'
     or r->>'reasonCode'<>'case-audit-layer96-receipt-mismatch'
     or r->>'activeIncidentCount'<>'1' then
    raise exception 'Layer 104 material evidence change invalid: %',r;
  end if;

  perform set_config('foundation.test_l104_state','pending',true);
  perform set_config('foundation.test_l104_reason','case-audit-layer102-within-grace',true);

  s:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t+interval '362 seconds',300,100
  );
  r:=foundation.transition_case_audit_layer102_coverage_incident_v1(
    'production',s,t+interval '362 seconds',300
  );

  if r->>'eventType'<>'recovered'
     or r->>'sourceState'<>'pending'
     or r->>'severity'<>'info'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0' then
    raise exception 'Layer 104 pending coverage did not recover: %',r;
  end if;

  perform set_config('foundation.test_l104_state','invalid',true);
  perform set_config('foundation.test_l104_reason','case-audit-layer102-receipt-invalid',true);

  s:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t+interval '363 seconds',300,100
  );
  r:=foundation.transition_case_audit_layer102_coverage_incident_v1(
    'production',s,t+interval '363 seconds',300
  );

  if r->>'eventType'<>'detected'
     or r->>'sourceState'<>'invalid'
     or r->>'severity'<>'critical'
     or r->>'watchCount'<>'1' then
    raise exception 'Layer 104 INVALID watch invalid: %',r;
  end if;

  perform set_config('foundation.test_l104_state','normal',true);
  perform set_config('foundation.test_l104_reason','case-audit-layer102-covered',true);

  s:=foundation.get_case_audit_layer102_reconciliation_coverage_v1(
    'production',t+interval '364 seconds',300,100
  );
  r:=foundation.transition_case_audit_layer102_coverage_incident_v1(
    'production',s,t+interval '364 seconds',300
  );

  if r->>'eventType'<>'recovered'
     or r->>'sourceState'<>'normal'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0' then
    raise exception 'Layer 104 INVALID recovery invalid: %',r;
  end if;
end;
$l104_lifecycle$;


set local role service_role;

do $l104_sentinel$
declare r jsonb;
begin
  perform set_config('foundation.test_l104_state','normal',true);
  perform set_config('foundation.test_l104_reason','case-audit-layer102-covered',true);

  r:=foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(
    'staging',now(),300,300
  );

  if r->>'coverageState'<>'normal'
     or r#>>'{incidentTransition,eventCreated}'<>'false'
     or r->>'automaticLayer102Reconciliation'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'layer96RerunPerformed'<>'false'
     or r->>'layer92RerunPerformed'<>'false' then
    raise exception 'Layer 104 sentinel invalid: %',r;
  end if;
end;
$l104_sentinel$;

reset role;


do $l104_summary$
declare r jsonb;
begin
  perform set_config('foundation.test_l104_state','normal',true);
  perform set_config('foundation.test_l104_reason','case-audit-layer102-covered',true);

  r:=foundation.get_case_audit_layer102_coverage_incident_summary_v1(
    'production',now(),300
  );

  if r->>'state'<>'normal'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0'
     or r->>'coverageState'<>'normal'
     or r->>'recommendedAction'<>'none'
     or r->>'automaticLayer102Reconciliation'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'layer96RerunPerformed'<>'false'
     or r->>'layer92RerunPerformed'<>'false' then
    raise exception 'Layer 104 summary invalid: %',r;
  end if;
end;
$l104_summary$;


do $l104_privileges$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_layer102_coverage_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_layer102_coverage_incident_events',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_layer102_coverage_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_layer102_coverage_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not pg_has_role('foundation_gateway','foundation_runtime','MEMBER')
     or exists(
       select 1
       from pg_proc p
       join pg_namespace n on n.oid=p.pronamespace
       cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
       join pg_roles rr on rr.oid=a.grantee
       where n.nspname='foundation'
         and p.proname='get_case_audit_layer102_coverage_incident_summary_v1'
         and rr.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_layer102_coverage_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_layer102_coverage_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_layer102_coverage_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_layer102_coverage_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'foundation.transition_case_audit_layer102_coverage_incident_v1(text,jsonb,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 104 privilege boundary invalid';
  end if;
end;
$l104_privileges$;


do $l104_append_only$
declare id uuid;
begin
  select event_id into id
  from foundation.case_audit_layer102_coverage_incident_events
  limit 1;

  begin
    update foundation.case_audit_layer102_coverage_incident_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 104 incident history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l104_append_only$;

rollback;
