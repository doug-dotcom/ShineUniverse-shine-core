begin;

-- Replace the Layer-78 reader transaction-locally with deterministic snapshots.
-- The original function is restored automatically by rollback.
create or replace function foundation.get_case_audit_safe_response_verification_coverage_v1(
  p_environment text default 'production',
  p_as_of timestamptz default now(),
  p_verification_grace_seconds integer default 300,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $l79_coverage_stub$
declare
  v_state text := coalesce(
    nullif(current_setting('foundation.test_l79_state',true),''),
    'normal'
  );
  v_reason text := nullif(
    current_setting('foundation.test_l79_reason',true),
    ''
  );
  v_problem integer := 0;
  v_execution integer := 1;
  v_items jsonb := '[]'::jsonb;
begin
  if v_reason is null then
    v_reason := case v_state
      when 'idle' then 'case-audit-safe-response-verification-no-executions'
      when 'normal' then 'case-audit-safe-response-verification-covered'
      when 'pending' then 'case-audit-safe-response-verification-within-grace'
      when 'gap' then 'case-audit-safe-response-verification-overdue'
      else 'case-audit-safe-response-verification-proof-invalid'
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
        'executionEventId','79000000-0000-4000-8000-000000000001',
        'incidentEventId','79000000-0000-4000-8000-000000000002',
        'actionKey','record-fresh-promotion-case-audit-observation',
        'coverageState',case
          when v_state='gap' then 'unverified'
          when v_state='invalid' then 'invalid'
          when v_state='pending' then 'pending'
          else 'verified'
        end,
        'reasonCode',v_reason,
        'verificationId',case
          when v_state in ('normal','invalid')
            then '79000000-0000-4000-8000-000000000003'
          else null
        end,
        'verificationState',case
          when v_state='normal' then 'verified'
          when v_state='invalid' then 'verified'
          else null
        end,
        'proofIntegrityVerified',case
          when v_state='invalid' then false
          when v_state='normal' then true
          else null
        end,
        'durableEvidenceId',case
          when v_state='normal'
            then '79000000-0000-4000-8000-000000000004'
          else null
        end,
        'durableEvidenceFingerprint',case
          when v_state='normal' then repeat('a',64)
          else null
        end
      )
    );
  end if;

  return jsonb_build_object(
    'foundationCaseAuditSafeResponseVerificationCoverage',
      'shine-foundation/case-audit-safe-response-verification-coverage-v1',
    'schemaVersion','1.0.0',
    'environment',p_environment,
    'evaluatedAt',p_as_of,
    'verificationGraceSeconds',p_verification_grace_seconds,
    'state',v_state,
    'reasonCode',v_reason,
    'executionCount',v_execution,
    'verificationRequiredCount',v_execution,
    'verificationProofCount',case
      when v_state in ('normal','invalid') then v_execution
      else 0
    end,
    'verifiedCount',case when v_state='normal' then 1 else 0 end,
    'pendingCount',case when v_state='pending' then 1 else 0 end,
    'unverifiedCount',case when v_state='gap' then 1 else 0 end,
    'missingEvidenceCount',0,
    'mismatchCount',0,
    'invalidProofCount',case when v_state='invalid' then 1 else 0 end,
    'problemCount',v_problem,
    'verificationCoveragePercent',case
      when v_execution=0 then 100.00
      when v_state in ('normal','invalid') then 100.00
      else 0.00
    end,
    'healthyVerificationPercent',case
      when v_execution=0 then 100.00
      when v_state='normal' then 100.00
      else 0.00
    end,
    'items',v_items,
    'onlyExecutedReceiptsRequireVerification',true,
    'proofIntegrityRecomputed',true,
    'targetReexecuted',false,
    'historyRewritePerformed',false,
    'releaseTruthMutationPerformed',false,
    'incidentHistoryMutationPerformed',false,
    'mutationPerformed',false
  );
end;
$l79_coverage_stub$;


do $l79_lifecycle$
declare
  t timestamptz := now();
  s jsonb;
  r jsonb;
  event_count integer;
begin
  perform set_config(
    'foundation.test_l79_state','gap',true
  );
  perform set_config(
    'foundation.test_l79_reason',
    'case-audit-safe-response-verification-overdue',
    true
  );

  s:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',t,300,100
  );
  r:=foundation.transition_case_audit_verify_incident_v1(
    'production',s,t,300
  );

  if r->>'eventType'<>'detected'
     or r->>'sourceState'<>'gap'
     or r->>'severity'<>'critical'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'1'
     or r->>'automaticVerification'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'targetReexecuted'<>'false' then
    raise exception 'Layer 79 first GAP sample invalid: %',r;
  end if;

  s:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',t+interval '301 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_incident_v1(
    'production',s,t+interval '301 seconds',300
  );

  if r->>'eventType'<>'opened'
     or r->>'activeIncidentCount'<>'1'
     or r->>'watchCount'<>'0'
     or (r->>'persistenceSeconds')::integer<300 then
    raise exception 'Layer 79 persistent GAP did not open: %',r;
  end if;

  select count(*) into event_count
  from foundation.case_audit_verify_incident_events;

  s:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',t+interval '360 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_incident_v1(
    'production',s,t+interval '360 seconds',300
  );

  if r->>'eventCreated'<>'false' then
    raise exception 'Layer 79 unchanged open evidence appended noise: %',r;
  end if;

  if (select count(*) from foundation.case_audit_verify_incident_events)
       <> event_count then
    raise exception 'Layer 79 unchanged open event count changed';
  end if;

  perform set_config(
    'foundation.test_l79_reason',
    'case-audit-safe-response-durable-evidence-missing',
    true
  );

  s:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',t+interval '361 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_incident_v1(
    'production',s,t+interval '361 seconds',300
  );

  if r->>'eventType'<>'changed'
     or r->>'reasonCode'<>
        'case-audit-safe-response-durable-evidence-missing'
     or r->>'activeIncidentCount'<>'1' then
    raise exception 'Layer 79 material evidence change invalid: %',r;
  end if;

  perform set_config(
    'foundation.test_l79_state','pending',true
  );
  perform set_config(
    'foundation.test_l79_reason',
    'case-audit-safe-response-verification-within-grace',
    true
  );

  s:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',t+interval '362 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_incident_v1(
    'production',s,t+interval '362 seconds',300
  );

  if r->>'eventType'<>'recovered'
     or r->>'sourceState'<>'pending'
     or r->>'severity'<>'info'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0' then
    raise exception 'Layer 79 pending coverage did not recover incident: %',r;
  end if;

  perform set_config(
    'foundation.test_l79_state','invalid',true
  );
  perform set_config(
    'foundation.test_l79_reason',
    'case-audit-safe-response-verification-proof-invalid',
    true
  );

  s:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',t+interval '363 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_incident_v1(
    'production',s,t+interval '363 seconds',300
  );

  if r->>'eventType'<>'detected'
     or r->>'sourceState'<>'invalid'
     or r->>'severity'<>'critical'
     or r->>'watchCount'<>'1' then
    raise exception 'Layer 79 INVALID watch invalid: %',r;
  end if;

  perform set_config(
    'foundation.test_l79_state','normal',true
  );
  perform set_config(
    'foundation.test_l79_reason',
    'case-audit-safe-response-verification-covered',
    true
  );

  s:=foundation.get_case_audit_safe_response_verification_coverage_v1(
    'production',t+interval '364 seconds',300,100
  );
  r:=foundation.transition_case_audit_verify_incident_v1(
    'production',s,t+interval '364 seconds',300
  );

  if r->>'eventType'<>'recovered'
     or r->>'sourceState'<>'normal'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0' then
    raise exception 'Layer 79 INVALID watch recovery invalid: %',r;
  end if;
end;
$l79_lifecycle$;


set local role service_role;

do $l79_sentinel$
declare
  r jsonb;
begin
  perform set_config(
    'foundation.test_l79_state','normal',true
  );
  perform set_config(
    'foundation.test_l79_reason',
    'case-audit-safe-response-verification-covered',
    true
  );

  r:=foundation.run_case_audit_verify_incident_sentinel_v1(
    'staging',now(),300,300
  );

  if r->>'coverageState'<>'normal'
     or r#>>'{incidentTransition,eventCreated}'<>'false'
     or r->>'automaticVerification'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'targetReexecuted'<>'false' then
    raise exception 'Layer 79 sentinel invalid: %',r;
  end if;
end;
$l79_sentinel$;

reset role;


do $l79_summary$
declare
  r jsonb;
begin
  perform set_config(
    'foundation.test_l79_state','normal',true
  );
  perform set_config(
    'foundation.test_l79_reason',
    'case-audit-safe-response-verification-covered',
    true
  );

  r:=foundation.get_case_audit_verify_incident_summary_v1(
    'production',now(),300
  );

  if r->>'state'<>'normal'
     or r->>'activeIncidentCount'<>'0'
     or r->>'watchCount'<>'0'
     or r->>'coverageState'<>'normal'
     or r->>'recommendedAction'<>'none'
     or r->>'automaticVerification'<>'false'
     or r->>'automaticRepair'<>'false'
     or r->>'targetReexecuted'<>'false' then
    raise exception 'Layer 79 summary invalid: %',r;
  end if;
end;
$l79_summary$;


do $l79_privileges$
begin
  if not has_function_privilege(
       'service_role',
       'foundation.run_case_audit_verify_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_runtime',
       'foundation.run_case_audit_verify_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'foundation_gateway',
       'foundation.run_case_audit_verify_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.run_case_audit_verify_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.run_case_audit_verify_incident_sentinel_v1(text,timestamptz,integer,integer)',
       'EXECUTE'
     )
     or has_table_privilege(
       'service_role',
       'foundation.case_audit_verify_incident_events',
       'INSERT'
     )
     or not has_function_privilege(
       'foundation_runtime',
       'foundation.get_case_audit_verify_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'foundation_gateway',
       'foundation.get_case_audit_verify_incident_summary_v1(text,timestamptz,integer)',
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
         and p.proname='get_case_audit_verify_incident_summary_v1'
         and r.rolname='foundation_gateway'
         and a.privilege_type='EXECUTE'
     )
     or has_function_privilege(
       'shine_core_control_plane',
       'foundation.get_case_audit_verify_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'shine_defence_runtime',
       'foundation.get_case_audit_verify_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'foundation.get_case_audit_verify_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'foundation.get_case_audit_verify_incident_summary_v1(text,timestamptz,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'foundation.transition_case_audit_verify_incident_v1(text,jsonb,timestamptz,integer)',
       'EXECUTE'
     ) then
    raise exception 'Layer 79 privilege boundary invalid';
  end if;
end;
$l79_privileges$;


do $l79_append_only$
declare
  id uuid;
begin
  select event_id into id
  from foundation.case_audit_verify_incident_events
  limit 1;

  begin
    update foundation.case_audit_verify_incident_events
    set reason_code='mutation'
    where event_id=id;
    raise exception 'Layer 79 incident history unexpectedly mutated';
  exception when sqlstate '55000' then
    null;
  end;
end;
$l79_append_only$;

rollback;
